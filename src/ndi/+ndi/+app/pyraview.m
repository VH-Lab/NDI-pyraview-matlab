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
        callbackstr = 'ndi.app.pyraview(''command'', get(gcbo,''Tag''), ''fig'', gcbf); drawnow limitrate;';

        % Initialize UserData
        ud = struct();
        ud.session = session;
        ud.current_doc = [];
        ud.epoch_t0 = 0;
        ud.epoch_t1 = 0;
        ud.current_data_t0 = -Inf; % Start of currently loaded data buffer
        ud.current_data_t1 = -Inf; % End of currently loaded data buffer
        ud.current_data = []; % Store loaded data
        ud.current_time = []; % Store loaded time
        ud.current_level = []; % Store loaded level
        ud.loaded_pixel_span = 0; % Store pixel span used for loading
        ud.loaded_view_duration = Inf; % Store duration used for loading
        ud.view_t0 = 0; % Start of current view
        ud.view_duration = 1; % Duration of current view
        ud.channel_y_spacing = 100; % Default spacing
        ud.spiking_info = struct('element_obj', {}, 'neuron_doc', {}, 'label', {}, 'color', {}); % Store spiking info
        ud.first_plot = true; % Flag for first plot
        ud.split_position = 0.8; % Default split position (80% for Main)
        ud.dragging = false;
        ud.last_mode = ''; % Store mode before drag

        % Create Controls (Positions will be set by ResizeFcn)

        % Dropdown: Probe
        uicontrol(fig, 'Style', 'text', 'String', 'Probe:', ...
            'Units', 'pixels', 'Position', [10 10 50 20], ...
            'HorizontalAlignment', 'left', 'Tag', 'ProbeText', ...
            'FontWeight', 'bold', 'FontSize', 14);

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
            'Tag', 'ProbeMenu', 'Callback', callbackstr, 'Value', 1, ...
            'FontSize', 14);

        % Dropdown: Epoch
        uicontrol(fig, 'Style', 'text', 'String', 'epoch_id:', ...
             'Units', 'pixels', 'Position', [10 10 60 20], ...
             'HorizontalAlignment', 'left', 'Tag', 'EpochText', ...
             'FontWeight', 'bold', 'FontSize', 14);

        uicontrol(fig, 'Style', 'popupmenu', 'String', {' '}, ...
             'Units', 'pixels', 'Position', [10 10 200 20], ...
             'Tag', 'EpochMenu', 'Callback', callbackstr, 'Value', 1, ...
             'FontSize', 14);

        % Dropdown: Band
        uicontrol(fig, 'Style', 'text', 'String', 'band:', ...
             'Units', 'pixels', 'Position', [10 10 40 20], ...
             'HorizontalAlignment', 'left', 'Tag', 'BandText', ...
             'FontWeight', 'bold', 'FontSize', 14);

        uicontrol(fig, 'Style', 'popupmenu', 'String', {'low', 'high'}, ...
             'Units', 'pixels', 'Position', [10 10 80 20], ...
             'Tag', 'BandMenu', 'Callback', callbackstr, 'Value', 2, ...
             'FontSize', 14); % Default high

        % Edit: Channel Spacing
        uicontrol(fig, 'Style', 'text', 'String', 'Spacing:', ...
             'Units', 'pixels', 'Position', [10 10 60 20], ...
             'HorizontalAlignment', 'left', 'Tag', 'SpacingText', ...
             'FontWeight', 'bold', 'FontSize', 14);

        uicontrol(fig, 'Style', 'edit', 'String', '100', ...
             'Units', 'pixels', 'Position', [10 10 50 20], ...
             'Tag', 'SpacingEdit', 'Callback', callbackstr, ...
             'FontSize', 14);

        % Mapping
        uicontrol(fig, 'Style', 'text', 'String', 'Mapping:', ...
             'Units', 'pixels', 'Position', [10 10 60 20], ...
             'HorizontalAlignment', 'left', 'Tag', 'MappingText', ...
             'FontWeight', 'bold', 'FontSize', 14);

        uicontrol(fig, 'Style', 'popupmenu', 'String', {'raw', 'PlexonSV'}, ...
             'Units', 'pixels', 'Position', [10 10 100 20], ...
             'Tag', 'MappingMenu', 'Callback', callbackstr, 'Value', 1, ...
             'FontSize', 14);

        % Checkbox: Show spiking units
        uicontrol(fig, 'Style', 'checkbox', 'String', 'Show spiking units', ...
             'Units', 'pixels', 'Position', [10 10 200 20], ...
             'Tag', 'SpikingCheckbox', 'Callback', callbackstr, ...
             'FontWeight', 'bold', 'FontSize', 14, 'Value', 0);

        % Separator Line (using uipanel as line)
        uipanel(fig, 'Units', 'pixels', 'Position', [0 0 100 1], 'Tag', 'SeparatorLine', ...
            'BorderType', 'line', 'HighlightColor', [0 0 0]);

        % Main Frame (uipanel)
        frame_panel = uipanel(fig, 'Title', '', 'Units', 'pixels', ...
             'Position', [10 10 100 100], 'Tag', 'MainFrame');

        % Axes
        ax = axes('Parent', frame_panel, 'Units', 'normalized', ...
             'Position', [0 0 1 1], 'Tag', 'MainAxes'); % Position will be adjusted in layout
        xlabel(ax, 'Time (s)');
        ud.axes = ax;

        % Spiking Units Frame
        sf = uipanel(fig, 'Title', '', 'Units', 'pixels', ...
             'Position', [10 10 100 100], 'Tag', 'SpikingFrame', 'Visible', 'off');

        % Split Dragger (uicontrol, visible only when Spiking is on)
        % Using 'text' style for simple bar, or 'pushbutton'
        uicontrol(fig, 'Style', 'text', 'String', '', ...
             'Units', 'pixels', 'Position', [0 0 5 100], ...
             'Tag', 'SplitDragger', 'BackgroundColor', [0.8 0.8 0.8], ...
             'Enable', 'inactive', 'ButtonDownFcn', @(src,ev) start_drag(src,ev), ...
             'Visible', 'off');

        % Spiking Axes
        sax = axes('Parent', sf, 'Units', 'normalized', ...
             'Position', [0 0 0.6 1], 'Tag', 'SpikingAxes');
        ud.spiking_axes = sax;

        % Spiking Title
        uicontrol(sf, 'Style', 'text', 'String', 'Spiking neurons', ...
             'Units', 'normalized', 'Position', [0.6 0.9 0.4 0.1], ...
             'Tag', 'SpikingTitle', 'FontWeight', 'bold');

        % Spiking Listbox
        uicontrol(sf, 'Style', 'listbox', 'String', {}, ...
             'Units', 'normalized', 'Position', [0.6 0 0.4 0.9], ...
             'Tag', 'SpikingList', 'Callback', callbackstr);

        % Link Y Axes
        linkaxes([ax, sax], 'y');

        % Setup zoom/pan callbacks on axes
        z = zoom(fig);
        z.ActionPostCallback = @(src, event) on_zoom_pan(fig, event);
        p = pan(fig);
        p.ActionPostCallback = @(src, event) on_zoom_pan(fig, event);


        % Scrollbar 1 (Top) - Pan
        s1 = uicontrol(frame_panel, 'Style', 'slider', 'Units', 'normalized', ...
             'Position', [0 0 1 1], ...
             'Tag', 'Scroll1', 'Callback', callbackstr, ...
             'Min', 0, 'Max', 1, 'Value', 0, 'SliderStep', [0.01, 0.1]);
        addlistener(s1, 'ContinuousValueChange', @(src,ev) continuous_callback(src, fig));

        % Scrollbar 2 (Bottom) - Zoom
        s2 = uicontrol(frame_panel, 'Style', 'slider', 'Units', 'normalized', ...
             'Position', [0 0 1 1], ...
             'Tag', 'Scroll2', 'Callback', callbackstr, ...
             'Min', 0, 'Max', 1, 'Value', 0.5, 'SliderStep', [1/200, 10/200]);
        addlistener(s2, 'ContinuousValueChange', @(src,ev) continuous_callback(src, fig));

        % Toggle Buttons: Pan / Zoom
        uicontrol(frame_panel, 'Style', 'togglebutton', 'String', 'Pan', ...
             'Units', 'normalized', 'Position', [0.8 0.05 0.1 0.05], ...
             'Tag', 'PanButton', 'Callback', callbackstr, 'Value', 1); % Default Pan

        uicontrol(frame_panel, 'Style', 'togglebutton', 'String', 'Zoom', ...
             'Units', 'normalized', 'Position', [0.9 0.05 0.1 0.05], ...
             'Tag', 'ZoomButton', 'Callback', callbackstr, 'Value', 0);

        set(fig, 'UserData', ud);

        set(fig, 'SizeChangedFcn', @(src, event) on_resize(src));

        % Activate Pan mode initially
        pan(fig, 'on'); zoom(fig, 'off');

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
            case 'SpacingEdit'
                update_spacing(fig);
            case 'MappingMenu'
                plot_data(fig);
            case 'SpikingCheckbox'
                on_resize(fig);
                val = get(findobj(fig, 'Tag', 'SpikingCheckbox'), 'Value');
                if val
                    % Load data via external function
                    pm = findobj(fig, 'Tag', 'ProbeMenu');
                    probe_idx = get(pm, 'Value');

                    % Get epochid
                    em = findobj(fig, 'Tag', 'EpochMenu');
                    epoch_strs = get(em, 'String');
                    epoch_val = get(em, 'Value');
                    epoch_str = '';
                    if ~isempty(epoch_strs) && epoch_val <= numel(epoch_strs)
                        epoch_str = epoch_strs{epoch_val};
                    end

                    if ~isempty(ud.probes) && probe_idx <= numel(ud.probes) && ~strcmp(epoch_str, ' ')
                        probe = ud.probes{probe_idx};

                        % Load and process colors
                        spiking_info = ndi.app.pyraview.load_spiking_neurons(ud.session, probe, epoch_str);

                        % Assign Colors Grouped by Best Channel
                        if ~isempty(spiking_info)
                            color_cycle = {'k', 'm', 'b', 'g', [1 0.5 0], 'r'};

                            for k = 1:numel(spiking_info)
                                color_idx = mod(k-1, numel(color_cycle)) + 1;
                                spiking_info(k).color = color_cycle{color_idx};
                            end
                        end

                        ud.spiking_info = spiking_info;
                        set(fig, 'UserData', ud);
                        update_spiking_list_ui(fig);
                    end
                end
            case 'SpikingList'
                update_spiking_plot(fig);
                plot_data(fig); % Re-plot main axes to show spikes overlay
            case 'Scroll1' % Pan
                update_from_scrollbars(fig, ud);
            case 'Scroll2' % Zoom
                update_from_scrollbars(fig, ud);
            case 'PanButton'
                set(findobj(fig, 'Tag', 'PanButton'), 'Value', 1);
                set(findobj(fig, 'Tag', 'ZoomButton'), 'Value', 0);
                pan(fig, 'on'); zoom(fig, 'off');
            case 'ZoomButton'
                set(findobj(fig, 'Tag', 'PanButton'), 'Value', 0);
                set(findobj(fig, 'Tag', 'ZoomButton'), 'Value', 1);
                zoom(fig, 'on'); pan(fig, 'off');
        end
    end
