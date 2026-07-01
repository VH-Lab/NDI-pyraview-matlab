classdef unitColors_test < matlab.unittest.TestCase
    % UNITCOLORS_TEST - Unit test for ndi.app.pyraview.unitColors

    methods (Test)
        function testSizeAndRange(testCase)
            % One RGB row per unit, all values in [0, 1].
            qualities = [1 2 3 4 1 2];
            depthKeys = [1 2 3 4 5 6];
            colors = ndi.app.pyraview.unitColors(qualities, depthKeys);

            testCase.verifySize(colors, [numel(qualities), 3]);
            testCase.verifyTrue(all(colors(:) >= 0 & colors(:) <= 1), ...
                'All color components must be in [0, 1]');
        end

        function testEmpty(testCase)
            colors = ndi.app.pyraview.unitColors([], []);
            testCase.verifySize(colors, [0, 3]);
        end

        function testVividVsMuted(testCase)
            % Q1 is best: Q1 and Q2 are vivid; Q3, Q4 and Q0 are muted. For a
            % single unit every variant uses hue index 1, so the vivid ones
            % must be the base color and the muted ones the pastel version.
            vivid = [0.0000 0.4471 0.6980]; % basePalette hue 1
            muted = [0.3733 0.5924 0.7153]; % mutedPalette hue 1

            testCase.verifyEqual(ndi.app.pyraview.unitColors(1, 1), vivid, ...
                'AbsTol', 1e-3, 'Q1 (best) should be vivid');
            testCase.verifyEqual(ndi.app.pyraview.unitColors(2, 1), vivid, ...
                'AbsTol', 1e-3, 'Q2 should be vivid');
            testCase.verifyEqual(ndi.app.pyraview.unitColors(3, 1), muted, ...
                'AbsTol', 1e-3, 'Q3 should be muted');
            testCase.verifyEqual(ndi.app.pyraview.unitColors(4, 1), muted, ...
                'AbsTol', 1e-3, 'Q4 should be muted');
            testCase.verifyEqual(ndi.app.pyraview.unitColors(0, 1), muted, ...
                'AbsTol', 1e-3, 'Q0 (no metadata) should be muted');

            % A muted color is closer to white (larger min component) than its
            % vivid counterpart.
            testCase.verifyGreaterThan(min(muted), min(vivid), ...
                'Muted color should be lighter/less saturated than vivid');
        end

        function testNeighborsDiffer(testCase)
            % Units adjacent in depth should get different hues (depth-aware
            % assignment), so their colors must not be identical.
            n = 8;
            qualities = 2 * ones(1, n);   % all vivid
            depthKeys = 1:n;
            colors = ndi.app.pyraview.unitColors(qualities, depthKeys);

            for k = 1:n-1
                testCase.verifyFalse(isequal(colors(k, :), colors(k+1, :)), ...
                    sprintf('Adjacent units %d and %d must differ in color', k, k+1));
            end
        end

        function testAssignmentFollowsDepthNotOrder(testCase)
            % depthKeys, not input order, drives assignment. Two units at very
            % different depths may reuse a hue; the function should still return
            % valid colors and treat the depth key as the neighbourhood metric.
            qualities = [2 2 2];
            depthKeys = [100 1 101]; % unit 2 is far from units 1 and 3
            colors = ndi.app.pyraview.unitColors(qualities, depthKeys);

            % Units 1 and 3 are depth-adjacent (100, 101) -> different colors.
            testCase.verifyFalse(isequal(colors(1, :), colors(3, :)), ...
                'Depth-adjacent units must differ');
        end
    end
end
