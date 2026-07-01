function colors = unitColors(qualities, depthKeys, options)
% UNITCOLORS - Assign per-unit display colors for pyraview spiking units.
%
%   COLORS = ndi.app.pyraview.unitColors(QUALITIES, DEPTHKEYS)
%
%   Returns an N-by-3 matrix of RGB colors (values 0..1), one row per unit,
%   used to draw that unit's hash marks, extent boxes and waveform.
%
%   The colors do two jobs at once:
%
%     1. Distinguish units that sit at (or near) the same depth. A curated
%        12-colour, colour-blind-safe palette (Okabe-Ito / Paul Tol families)
%        carries unit identity through hue. The palette was chosen so its
%        entries stay distinguishable under red/green colour-vision deficiency
%        (variation rides on the blue<->yellow axis and on lightness, not on
%        red<->green). Colors are assigned depth-aware: units are walked in
%        depth order and each is given the palette hue that is most different
%        (in CIELAB) from its recent depth neighbours, so adjacent units are
%        easy to tell apart.
%
%     2. Convey quality. Higher-quality units (QUALITY >= vividThreshold, by
%        default 2, i.e. Q2 and above) are drawn with the full vivid palette;
%        lower-quality units (Q1 and Q0) are drawn with a muted/pastel version
%        of the same hue so they read as "less prominent". Vividness is a
%        saturation/lightness difference, which is orthogonal to red/green
%        confusion and therefore remains legible to colour-blind viewers.
%
%   Inputs:
%       QUALITIES  - 1-by-N vector of unit quality numbers (e.g. 1..4).
%       DEPTHKEYS  - 1-by-N vector of a depth-ordering key per unit (the
%                    unit's best/maximum-energy channel index is used by the
%                    caller). If its length does not match QUALITIES, unit
%                    order (1..N) is used instead.
%
%   Optional name/value arguments:
%       vividThreshold - Quality at/above which the vivid palette is used.
%                        Default 2 (Q2 and higher are vivid; Q1/Q0 muted).
%       neighborWindow - Number of preceding depth-neighbours considered when
%                        picking a maximally-different hue. Default 4.
%
    arguments
        qualities (1,:) double
        depthKeys (1,:) double
        options.vividThreshold (1,1) double = 2
        options.neighborWindow (1,1) double = 4
    end

    N = numel(qualities);
    colors = zeros(N, 3);
    if N == 0
        return;
    end

    if numel(depthKeys) ~= N
        depthKeys = 1:N;
    end

    B = basePalette();   % 12x3 vivid
    M = mutedPalette();  % 12x3 muted (same hues, desaturated + lightened)
    P = size(B, 1);

    % Perceptual distances between palette hues (use the vivid set as the
    % representative; muted shares the same hues). Drives the depth-aware
    % assignment below.
    D = pairwiseLabDistance(B);

    % Walk units in depth order and greedily assign the palette hue that is
    % most different from the hues used by recent depth neighbours, so nearby
    % units never share a colour. A balance penalty (relative to the
    % least-used hue, so it stays bounded no matter how many units there are)
    % spreads assignments across the whole palette, so far-apart repeats are
    % as rare as possible while local separation stays strong.
    balanceWeight = 3.0; % in CIELAB Delta-E units per excess use
    [~, order] = sort(depthKeys, 'ascend');
    hueIdx = zeros(1, N);
    usage = zeros(1, P);
    W = options.neighborWindow;

    for ii = 1:N
        u = order(ii);

        firstNeighbor = max(1, ii - W);
        recent = hueIdx(order(firstNeighbor:ii-1));
        recent = recent(recent > 0);

        minUsage = min(usage);

        bestH = 1;
        bestScore = -inf;
        for h = 1:P
            if isempty(recent)
                sep = 0;
            else
                sep = min(D(h, recent)); % distance to nearest recent neighbour
            end
            score = sep - balanceWeight * (usage(h) - minUsage);
            if score > bestScore
                bestScore = score;
                bestH = h;
            end
        end

        hueIdx(u) = bestH;
        usage(bestH) = usage(bestH) + 1;
    end

    for u = 1:N
        h = hueIdx(u);
        if qualities(u) >= options.vividThreshold
            colors(u, :) = B(h, :);
        else
            colors(u, :) = M(h, :);
        end
    end
end

function B = basePalette()
    % 12 colour-blind-safe hues (vivid), used for higher-quality units.
    B = [ ...
        0.0000 0.4471 0.6980;   % blue
        0.9020 0.6235 0.0000;   % orange
        0.0000 0.6196 0.4510;   % teal-green
        0.8000 0.4745 0.6549;   % pink-purple
        0.3373 0.7059 0.9137;   % sky
        0.8353 0.3686 0.0000;   % vermillion
        0.9412 0.8941 0.2588;   % yellow
        0.4000 0.0667 0.0000;   % maroon
        0.2000 0.1333 0.5333;   % indigo
        0.6000 0.6000 0.2000;   % olive
        0.6667 0.2667 0.6000;   % magenta
        0.5333 0.8000 0.9333];  % pale-cyan
end

function M = mutedPalette()
    % Muted/pastel version of basePalette (saturation x0.70, then mixed 30%
    % toward white), used for lower-quality units (Q1/Q0). Same hue order as
    % basePalette so a unit keeps a related hue regardless of quality.
    M = [ ...
        0.3733 0.5924 0.7153;
        0.8367 0.7002 0.3947;
        0.3651 0.6687 0.5860;
        0.8258 0.6663 0.7547;
        0.5966 0.7772 0.8791;
        0.7970 0.5683 0.3877;
        0.8872 0.8641 0.5528;
        0.5380 0.3747 0.3420;
        0.4680 0.4353 0.6313;
        0.6780 0.6780 0.4820;
        0.7247 0.5287 0.6920;
        0.7153 0.8460 0.9113];
end

function D = pairwiseLabDistance(rgb)
    % Euclidean CIELAB (Delta-E) distance between every pair of rows of RGB.
    lab = srgb2lab(rgb);
    n = size(lab, 1);
    D = zeros(n);
    for i = 1:n
        for j = 1:n
            D(i, j) = sqrt(sum((lab(i, :) - lab(j, :)).^2));
        end
    end
end

function lab = srgb2lab(rgb)
    % Convert sRGB (0..1) to CIELAB (D65). Self-contained so no toolbox is
    % required.
    thr = 0.04045;
    lin = zeros(size(rgb));
    lo = rgb <= thr;
    lin(lo) = rgb(lo) / 12.92;
    lin(~lo) = ((rgb(~lo) + 0.055) / 1.055).^2.4;

    % linear sRGB -> XYZ (D65)
    Mx = [0.4124 0.3576 0.1805; ...
          0.2126 0.7152 0.0722; ...
          0.0193 0.1192 0.9505];
    XYZ = lin * Mx';

    white = [0.95047 1.0 1.08883];
    XYZn = XYZ ./ white;

    f = @(t) (t > 0.008856) .* t.^(1/3) + (t <= 0.008856) .* (7.787 * t + 16/116);
    fx = f(XYZn(:, 1));
    fy = f(XYZn(:, 2));
    fz = f(XYZn(:, 3));

    L = 116 * fy - 16;
    a = 500 * (fx - fy);
    b = 200 * (fy - fz);
    lab = [L a b];
end