end

function start_drag(src, ~)
    fig = ancestor(src, 'figure');
    ud = get(fig, 'UserData');
    ud.dragging = true;

    % Disable Pan/Zoom temporarily to allow drag
    p = pan(fig);
    z = zoom(fig);

    ud.last_mode = '';
    if strcmp(p.Enable, 'on')
        ud.last_mode = 'pan';
        pan(fig, 'off');
    elseif strcmp(z.Enable, 'on')
        ud.last_mode = 'zoom';
        zoom(fig, 'off');
    end

    set(fig, 'UserData', ud);
    set(fig, 'WindowButtonMotionFcn', @(s,e) drag_split(s,e));
    set(fig, 'WindowButtonUpFcn', @(s,e) stop_drag(s,e));
end

function drag_split(fig, ~)
    ud = get(fig, 'UserData');
    if ~ud.dragging, return; end

    pos = get(fig, 'CurrentPoint');
    fig_pos = get(fig, 'Position');
    width = fig_pos(3);

    % Calculate ratio (CurrentPoint is relative to bottom-left)
    ratio = pos(1) / width;

    % Clamp
    ratio = max(0.2, min(0.9, ratio));

    ud.split_position = ratio;
    set(fig, 'UserData', ud);
    on_resize(fig);
end

function stop_drag(fig, ~)
    ud = get(fig, 'UserData');
    ud.dragging = false;
    set(fig, 'UserData', ud);

    % Clear callbacks FIRST
    set(fig, 'WindowButtonMotionFcn', '');
    set(fig, 'WindowButtonUpFcn', '');

    % Restore mode SECOND
    if strcmp(ud.last_mode, 'pan')
        pan(fig, 'on');
    elseif strcmp(ud.last_mode, 'zoom')
        zoom(fig, 'on');
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

    if val > numel(probes)
        val = 1;
        set(pm, 'Value', 1);
    end

    selected_probe = probes{val};
    et = selected_probe.epochtable();
    epoch_ids = {et.epoch_id};

    epoch_list = [{' '}, epoch_ids];

    em = findobj(fig, 'Tag', 'EpochMenu');
    set(em, 'String', epoch_list, 'Value', 1);
