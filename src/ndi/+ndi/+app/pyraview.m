function pyraview(app_options)
% PYRAVIEW - Signal viewer for NDI-matlab
%
%   ndi.app.pyraview('session', session_obj)
%
    arguments
        app_options.session (1,1) ndi.session = ndi.session.empty()
        app_options.command (1,:) char = 'Initialize'
        app_options.fig (1,1) matlab.ui.Figure = matlab.ui.Figure.empty()
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

        % Scrollbar 1 (Top)
        uicontrol(frame_panel, 'Style', 'slider', 'Units', 'normalized', ...
             'Position', [0 0 1 1], ...
             'Tag', 'Scroll1', 'Callback', callbackstr, ...
             'Min', 1, 'Max', 100, 'Value', 1, 'SliderStep', [1/99, 10/99]);

        % Scrollbar 2 (Bottom)
        uicontrol(frame_panel, 'Style', 'slider', 'Units', 'normalized', ...
             'Position', [0 0 1 1], ...
             'Tag', 'Scroll2', 'Callback', callbackstr, ...
             'Min', -100, 'Max', 100, 'Value', 0, 'SliderStep', [1/200, 10/200]);

        set(fig, 'UserData', ud);

        % Set Resize function
        set(fig, 'SizeChangedFcn', @(src, event) on_resize(src));

        % Trigger initial layout and update
        update_epoch_list(fig, ud);
        on_resize(fig);

    else
        % Handle Commands
        switch command
            case 'ProbeMenu'
                update_epoch_list(fig, get(fig, 'UserData'));
            case 'EpochMenu'
                % Do nothing for now
            case 'BandMenu'
                % Do nothing
            case 'Scroll1'
                % Do nothing
            case 'Scroll2'
                % Do nothing
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
    % Left 3/4, 80% height.
    % Placed below separator.
    frame_h = height * 0.8;
    frame_w = width * 0.75;
    frame_y = sep_y - margin - frame_h;

    % Ensure frame doesn't go below 0 (simple check)
    if frame_y < margin, frame_y = margin; end

    mf = findobj(fig, 'Tag', 'MainFrame');
    set(mf, 'Position', [0, frame_y, frame_w, frame_h]);

    % Adjust contents of MainFrame (Scrollbars and Axes)
    % Since they are normalized, they should adjust automatically relative to panel size.
    % But we need to define their normalized positions correctly once.
    % Actually, if I define them with normalized units in creation, I don't need to update them here
    % UNLESS I want fixed pixel height for scrollbars.
    % Scrollbars are usually fixed height in pixels.
    % So let's update them here using pixels logic inside the panel?
    % But panel size changes.
    % Let's use normalized for simplicity as per my previous thought,
    % but ensure they are correctly placed.

    scrollbar_h_px = 20;
    % We need to convert pixel height to normalized height for the panel
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
