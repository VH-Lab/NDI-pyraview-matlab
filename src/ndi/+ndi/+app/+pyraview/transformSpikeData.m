function [X, Y] = transformSpikeData(spiking_info, selectedIdx, t0, t1, spacing)
% TRANSFORM_SPIKE_DATA - Prepare spike data for plotting
%
%   [X, Y] = ndi.app.pyraview.transformSpikeData(SPIKING_INFO, SELECTEDIDX, T0, T1, SPACING)
%
%   Inputs:
%       SPIKING_INFO - Struct array from load_spiking_neurons
%       SELECTEDIDX  - Indices of spiking_info to plot
%       T0           - Start time of view
%       T1           - End time of view
%       SPACING      - Vertical spacing between channels
%
%   Outputs:
%       X, Y         - Vectors for plotting
%

    arguments
        spiking_info struct
        selectedIdx (1,:) double
        t0 (1,1) double
        t1 (1,1) double
        spacing (1,1) double
    end

    X = [];
    Y = [];

    if isempty(spiking_info) || isempty(selectedIdx)
        return;
    end

    x_cells = {};
    y_cells = {};

    for k = 1:numel(selectedIdx)
        idx = selectedIdx(k);
        if idx > numel(spiking_info), continue; end

        info = spiking_info(idx);
        times = info.spike_times;

        % Use best_channel instead of center_of_mass
        if isfield(info, 'best_channel')
            ch_idx = info.best_channel;
        elseif isfield(info, 'center_of_mass')
            ch_idx = round(info.center_of_mass);
        else
            ch_idx = 1;
        end

        if isempty(times), continue; end

        % Filter times within view
        valid_mask = times >= t0 & times <= t1;
        t_plot = times(valid_mask);

        if isempty(t_plot), continue; end

        % Calculate Y positions
        % (ch_idx-1)*S + 0.4*S to +0.6*S
        y_base = (ch_idx - 1) * spacing;
        y1 = y_base + 0.4 * spacing;
        y2 = y_base + 0.6 * spacing;

        numSpikes = numel(t_plot);

        % Construct line segments: (t, y1) -> (t, y2) -> (NaN, NaN)
        tempX = [t_plot(:)'; t_plot(:)'; nan(1, numSpikes)];
        tempY = [repmat(y1, 1, numSpikes); repmat(y2, 1, numSpikes); nan(1, numSpikes)];

        x_cells{end+1} = tempX(:);
        y_cells{end+1} = tempY(:);
    end

    if ~isempty(x_cells)
        X = cell2mat(x_cells');
        Y = cell2mat(y_cells');
    end
end