end

function check_and_load(fig)
    ud = get(fig, 'UserData');

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
        return;
    end

    bm = findobj(fig, 'Tag', 'BandMenu');
    band_strs = get(bm, 'String');
    band_val = get(bm, 'Value');
    band_str = band_strs{band_val};

    doc = [];
    if isfield(ud, 'current_doc') && ~isempty(ud.current_doc)
        try
            doc_props = ud.current_doc.document_properties;
            match_epoch = strcmp(doc_props.epochid.epochid, epoch_str);
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
        end
    end

    if isempty(doc)
        session = ud.session;
        q1 = ndi.query('','isa','pyraview');
        q2 = ndi.query('','depends_on','element_id', probe.id());
        q3 = ndi.query('epochid.epochid', 'exact_string', epoch_str);
        q4 = ndi.query('filter.type', 'exact_string', band_str);
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

    ud.current_doc = doc;

    try
        t0_t1 = doc.document_properties.epochclocktimes.t0_t1;
        ud.epoch_t0 = t0_t1(1);
        ud.epoch_t1 = t0_t1(2);
    catch
        ud.epoch_t0 = 0; ud.epoch_t1 = 100;
    end

    full_dur = ud.epoch_t1 - ud.epoch_t0;
    ud.view_duration = min(10, full_dur);
    ud.view_t0 = ud.epoch_t0;

    ud.current_data_t0 = -Inf;
    ud.current_data_t1 = -Inf;
    ud.loaded_pixel_span = 0;
    ud.loaded_view_duration = Inf;
    ud.first_plot = true; % Reset Y-axis scale on new data

    set(fig, 'UserData', ud);

    update_scrollbars(fig, ud);
    update_view(fig);

    % Check for spiking
    cb = findobj(fig, 'Tag', 'SpikingCheckbox');
    if get(cb, 'Value')
        ud.spiking_info = ndi.app.pyraview.load_spiking_neurons(ud.session, probe, epoch_str);
        set(fig, 'UserData', ud);
        update_spiking_list_ui(fig);
    end
