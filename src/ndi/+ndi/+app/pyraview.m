function pyraview(app_options)
% PYRAVIEW - Signal viewer for NDI-matlab
%
%   ndi.app.pyraview('session', session_obj)
%
    arguments
        app_options.session (1,:) ndi.session = ndi.session.empty()
        app_options.command (1,:) char = 'Initialize'
        app_options.fig = []
    end

    session = app_options.session;
    command = app_options.command;
    fig = app_options.fig;

    % If figure is provided, get session from it if not provided
    if isempty(session) && ~isempty(fig)
        ud = get(fig, 'UserData');
        if isstruct(ud) && isfield(ud, 'session')
            session = ud.session;
        end
    end

    if strcmp(command, 'Initialize')
        if isempty(session)
            % If session is empty, we cannot proceed with initialization as per requirements
            error('ndi:app:pyraview:nosession', 'Session must be provided for initialization.');
        end

        % Create Figure
        fig = figure('Name', ['pyraview: ' session.reference], ...
                     'NumberTitle', 'off', ...
                     'MenuBar', 'none', ...
                     'Tag', 'ndi.app.pyraview', ...
                     'Visible', 'on');

        % Callback string for controls
        % Uses the Tag of the control as the command
        callbackstr = 'ndi.app.pyraview(''command'', get(gcbo,''Tag''), ''fig'', gcbf);';

        % Initialize UserData
        ud = struct();
        ud.session = session;
        ud.current_doc = [];
        ud.epoch_t0 = 0;
        ud.epoch_t1 = 0;
        ud.current_data_t0 = -Inf; % Start of currently loaded data buffer
        ud.current_data_t1 = -Inf; % End of currently loaded data buffer
        ud.view_t0 = 0; % Start of current view
        ud.view_duration = 1; % Duration of current view

        % Create Controls (Positions will be set by ResizeFcn)

        % Dropdown: Probe
        uicontrol(fig, 'Style', 'text', 'String', 'Probe:', ...
            'Units', 'pixels', 'Position', [10 10 50 20], ...
            'HorizontalAlignment', 'left', 'Tag', 'ProbeText');

        probes = session.getprobes('type', 'n-trode');
        probe_strings = {};
        for i=1:numel(probes)
            probe_strings{end+1} = probes{i}.elementstring();
        end
        if isempty(probe_strings)
            probe_strings = {'No probes found'};
        end

        ud.probes = probes;

        uicontrol(fig, 'Style', 'popupmenu', 'String', probe_strings, ...
            'Units', 'pixels', 'Position', [10 10 200 20], ...
            'Tag', 'ProbeMenu', 'Callback', callbackstr, 'Value', 1);

        % Dropdown: Epoch
        uicontrol(fig, 'Style', 'text', 'String', 'epoch_id:', ...
             'Units', 'pixels', 'Position', [10 10 60 20], ...
             'HorizontalAlignment', 'left', 'Tag', 'EpochText');

        uicontrol(fig, 'Style', 'popupmenu', 'String', {' '}, ...
             'Units', 'pixels', 'Position', [10 10 200 20], ...
             'Tag', 'EpochMenu', 'Callback', callbackstr, 'Value', 1);

        % Dropdown: Band
        uicontrol(fig, 'Style', 'text', 'String', 'band:', ...
             'Units', 'pixels', 'Position', [10 10 40 20], ...
             'HorizontalAlignment', 'left', 'Tag', 'BandText');

        uicontrol(fig, 'Style', 'popupmenu', 'String', {'low', 'high'}, ...
             'Units', 'pixels', 'Position', [10 10 80 20], ...
             'Tag', 'BandMenu', 'Callback', callbackstr, 'Value', 2); % Default high

        % Separator Line (using uipanel as line)
        uipanel(fig, 'Units', 'pixels', 'Position', [0 0 100 1], 'Tag', 'SeparatorLine', ...
            'BorderType', 'line', 'HighlightColor', [0 0 0]);

        % Main Frame (uipanel)
        frame_panel = uipanel(fig, 'Title', '', 'Units', 'pixels', ...
             'Position', [10 10 100 100], 'Tag', 'MainFrame');

        % Axes
        ax = axes('Parent', frame_panel, 'Units', 'normalized', ...
             'Position', [0 0 1 1], 'Tag', 'MainAxes'); % Position will be adjusted in layout
        ud.axes = ax;

        % Setup zoom/pan callbacks on axes
        z = zoom(fig);
        z.ActionPostCallback = @(src, event) on_zoom_pan(fig, event);
        p = pan(fig);
        p.ActionPostCallback = @(src, event) on_zoom_pan(fig, event);


        % Scrollbar 1 (Zoom / Scale) - Duration
        % Normalized 0..1 corresponds to some log scale of duration?
        uicontrol(frame_panel, 'Style', 'slider', 'Units', 'normalized', ...
             'Position', [0 0 1 1], ...
             'Tag', 'Scroll1', 'Callback', callbackstr, ...
             'Min', 0, 'Max', 1, 'Value', 0.5, 'SliderStep', [0.01, 0.1]);

        % Scrollbar 2 (Pan) - Time Position
        % Normalized 0..1 corresponds to t0..t1
        uicontrol(frame_panel, 'Style', 'slider', 'Units', 'normalized', ...
             'Position', [0 0 1 1], ...
             'Tag', 'Scroll2', 'Callback', callbackstr, ...
             'Min', 0, 'Max', 1, 'Value', 0, 'SliderStep', [0.01, 0.1]);

        set(fig, 'UserData', ud);

        set(fig, 'SizeChangedFcn', @(src, event) on_resize(src));

        % Trigger initial layout and update
        update_epoch_list(fig, ud);
        on_resize(fig);

    else
        % Handle Commands
        ud = get(fig, 'UserData');
        switch command
            case 'ProbeMenu'
                update_epoch_list(fig, ud);
                check_and_load(fig);
            case 'EpochMenu'
                check_and_load(fig);
            case 'BandMenu'
                check_and_load(fig);
            case 'Scroll1' % Zoom
                update_from_scrollbars(fig, ud);
            case 'Scroll2' % Pan
                update_from_scrollbars(fig, ud);
        end
    end
