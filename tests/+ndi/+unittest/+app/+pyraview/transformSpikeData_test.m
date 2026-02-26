classdef transformSpikeData_test < matlab.unittest.TestCase
    % TRANSFORMSPIKEDATA_TEST - Unit test for ndi.app.pyraview.transformSpikeData

    methods (Test)
        function testNoFiltering(testCase)
            % Test that spikes outside t0 and t1 are still returned

            % Mock spiking_info
            % Structure array with spike_times and best_channel
            spiking_info = struct();
            spiking_info(1).spike_times = [10, 20, 30];
            spiking_info(1).best_channel = 1;

            selectedIdx = 1;
            t0 = 15;
            t1 = 25;
            spacing = 100;

            % Call function
            [X, Y] = ndi.app.pyraview.transformSpikeData(spiking_info, selectedIdx, t0, t1, spacing);

            % Verification
            % We expect X to contain 10, 20, and 30, even though 10 and 30 are outside [15, 25]
            % X format is [t; t; NaN] for each spike

            testCase.verifyTrue(any(X == 10), 'X should contain spike at t=10');
            testCase.verifyTrue(any(X == 20), 'X should contain spike at t=20');
            testCase.verifyTrue(any(X == 30), 'X should contain spike at t=30');

            % Verify Y structure
            % Should have 3 segments (3 spikes) * 3 points = 9 points
            testCase.verifyEqual(numel(X), 9, 'Should have 9 points in X');
            testCase.verifyEqual(numel(Y), 9, 'Should have 9 points in Y');

        end

        function testMultipleNeurons(testCase)
            % Test with multiple neurons selected

            spiking_info(1).spike_times = [10];
            spiking_info(1).best_channel = 1;
            spiking_info(2).spike_times = [40];
            spiking_info(2).best_channel = 2;

            selectedIdx = [1, 2];
            t0 = 0; t1 = 100; spacing = 100;

            [X, Y] = ndi.app.pyraview.transformSpikeData(spiking_info, selectedIdx, t0, t1, spacing);

            testCase.verifyTrue(any(X == 10), 'X should contain t=10');
            testCase.verifyTrue(any(X == 40), 'X should contain t=40');

            % Verify Y Levels
            % Neuron 1 (best_channel 1): Base 0. Y range 40..60
            % Neuron 2 (best_channel 2): Base 100. Y range 140..160

            mask1 = (X == 10);
            y1 = Y(mask1);
            y1_vals = y1(~isnan(y1));
            testCase.verifyTrue(all(y1_vals >= 40 & y1_vals <= 60), 'Neuron 1 Y values correct');

            mask2 = (X == 40);
            y2 = Y(mask2);
            y2_vals = y2(~isnan(y2));
            testCase.verifyTrue(all(y2_vals >= 140 & y2_vals <= 160), 'Neuron 2 Y values correct');
        end
    end
end
