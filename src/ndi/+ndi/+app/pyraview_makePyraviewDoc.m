function pyraview_doc = pyraview_makePyraviewDoc(probe, epochid, filterband, options)
    % PYRAVIEW_MAKEPYRAVIEWDOC - create a pyraview document for a probe and epoch
    %
    % PYRAVIEW_DOC = ndi.app.pyraview_makePyraviewDoc(PROBE, EPOCHID, FILTERBAND, ...)
    %
    % Inputs:
    %   PROBE: An ndi.probe object
    %   EPOCHID: The epoch identifier string
    %   FILTERBAND: 'low' or 'high'
    %
    % Optional Parameters:
    %   chunkDuration (default 50)
    %   chunkExcess (default 1)
    %
    arguments
        probe (1,1) {mustBeA(probe, 'ndi.probe')}
        epochid (1,:) char
        filterband (1,:) char {mustBeMember(filterband, {'low', 'high'})}
        options.chunkDuration (1,1) double = 50
        options.chunkExcess (1,1) double = 1
    end

    % 1. Get Epoch Information and check for 'dev_local_time'
    et = probe.epochtable();
    match_idx = find(strcmp({et.epoch_id}, epochid), 1);
    if isempty(match_idx)
        error(['Epoch ' epochid ' not found in probe ' probe.elementstring()]);
    end
    epoch_entry = et(match_idx);

    % Check for dev_local_time
    has_dev_local_time = false;
    t0 = 0;
    t1 = 0;

    % epoch_clock is a cell array of clocktypes
    for i = 1:numel(epoch_entry.epoch_clock)
        if strcmp(epoch_entry.epoch_clock{i}.type, 'dev_local_time')
            has_dev_local_time = true;
            t0 = epoch_entry.t0_t1{i}(1);
            t1 = epoch_entry.t0_t1{i}(2);
            break;
        end
    end

    if ~has_dev_local_time
        error('Epoch does not have ''dev_local_time'' clock type.');
    end

    % 2. Get Sampling Rate
    sr = probe.samplerate(epochid);

    % 3. Calculate Filter
    % [b,a] = cheby1(4,0.8,300/(0.5*sr),’high’)
    % Check if cheby1 exists (Signal Processing Toolbox)
    if exist('cheby1', 'file') || exist('cheby1', 'builtin')
        nyquist = 0.5 * sr;
        cutoff = 300 / nyquist;

        if cutoff >= 1
            warning('Filter cutoff frequency is >= Nyquist frequency. Adjusting to 0.99*Nyquist for stability.');
            cutoff = 0.99;
        end

        if strcmp(filterband, 'high')
             [b, a] = cheby1(4, 0.8, cutoff, 'high');
        else
             [b, a] = cheby1(4, 0.8, cutoff, 'low');
        end
    else
        warning('Signal Processing Toolbox not found. Using dummy filter coefficients.');
        b = 1; a = 1;
    end

    % 4. Prepare for Processing
    temp_dir = tempname;
    mkdir(temp_dir);
    [~, probe_name_clean] = fileparts(tempname); % get a random unique string
    prefix = fullfile(temp_dir, ['pyraview_' probe_name_clean]);

    steps = [100 10 10 10 10 10 10]; % Decimation steps
    nativeRate = sr;
    append = true;

    % 5. Loop and Process Chunks
    chunk_dur = options.chunkDuration;
    excess = options.chunkExcess;

    current_t = t0;

    while current_t < t1
        % Define read times with excess
        t_read_start = current_t - excess;
        t_read_end = current_t + chunk_dur + excess;

        % Read data
        % probe.readtimeseries(epochid, t0, t1)
        data = probe.readtimeseries(epochid, t_read_start, t_read_end);

        if ~isempty(data)
             % Filter data
             data = filter(b, a, data);

             % Calculate actual start time of data
             % readtimeseries typically clamps to valid range [t0, t1]
             data_start_time = max(t0, t_read_start);

             % We want central portion corresponding to [current_t, current_t + chunk_dur]
             % Calculate time offset from start of data
             offset_start = current_t - data_start_time;
             offset_end = (current_t + chunk_dur) - data_start_time;

             % Convert to samples
             % If offset is negative, it means we want data before what we have (shouldn't happen if logic is sound)
             % If offset is positive, we trim from beginning

             start_idx = round(offset_start * sr) + 1;
             end_idx = round(offset_end * sr);

             % Clamp indices
             if start_idx < 1, start_idx = 1; end
             if end_idx > size(data, 1), end_idx = size(data, 1); end

             if start_idx <= end_idx
                 data_central = data(start_idx:end_idx, :);

                 % Call Pyraview MEX
                 % status = pyraview(data, prefix, steps, nativeRate, [append], [numThreads])
                 % Using pyraview.pyraview as updated
                 try
                     pyraview.pyraview(data_central, prefix, steps, nativeRate, append);
                 catch mex_err
                     warning(['Pyraview MEX failed: ' mex_err.message]);
                 end
             end
        end

        current_t = current_t + chunk_dur;
    end

    % 6. Create Document
    % Create an ndi.document of type 'pyraview'

    pyraview_doc = ndi.document('pyraview');
    pyraview_doc = pyraview_doc.set_dependency_value('element_id', probe.id());
    pyraview_doc.document_properties.epochid = struct('epochid', epochid);
    pyraview_doc.document_properties.pyraview = struct();
    pyraview_doc.document_properties.pyraview.filter = struct('band', filterband, 'b', b, 'a', a);
    pyraview_doc.document_properties.pyraview.path = struct('prefix', prefix);

    % Note: We are NOT adding it to the database as per instructions.
end
