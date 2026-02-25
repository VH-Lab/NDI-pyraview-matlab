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
        ud.current_data = []; % Store loaded data
        ud.current_time = []; % Store loaded time
        ud.current_level = []; % Store loaded level
        ud.loaded_pixel_span = 0; % Store pixel span used for loading
        ud.loaded_view_duration = Inf; % Store duration used for loading
        ud.view_t0 = 0; % Start of current view
        ud.view_duration = 1; % Duration of current view
        ud.channel_y_spacing = 100; % Default spacing
        ud.spiking_elements = {}; % Store spiking element objects

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
             'Tag', 'SpikingList');

        % Link Y Axes
        linkaxes([ax, sax], 'y');

        % Setup zoom/pan callbacks on axes
        z = zoom(fig);
        z.ActionPostCallback = @(src, event) on_zoom_pan(fig, event);
        p = pan(fig);
        p.ActionPostCallback = @(src, event) on_zoom_pan(fig, event);


        % Scrollbar 1 (Top) - Pan
        uicontrol(frame_panel, 'Style', 'slider', 'Units', 'normalized', ...
             'Position', [0 0 1 1], ...
             'Tag', 'Scroll1', 'Callback', callbackstr, ...
             'Min', 0, 'Max', 1, 'Value', 0, 'SliderStep', [0.01, 0.1]);

        % Scrollbar 2 (Bottom) - Zoom
        uicontrol(frame_panel, 'Style', 'slider', 'Units', 'normalized', ...
             'Position', [0 0 1 1], ...
             'Tag', 'Scroll2', 'Callback', callbackstr, ...
             'Min', 0, 'Max', 1, 'Value', 0.5, 'SliderStep', [0.01, 0.1]);

        % Toggle Buttons: Pan / Zoom
        uicontrol(frame_panel, 'Style', 'togglebutton', 'String', 'Pan', ...
             'Units', 'pixels', 'Position', [0 0 50 25], ...
             'Tag', 'PanButton', 'Callback', callbackstr, 'Value', 1); % Default Pan

        uicontrol(frame_panel, 'Style', 'togglebutton', 'String', 'Zoom', ...
             'Units', 'pixels', 'Position', [0 0 50 25], ...
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
            case 'SpikingCheckbox'
                on_resize(fig);
                val = get(findobj(fig, 'Tag', 'SpikingCheckbox'), 'Value');
                if val
                    load_spiking_neurons(fig);
                end
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

    set(fig, 'UserData', ud);

    update_scrollbars(fig, ud);
    update_view(fig);

    % Check for spiking
    cb = findobj(fig, 'Tag', 'SpikingCheckbox');
    if get(cb, 'Value')
        load_spiking_neurons(fig);
    end
end

function load_spiking_neurons(fig)
    ud = get(fig, 'UserData');

    pm = findobj(fig, 'Tag', 'ProbeMenu');
    probe_idx = get(pm, 'Value');
    if isempty(ud.probes) || probe_idx > numel(ud.probes)
        return;
    end
    probe = ud.probes{probe_idx};
    session = ud.session;

    Q1 = ndi.query('element.type','exact_string','spikes');
    Q2 = ndi.query('','depends_on','underlying_element_id', probe.id());
    Q = Q1 & Q2;

    docs = session.database_search(Q);

    elements = {};
    for i=1:numel(docs)
        elements{end+1} = ndi.database.fun.ndi_document2ndi_object(docs{i}, session);
    end

    ud.spiking_elements = elements;
    set(fig, 'UserData', ud);

    strs = {};
    if ~isempty(elements)
        strs = cellfun(@(x) x.elementstring(), elements, 'UniformOutput', false);
    end

    lb = findobj(fig, 'Tag', 'SpikingList');
    set(lb, 'String', strs);
    set(lb, 'Max', max(2, numel(strs))); % Allow multiple selection (Max > 1)
    if ~isempty(strs)
        set(lb, 'Value', 1:numel(strs));
    else
        set(lb, 'Value', []);
    end
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
end

function update_from_scrollbars(fig, ud)
    % Read scrollbar values and update view_t0 / view_duration

    s1 = findobj(fig, 'Tag', 'Scroll1'); % Pan
    s2 = findobj(fig, 'Tag', 'Scroll2'); % Zoom

    val_pan = get(s1, 'Value');
    val_zoom = get(s2, 'Value');

    full_dur = ud.epoch_t1 - ud.epoch_t0;
    if full_dur <= 0, full_dur = 1; end

    min_dur = 0.01; % 10ms

    % ZOOM Logic: Maintain center time
    % Calculate old center
    center_t = ud.view_t0 + ud.view_duration / 2;

    % New Duration
    new_duration = exp( log(full_dur) * (1-val_zoom) + log(min_dur) * val_zoom );
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

function update_scrollbars(fig, ud)
    s1 = findobj(fig, 'Tag', 'Scroll1');
    s2 = findobj(fig, 'Tag', 'Scroll2');

    full_dur = ud.epoch_t1 - ud.epoch_t0;
    if full_dur <= 0, full_dur = 1; end
    min_dur = 0.01;

    % Calculate val_zoom (Scroll2)
    num = log(ud.view_duration) - log(full_dur);
    den = log(min_dur) - log(full_dur);
    val_zoom = num / den;
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

    % If pixel span changed significantly (>10%)
    if abs(current_pixel_span - ud.loaded_pixel_span) / ud.loaded_pixel_span > 0.1
        needs_load = true;
    end

    % If zoom level changed significantly (>20%)
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

    % Force scrollbar sync if not called from there?
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

    numSamples = size(data, 1);
    numChannels = size(data, 2);

    if level == 0
        totalPoints = numChannels * (numSamples + 1);
        X = NaN(totalPoints, 1);
        Y = NaN(totalPoints, 1);

        for c = 1:numChannels
            offset = (c-1) * spacing;
            startIdx = (c-1) * (numSamples + 1) + 1;
            endIdx = startIdx + numSamples - 1;

            X(startIdx:endIdx) = tVec;
            Y(startIdx:endIdx) = data(:, c) + offset;
        end
        plot(ud.axes, X, Y);

    else
        pointsPerSample = 3;
        totalPoints = numSamples * pointsPerSample * numChannels;

        X = NaN(totalPoints, 1);
        Y = NaN(totalPoints, 1);

        for c = 1:numChannels
            offset = (c-1) * spacing;
            mins = data(:, c, 1) + offset;
            maxs = data(:, c, 2) + offset;

            tempY = [mins'; maxs'; nan(1, numSamples)];
            tempX = [tVec'; tVec'; nan(1, numSamples)];

            colY = tempY(:);
            colX = tempX(:);

            startIdx = (c-1) * numel(colY) + 1;
            endIdx = startIdx + numel(colY) - 1;

            X(startIdx:endIdx) = colX;
            Y(startIdx:endIdx) = colY;
        end
        plot(ud.axes, X, Y);
    end

    xlim(ud.axes, [ud.view_t0, ud.view_t0 + ud.view_duration]);
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
    sc = findobj(fig, 'Tag', 'SpikingCheckbox');
    set(sc, 'Position', [current_x, top_y, 200, control_height]);

    % Separator
    sep_y = top_y - margin;
    sep = findobj(fig, 'Tag', 'SeparatorLine');
    set(sep, 'Position', [0, sep_y, width, 1]);

    % Frames
    % Main Frame hugs bottom (0) and separator (sep_y)
    frame_y = 0; % Assuming "hug bottom" means 0
    frame_h = sep_y; % From 0 to sep_y

    % Check Spiking Checkbox
    show_spiking = get(sc, 'Value');

    mf = findobj(fig, 'Tag', 'MainFrame');
    sf = findobj(fig, 'Tag', 'SpikingFrame');

    if show_spiking
        main_w = width * 0.8;
        spiking_w = width * 0.2;
        set(mf, 'Position', [0, frame_y, main_w, frame_h]);
        set(sf, 'Position', [main_w, frame_y, spiking_w, frame_h], 'Visible', 'on');
    else
        main_w = width;
        set(mf, 'Position', [0, frame_y, main_w, frame_h]);
        set(sf, 'Visible', 'off');
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
    set(ax, 'Position', [0.05, axes_bottom + 0.05, 0.9, 1 - (axes_bottom + 0.05) - 0.02]);

    update_view(fig);
end