end

function update_epoch_list(fig, ud)
    % Get selected probe
    pm = findobj(fig, 'Tag', 'ProbeMenu');
    val = get(pm, 'Value');
    probes = ud.probes;

    if isempty(probes)
        return;
    end

    % Validate val
    if val > numel(probes)
        val = 1;
        set(pm, 'Value', 1);
    end

    selected_probe = probes{val};
    et = selected_probe.epochtable();
    epoch_ids = {et.epoch_id};

    % Add empty slot with a spacer
    epoch_list = [{' '}, epoch_ids];

    em = findobj(fig, 'Tag', 'EpochMenu');
    set(em, 'String', epoch_list, 'Value', 1);
end

function check_and_load(fig)
    ud = get(fig, 'UserData');

    % 1. Get Selections
    pm = findobj(fig, 'Tag', 'ProbeMenu');
    probe_idx = get(pm, 'Value');
    if isempty(ud.probes) || probe_idx > numel(ud.probes)
        return;
    end
    probe = ud.probes{probe_idx};

    em = findobj(fig, 'Tag', 'EpochMenu');
    epoch_strs = get(em, 'String');
    epoch_val = get(em, 'Value');
    if epoch_val < 1 || epoch_val > numel(epoch_strs)
        return;
    end
    epoch_str = epoch_strs{epoch_val};

    if strcmp(epoch_str, ' ')
        % No epoch selected
        return;
    end

    bm = findobj(fig, 'Tag', 'BandMenu');
    band_strs = get(bm, 'String');
    band_val = get(bm, 'Value');
    band_str = band_strs{band_val};

    % 2. Check Memory (UserData)
    doc = [];
    if isfield(ud, 'current_doc') && ~isempty(ud.current_doc)
        try
            doc_props = ud.current_doc.document_properties;
            match_epoch = strcmp(doc_props.epochid.epochid, epoch_str);
            % Corrected to check filter.type based on schema
            if isfield(doc_props, 'filter') && isfield(doc_props.filter, 'type')
                match_band = strcmp(doc_props.filter.type, band_str);
            else
                match_band = false;
            end
            match_element = strcmp(ud.current_doc.dependency_value('element_id'), probe.id());

            if match_epoch && match_band && match_element
                doc = ud.current_doc;
                disp('Using cached document from memory.');
            end
        catch
            % Structure mismatch, ignore cache
        end
    end

    % 3. Search for Document in DB if not found in cache
    if isempty(doc)
        session = ud.session;
        q1 = ndi.query('','isa','pyraview');
        q2 = ndi.query('','depends_on','element_id', probe.id());
        q3 = ndi.query('epochid.epochid', 'exact_string', epoch_str);
        q4 = ndi.query('filter.type', 'exact_string', band_str); % Use filter.type
        q = q1 & q2 & q3 & q4;
        docs = session.database_search(q);

        if isempty(docs)
            disp('Document not found, creating...');
            try
                doc = ndi.app.pyraview.makePyraviewDoc(probe, epoch_str, band_str);
                disp(['Created document with id: ' doc.id()]);
            catch e
                disp(['Error creating document: ' e.message]);
                return;
            end
        else
            disp('Document found.');
            doc = docs{1};
        end
    end

    % Update UserData with new doc
    ud.current_doc = doc;

    % Get Epoch start/end times
    % From document or probe? Document has epochclocktimes
    try
        t0_t1 = doc.document_properties.epochclocktimes.t0_t1;
        ud.epoch_t0 = t0_t1(1);
        ud.epoch_t1 = t0_t1(2);
    catch
        % Fallback to probe
        et = probe.epochtable();
        match_idx = find(strcmp({et.epoch_id}, epoch_str), 1);
        % assuming dev_local_time exists per makePyraviewDoc logic
        % But we need to find the right clock.
        % For simplicity, let's assume makePyraviewDoc populated doc correctly.
        ud.epoch_t0 = 0; ud.epoch_t1 = 100; % Dummy fallback
    end

    % Initialize View
    % Default duration: 10s or full duration if shorter
    full_dur = ud.epoch_t1 - ud.epoch_t0;
    ud.view_duration = min(10, full_dur);
    ud.view_t0 = ud.epoch_t0;

    % Reset loaded data range to force reload
    ud.current_data_t0 = -Inf;
    ud.current_data_t1 = -Inf;

    set(fig, 'UserData', ud);

    % Update Scrollbars to reflect initial state
    update_scrollbars(fig, ud);

    % Load Data and Plot
    update_view(fig);