end

function update_spiking_list_ui(fig)
    ud = get(fig, 'UserData');
    spiking_info = ud.spiking_info;

    strs = {spiking_info.label};

    lb = findobj(fig, 'Tag', 'SpikingList');
    set(lb, 'String', strs);
    set(lb, 'Max', max(2, numel(strs))); % Allow multiple selection
    if ~isempty(strs)
        set(lb, 'Value', 1:numel(strs));
    else
        set(lb, 'Value', []);
    end

    update_spiking_plot(fig);
    plot_data(fig); % Update main plot to include spikes
end

function update_spiking_plot(fig)
    ud = get(fig, 'UserData');
    lb = findobj(fig, 'Tag', 'SpikingList');

    selectedIdx = get(lb, 'Value');
    spiking_info = ud.spiking_info;

    sax = ud.spiking_axes;
    cla(sax);

    if isempty(selectedIdx) || isempty(spiking_info)
        return;
    end

    spacing = ud.channel_y_spacing;

    % Prepare plotting arrays
    X = [];
    Y = [];
    text_labels = struct('x', {}, 'y_top', {}, 'y_bot', {}, 'str', {});

    % Loop through selected
    for k = 1:numel(selectedIdx)
        idx = selectedIdx(k);
        if idx > numel(spiking_info), continue; end

        info = spiking_info(idx);
        doc = info.neuron_doc;

        if isempty(doc) || ~isfield(doc.document_properties, 'neuron_extracellular') || ...
           ~isfield(doc.document_properties.neuron_extracellular, 'mean_waveform')
            continue;
        end

        waveform = doc.document_properties.neuron_extracellular.mean_waveform; % N x C
        [numSamples, numChannels] = size(waveform);

        % Normalize X to 0..1 for this neuron slot k
        % k corresponds to x-range [k-1+0.25, k-1+0.75]
        t = linspace(-0.25, 0.25, numSamples)';
        t_shifted = idx + t;

        color = 'k';
        if isfield(info, 'color') && ~isempty(info.color)
            color = info.color;
        end

        % Plot channels stacked
        for c = 1:numChannels
            offset = (c-1) * spacing;

            % Plot directly to avoid huge array for colors
            % Optimization: Plot each neuron separately in side panel is fine
            % But user asked for color grouping
            % Side panel usually handles individual plots ok since N is small

            plot(sax, t_shifted, waveform(:,c) + offset, 'Color', color);
            hold(sax, 'on');
        end

        % Labels
        label_idx = num2str(idx);
        text_labels(end+1).x = idx;
        text_labels(end).y_top = (numChannels+0.5)*spacing;
        text_labels(end).y_bot = -0.5*spacing;
        text_labels(end).str = label_idx;
    end

    for t = 1:numel(text_labels)
        text(sax, text_labels(t).x, text_labels(t).y_top, text_labels(t).str, 'HorizontalAlignment', 'center');
        text(sax, text_labels(t).x, text_labels(t).y_bot, text_labels(t).str, 'HorizontalAlignment', 'center');
    end
    hold(sax, 'off');

    xlim(sax, [0, max(numel(spiking_info), 1) + 1]);
