classdef pyraview_test < matlab.unittest.TestCase
    % PYRAVIEW_TEST - Unit tests for ndi.app.pyraview

    methods (Test)
        function testInitializationWithoutSession(testCase)
            % Test that initialization without a session throws an error
            % We expect 'ndi:app:pyraview:nosession' error because default session is empty
            testCase.verifyError(@() ndi.app.pyraview(), 'ndi:app:pyraview:nosession');
        end

        function testInitializationWithEmptySession(testCase)
             % Test that initialization with an empty session throws an error
             s = ndi.session.empty();
             testCase.verifyError(@() ndi.app.pyraview('session', s), 'ndi:app:pyraview:nosession');
        end
    end
end