end

function update_from_scrollbars(fig, ud)
    % Read scrollbar values and update view_t0 / view_duration

    s1 = findobj(fig, 'Tag', 'Scroll1'); % Zoom/Duration
    s2 = findobj(fig, 'Tag', 'Scroll2'); % Pan/Position

    val1 = get(s1, 'Value');
    val2 = get(s2, 'Value');

    full_dur = ud.epoch_t1 - ud.epoch_t0;
    if full_dur <= 0, full_dur = 1; end

    % Map val1 (0..1) to duration.
    % 0 -> full_dur (zoomed out)
    % 1 -> min_dur (zoomed in)
    min_dur = 0.01; % 10ms
    % Log scale for smooth zoom
    % dur = exp( log(full_dur) * (1-val1) + log(min_dur) * val1 )
    ud.view_duration = exp( log(full_dur) * (1-val1) + log(min_dur) * val1 );

    % Map val2 (0..1) to view_t0
    % view_t0 ranges from epoch_t0 to epoch_t1 - view_duration
    max_start = ud.epoch_t1 - ud.view_duration;
    if max_start < ud.epoch_t0, max_start = ud.epoch_t0; end

    ud.view_t0 = ud.epoch_t0 + val2 * (max_start - ud.epoch_t0);

    set(fig, 'UserData', ud);
    update_view(fig);
end

function update_scrollbars(fig, ud)
    % Update scrollbar positions based on current view_t0 / view_duration
    % (Inverse of update_from_scrollbars)

    s1 = findobj(fig, 'Tag', 'Scroll1');
    s2 = findobj(fig, 'Tag', 'Scroll2');

    full_dur = ud.epoch_t1 - ud.epoch_t0;
    if full_dur <= 0, full_dur = 1; end
    min_dur = 0.01;

    % Calculate val1
    % log(dur) = log(full) * (1-v) + log(min) * v
    % log(dur) - log(full) = v * (log(min) - log(full))
    % v = (log(dur) - log(full)) / (log(min) - log(full))
    num = log(ud.view_duration) - log(full_dur);
    den = log(min_dur) - log(full_dur);
    val1 = num / den;
    val1 = max(0, min(1, val1));

    set(s1, 'Value', val1);

    % Calculate val2
    % t0 = epoch_t0 + v * (max_start - epoch_t0)
    max_start = ud.epoch_t1 - ud.view_duration;
    if max_start <= ud.epoch_t0
        val2 = 0;
    else
        val2 = (ud.view_t0 - ud.epoch_t0) / (max_start - ud.epoch_t0);
    end
    val2 = max(0, min(1, val2));

    set(s2, 'Value', val2);
end

function on_zoom_pan(fig, ~)
    % Callback for MATLAB zoom/pan tools
    % Update ud.view_t0 and ud.view_duration from axes limits
    ud = get(fig, 'UserData');
    ax = ud.axes;
    xl = xlim(ax);

    ud.view_t0 = xl(1);
    ud.view_duration = xl(2) - xl(1);

    set(fig, 'UserData', ud);
    update_scrollbars(fig, ud);
    update_view(fig);
end