end

function update_spacing(fig)
    ud = get(fig, 'UserData');
    se = findobj(fig, 'Tag', 'SpacingEdit');
    str = get(se, 'String');
    val = str2double(str);
    if isnan(val)
        val = 100;
        set(se, 'String', '100');
    end
    ud.channel_y_spacing = val;
    set(fig, 'UserData', ud);
    plot_data(fig); % Re-plot without reloading data

    % Update spiking plot if visible
    if strcmp(get(findobj(fig, 'Tag', 'SpikingFrame'), 'Visible'), 'on')
        update_spiking_plot(fig);
    end
end

function update_from_scrollbars(fig, ud)
    % Read scrollbar values and update view_t0 / view_duration

    s1 = findobj(fig, 'Tag', 'Scroll1'); % Pan
    s2 = findobj(fig, 'Tag', 'Scroll2'); % Zoom

    val_pan = get(s1, 'Value');
    val_zoom = get(s2, 'Value');

    full_dur = ud.epoch_t1 - ud.epoch_t0;
    if full_dur <= 0, full_dur = 1; end

    % ZOOM Logic: Maintain center time
    % Calculate old center
    center_t = ud.view_t0 + ud.view_duration / 2;

    % New Duration
    W_max = 2592000;
    W_min = 0.001;
    N = 200;

    s = round(val_zoom * N);

    exponent = (N - s) / N;
    new_duration = W_min * (W_max / W_min)^exponent;
    ud.view_duration = new_duration;

    % New T0 based on old center
    new_t0 = center_t - new_duration / 2;

    % Clamp T0 to epoch bounds
    if new_t0 < ud.epoch_t0
        new_t0 = ud.epoch_t0;
    end
    if new_t0 + new_duration > ud.epoch_t1
        new_t0 = ud.epoch_t1 - new_duration;
    end
    % If duration > full epoch (shouldn't happen with logic above), clamp t0
    if new_t0 < ud.epoch_t0
        new_t0 = ud.epoch_t0;
    end

    ud.view_t0 = new_t0;

    % Update Pan Scrollbar to match new T0 (because we shifted T0)

    obj = gcbo;
    if ~isempty(obj)
        tag = get(obj, 'Tag');
        if strcmp(tag, 'Scroll1') % Pan
            % Standard Pan Logic
            max_start = ud.epoch_t1 - ud.view_duration;
            if max_start < ud.epoch_t0, max_start = ud.epoch_t0; end
            ud.view_t0 = ud.epoch_t0 + val_pan * (max_start - ud.epoch_t0);
        elseif strcmp(tag, 'Scroll2') % Zoom
            % Already handled above (Center Logic)
        end
    end

    set(fig, 'UserData', ud);
    update_view(fig);
end

function continuous_callback(src, fig)
    ndi.app.pyraview('command', get(src, 'Tag'), 'fig', fig);
    drawnow limitrate;
end

function update_scrollbars(fig, ud)
    s1 = findobj(fig, 'Tag', 'Scroll1');
    s2 = findobj(fig, 'Tag', 'Scroll2');

    full_dur = ud.epoch_t1 - ud.epoch_t0;
    if full_dur <= 0, full_dur = 1; end

    % Calculate val_zoom (Scroll2)
    W_max = 2592000;
    W_min = 0.001;
    N = 200;

    exponent_ideal = log(ud.view_duration / W_min) / log(W_max / W_min);
    s_ideal = N * (1 - exponent_ideal);
    s = round(s_ideal);
    val_zoom = s / N;

    val_zoom = max(0, min(1, val_zoom));

    set(s2, 'Value', val_zoom);

    % Calculate val_pan (Scroll1)
    max_start = ud.epoch_t1 - ud.view_duration;
    if max_start <= ud.epoch_t0
        val_pan = 0;
    else
        val_pan = (ud.view_t0 - ud.epoch_t0) / (max_start - ud.epoch_t0);
    end
    val_pan = max(0, min(1, val_pan));

    set(s1, 'Value', val_pan);
end

function on_zoom_pan(fig, ~)
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

    req_t0 = ud.view_t0;
    req_t1 = req_t0 + ud.view_duration;

    needs_load = false;

    % Edge check
    if req_t0 < ud.current_data_t0 || req_t1 > ud.current_data_t1
        needs_load = true;
    end

    % Resolution check
    ax_pos = getpixelposition(ud.axes);
    current_pixel_span = ax_pos(3);

    if abs(current_pixel_span - ud.loaded_pixel_span) / ud.loaded_pixel_span > 0.1
        needs_load = true;
    end

    if ud.view_duration < ud.loaded_view_duration * 0.8
        needs_load = true;
    end

    if needs_load
        probe_idx = get(findobj(fig, 'Tag', 'ProbeMenu'), 'Value');
        probe = ud.probes{probe_idx};

        [tVec, data, level] = ndi.app.pyraview.getData(probe, ud.current_doc, req_t0, req_t1, current_pixel_span);

        if ~isempty(tVec)
            ud.current_data_t0 = tVec(1);
            ud.current_data_t1 = tVec(end);
            ud.current_data = data;
            ud.current_time = tVec;
            ud.current_level = level;
            ud.loaded_pixel_span = current_pixel_span;
            ud.loaded_view_duration = ud.view_duration;

            set(fig, 'UserData', ud);
            plot_data(fig);
        else
            cla(ud.axes);
        end
    else
        xlim(ud.axes, [req_t0, req_t1]);
    end

    update_scrollbars(fig, ud);
end

function plot_data(fig)
    ud = get(fig, 'UserData');

    data = ud.current_data;
    tVec = ud.current_time;
    level = ud.current_level;
    spacing = ud.channel_y_spacing;

    if isempty(data)
        cla(ud.axes);
        return;
    end

    % Get Mapping
    mm = findobj(fig, 'Tag', 'MappingMenu');
    maps = get(mm, 'String');
    map_val = get(mm, 'Value');
    mapping_name = maps{map_val};

    numChannels = size(data, 2);
    try
        mapping = ndi.app.pyraview.mappings(1:numChannels, mapping_name);
    catch e
        warning('Mapping error: %s', e.message);
        mapping = [];
    end

    % Store previous YLim if not first plot
    if ~ud.first_plot
        yl_old = ylim(ud.axes);
    else
        yl_old = [];
    end

    % Pass mapping to transform function
    [X, Y] = ndi.app.pyraview.transformPlotData(data, tVec, level, spacing, mapping);

    plot(ud.axes, X, Y);
    hold(ud.axes, 'on');

    % Plot Spikes if available
    lb = findobj(fig, 'Tag', 'SpikingList');
    if ~isempty(lb) && ~isempty(ud.spiking_info)
        selectedIdx = get(lb, 'Value');
        if ~isempty(selectedIdx)
            % Group by Color
            % Extract colors for selected indices
            % Since color is string or array, tricky to use 'unique' directly if mixed
            % But we used standard set.
            % Map color to string key for grouping

            groups = containers.Map();

            for idx = selectedIdx
                if idx > numel(ud.spiking_info), continue; end
                info = ud.spiking_info(idx);

                col = 'k';
                if isfield(info, 'color') && ~isempty(info.color)
                    col = info.color;
                end

                % Convert to key
                if ischar(col)
                    key = col;
                else
                    key = mat2str(col);
                end

                if ~isKey(groups, key)
                    groups(key) = idx;
                else
                    groups(key) = [groups(key), idx];
                end
            end

            keys = groups.keys;
            for i = 1:numel(keys)
                key = keys{i};
                idxs = groups(key);

                % Recover color from key or first item
                % Simplest: use key if char, else eval
                if key(1) == '['
                    col = eval(key);
                else
                    col = key;
                end

                [sX, sY] = ndi.app.pyraview.transformSpikeData(ud.spiking_info, idxs, ud.view_t0, ud.view_t0 + ud.view_duration, spacing);
                if ~isempty(sX)
                    plot(ud.axes, sX, sY, 'Color', col, 'LineWidth', 2);
                end
            end
        end
    end
    hold(ud.axes, 'off');

    % Restore X limits
    xlim(ud.axes, [ud.view_t0, ud.view_t0 + ud.view_duration]);

    % Restore Y limits if preserved
    if ~isempty(yl_old)
        ylim(ud.axes, yl_old);
    else
        ud.first_plot = false;
        set(fig, 'UserData', ud);
    end
end

function on_resize(fig)
    pos = get(fig, 'Position');
    width = pos(3);
    height = pos(4);

    margin = 10;
    control_height = 25;

    top_y = height - margin - control_height;

    % Controls Layout
    pt = findobj(fig, 'Tag', 'ProbeText');
    pm = findobj(fig, 'Tag', 'ProbeMenu');
    set(pt, 'Position', [margin, top_y, 50, control_height]);
    set(pm, 'Position', [margin + 50, top_y, 200, control_height]);

    current_x = margin + 50 + 200 + margin;
    et = findobj(fig, 'Tag', 'EpochText');
    em = findobj(fig, 'Tag', 'EpochMenu');
    set(et, 'Position', [current_x, top_y, 60, control_height]);
    set(em, 'Position', [current_x + 60, top_y, 200, control_height]);

    % Row 1 continued: Band | Spacing
    current_x = current_x + 60 + 200 + margin;
    bt = findobj(fig, 'Tag', 'BandText');
    bm = findobj(fig, 'Tag', 'BandMenu');
    set(bt, 'Position', [current_x, top_y, 40, control_height]);
    set(bm, 'Position', [current_x + 40, top_y, 80, control_height]);

    current_x = current_x + 40 + 80 + margin;
    st = findobj(fig, 'Tag', 'SpacingText');
    se = findobj(fig, 'Tag', 'SpacingEdit');
    set(st, 'Position', [current_x, top_y, 60, control_height]);
    set(se, 'Position', [current_x + 60, top_y, 50, control_height]);

    current_x = current_x + 60 + 50 + margin;
    mt = findobj(fig, 'Tag', 'MappingText');
    mm = findobj(fig, 'Tag', 'MappingMenu');
    set(mt, 'Position', [current_x, top_y, 60, control_height]);
    set(mm, 'Position', [current_x + 60, top_y, 100, control_height]);

    current_x = current_x + 60 + 100 + margin;
    sc = findobj(fig, 'Tag', 'SpikingCheckbox');
    set(sc, 'Position', [current_x, top_y, 200, control_height]);

    % Separator
    sep_y = top_y - margin;
    sep = findobj(fig, 'Tag', 'SeparatorLine');
    set(sep, 'Position', [0, sep_y, width, 1]);

    % Frames
    % Main Frame hugs bottom (0) and separator (sep_y)
    frame_y = 0;
    frame_h = sep_y;

    % Check Spiking Checkbox
    show_spiking = get(sc, 'Value');
    ud = get(fig, 'UserData');
    split = ud.split_position;

    mf = findobj(fig, 'Tag', 'MainFrame');
    sf = findobj(fig, 'Tag', 'SpikingFrame');
    sd = findobj(fig, 'Tag', 'SplitDragger');

    if show_spiking
        main_w = width * split;
        spiking_w = width * (1 - split);
        dragger_w = 5;

        set(mf, 'Position', [0, frame_y, main_w, frame_h]);
        set(sf, 'Position', [main_w, frame_y, spiking_w, frame_h], 'Visible', 'on');
        set(sd, 'Position', [main_w - dragger_w/2, frame_y, dragger_w, frame_h], 'Visible', 'on');
    else
        main_w = width;
        set(mf, 'Position', [0, frame_y, main_w, frame_h]);
        set(sf, 'Visible', 'off');
        set(sd, 'Visible', 'off');
    end

    % Scrollbars inside MainFrame (Normalized)
    % Fixed pixel height logic for scrollbars
    scrollbar_h_px = 20;
    if frame_h > 0
        sb_h_norm = scrollbar_h_px / frame_h;
    else
        sb_h_norm = 0.05;
    end

    % Button Height (px) converted to norm
    btn_h_px = 25;
    if frame_h > 0
        btn_h_norm = btn_h_px / frame_h;
    else
        btn_h_norm = 0.05;
    end

    s1 = findobj(mf, 'Tag', 'Scroll1'); % Pan (Top)
    s2 = findobj(mf, 'Tag', 'Scroll2'); % Zoom (Bottom)
    ax = findobj(mf, 'Tag', 'MainAxes');

    pb = findobj(mf, 'Tag', 'PanButton');
    zb = findobj(mf, 'Tag', 'ZoomButton');

    % Scroll 2 (Bottom)
    set(s2, 'Position', [0.05, 0, 0.9, sb_h_norm]);

    % Scroll 1 (Above Scroll 2)
    set(s1, 'Position', [0.05, sb_h_norm, 0.9, sb_h_norm]);

    % Buttons (Right aligned above scrollbars)
    btn_w_norm = 0.1;
    right_margin = 0.05;

    % Pan Button
    set(pb, 'Position', [1 - right_margin - 2*btn_w_norm, 2*sb_h_norm, btn_w_norm, btn_h_norm]);
    % Zoom Button
    set(zb, 'Position', [1 - right_margin - btn_w_norm, 2*sb_h_norm, btn_w_norm, btn_h_norm]);

    % Axes
    % Starts above buttons
    axes_bottom = 2*sb_h_norm + btn_h_norm;

    main_ax_pos = [0.05, axes_bottom + 0.05, 0.9, 1 - (axes_bottom + 0.05) - 0.02];
    set(ax, 'Position', main_ax_pos);

    % Align Spiking Axes to Main Axes
    if show_spiking
        sax = findobj(sf, 'Tag', 'SpikingAxes');
        slb = findobj(sf, 'Tag', 'SpikingList');
        stt = findobj(sf, 'Tag', 'SpikingTitle');

        % Spiking Axes on Left 60% of Spiking Frame
        % Align bottom/top to MainAxes relative to Frame Height

        spiking_ax_pos = [0.1, main_ax_pos(2), 0.5, main_ax_pos(4)];
        set(sax, 'Position', spiking_ax_pos);

        % Listbox on Right
        set(slb, 'Position', [0.65, 0, 0.35, 0.9]);

        % Title
        set(stt, 'Position', [0.65, 0.9, 0.35, 0.1]);
    end

    update_view(fig);
end