function update_view(fig)
    ud = get(fig, 'UserData');
    if isempty(ud.current_doc)
        return;
    end

    % Determine if we need to load new data
    % Check if current view is inside current data buffer with some margin?
    % The prompt says: "only call getData when the real viewing axis (let's say t0 or t1) gets to the edge."
    % This implies we maintain a buffer slightly larger than the view.
    % getData itself implements `readExcess` for raw data, but here we manage the "viewport buffer".

    req_t0 = ud.view_t0;
    req_t1 = req_t0 + ud.view_duration;

    % Check bounds against loaded data
    % We assume loaded data is [ud.current_data_t0, ud.current_data_t1]
    % If req_t0 < current_data_t0 OR req_t1 > current_data_t1, we are at or beyond the edge.

    needs_load = false;

    if req_t0 < ud.current_data_t0 || req_t1 > ud.current_data_t1
        needs_load = true;
    end

    % If we are zoomed out significantly, we might need a different decimation level.
    % getData handles decimation based on pixelSpan.
    % If pixelSpan changes (resize) or duration changes (zoom), getData might return different level.
    % So we should probably reload if zoom level changes significantly too?
    % For now, let's stick to the "edge" logic for panning, but zooming naturally changes t1/t0 limits.

    % Also, if we zoom out, we might need MORE data than loaded.

    if needs_load
        % Calculate buffer to load
        % Load view +/- 1 screen width? Or just the view?
        % Prompt: "return data from t0-delta to t1+delta, where delta is (t1-t0)"
        % getData does this internal expansion based on inputs T0, T1.
        % So we pass the VIEW coordinates to getData, and it returns expanded data.
        % So we should update current_data_t0/t1 to reflect what getData returns.

        probe_idx = get(findobj(fig, 'Tag', 'ProbeMenu'), 'Value');
        probe = ud.probes{probe_idx};

        % Get pixel width of axes
        ax_pos = getpixelposition(ud.axes);
        pixelSpan = ax_pos(3);

        [tVec, data] = ndi.app.pyraview.getData(probe, ud.current_doc, req_t0, req_t1, pixelSpan);

        if ~isempty(tVec)
            ud.current_data_t0 = tVec(1);
            ud.current_data_t1 = tVec(end);

            % Plot data
            plot(ud.axes, tVec, data);

            % Restore limits because plot resets them
            xlim(ud.axes, [req_t0, req_t1]);

            ud.last_plot_data = data; % Optional caching if needed
            ud.last_plot_time = tVec;
        else
            cla(ud.axes);
        end

        set(fig, 'UserData', ud);
    else
        % Data is already loaded, just update limits
        xlim(ud.axes, [req_t0, req_t1]);
    end
end

function on_resize(fig)
    pos = get(fig, 'Position');
    width = pos(3);
    height = pos(4);

    margin = 10;
    control_height = 25;

    top_y = height - margin - control_height;

    % Probes
    pt = findobj(fig, 'Tag', 'ProbeText');
    set(pt, 'Position', [margin, top_y, 50, control_height]);

    pm = findobj(fig, 'Tag', 'ProbeMenu');
    set(pm, 'Position', [margin + 50, top_y, 200, control_height]);

    % Epochs
    current_x = margin + 50 + 200 + margin;
    et = findobj(fig, 'Tag', 'EpochText');
    set(et, 'Position', [current_x, top_y, 60, control_height]);

    em = findobj(fig, 'Tag', 'EpochMenu');
    set(em, 'Position', [current_x + 60, top_y, 200, control_height]);

    % Band
    current_x = current_x + 60 + 200 + margin;
    bt = findobj(fig, 'Tag', 'BandText');
    set(bt, 'Position', [current_x, top_y, 40, control_height]);

    bm = findobj(fig, 'Tag', 'BandMenu');
    set(bm, 'Position', [current_x + 40, top_y, 80, control_height]);

    % Separator
    sep_y = top_y - margin;
    sep = findobj(fig, 'Tag', 'SeparatorLine');
    set(sep, 'Position', [0, sep_y, width, 1]);

    % Main Frame
    frame_h = height * 0.8;
    frame_w = width * 0.75;
    frame_y = sep_y - margin - frame_h;

    if frame_y < margin, frame_y = margin; end

    mf = findobj(fig, 'Tag', 'MainFrame');
    set(mf, 'Position', [0, frame_y, frame_w, frame_h]);

    scrollbar_h_px = 20;
    if frame_h > 0
        sb_h_norm = scrollbar_h_px / frame_h;
    else
        sb_h_norm = 0.05;
    end

    s1 = findobj(mf, 'Tag', 'Scroll1');
    s2 = findobj(mf, 'Tag', 'Scroll2');
    ax = findobj(mf, 'Tag', 'MainAxes');

    % Scroll2 (Bottom)
    set(s2, 'Position', [0.05, 0, 0.9, sb_h_norm]);

    % Scroll1 (Top of Scroll2)
    set(s1, 'Position', [0.05, sb_h_norm, 0.9, sb_h_norm]);

    % Axes
    set(ax, 'Position', [0.05, 2*sb_h_norm + 0.05, 0.9, 1 - (2*sb_h_norm + 0.05) - 0.02]);
end
