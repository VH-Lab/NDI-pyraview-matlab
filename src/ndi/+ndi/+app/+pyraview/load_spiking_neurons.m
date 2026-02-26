function spiking_info = load_spiking_neurons(session, probe, epochid)
% LOAD_SPIKING_NEURONS - Load spiking neuron information for a probe
%
%   SPIKING_INFO = ndi.app.pyraview.load_spiking_neurons(SESSION, PROBE, EPOCHID)
%
%   Inputs:
%       SESSION - An ndi.session object
%       PROBE   - An ndi.probe object
%       EPOCHID - String identifier for the epoch
%
%   Outputs:
%       SPIKING_INFO - Struct array with fields:
%                      'element_obj' : The NDI element object
%                      'element_doc' : The NDI element document
%                      'neuron_doc'  : The associated neuron_extracellular document
%                      'label'       : Display label
%                      'spike_times' : Vector of spike times
%                      'center_of_mass': Scalar channel index of CoM
%

    arguments
        session (1,1) ndi.session
        probe (1,1) {mustBeA(probe, 'ndi.probe')}
        epochid (1,:) char
    end

    spiking_info = struct('element_obj', {}, 'element_doc', {}, 'neuron_doc', {}, ...
                          'label', {}, 'spike_times', {}, 'center_of_mass', {});

    % 1. Find all spike elements for this probe
    Q1 = ndi.query('element.type', 'exact_string', 'spikes');
    Q2 = ndi.query('', 'depends_on', 'underlying_element_id', probe.id());
    element_docs = session.database_search(Q1 & Q2);

    if isempty(element_docs)
        return;
    end

    % 2. Find all neuron_extracellular documents in the session
    Q_neuron = ndi.query('', 'isa', 'neuron_extracellular');
    all_neuron_docs = session.database_search(Q_neuron);

    % Initialize Progress Bar
    pb_fig = figure('Name', 'Loading Spiking Neurons', 'NumberTitle', 'off', 'MenuBar', 'none', ...
                    'ToolBar', 'none', 'Resize', 'off', 'Position', [500 500 520 80]);
    pb = ndi.gui.component.NDIProgressBar('Parent', pb_fig, ...
        'Message', 'Loading...', 'Text', 'Initializing...');

    cleanupObj = onCleanup(@() delete(pb_fig));

    % 3. Match elements to neurons
    num_elements = numel(element_docs);
    for i = 1:num_elements
        % Update Progress
        progress = i / num_elements;
        pb.Value = progress;
        pb.Message = sprintf('Loading neuron %d of %d...', i, num_elements);
        drawnow;

        el_doc = element_docs{i};
        el_id = el_doc.id();

        el_obj = ndi.database.fun.ndi_document2ndi_object(el_doc, session);

        % Find matching neuron doc
        n_doc = [];
        for j = 1:numel(all_neuron_docs)
            try
                dep_id = all_neuron_docs{j}.dependency_value('element_id');
                if strcmp(dep_id, el_id)
                    n_doc = all_neuron_docs{j};
                    break;
                end
            catch
            end
        end

        quality = 0;
        com = 1; % Default Center of Mass

        if ~isempty(n_doc)
            % Extract Quality
            if isfield(n_doc.document_properties, 'neuron_extracellular')
               if isfield(n_doc.document_properties.neuron_extracellular, 'quality_number')
                   quality = n_doc.document_properties.neuron_extracellular.quality_number;
               elseif isfield(n_doc.document_properties.neuron_extracellular, 'quality')
                   quality = n_doc.document_properties.neuron_extracellular.quality;
               end

               % Calculate Center of Mass
               if isfield(n_doc.document_properties.neuron_extracellular, 'mean_waveform')
                   w = n_doc.document_properties.neuron_extracellular.mean_waveform;
                   % w is Samples x Channels
                   % Energy E = sum(w.^2, 1) -> 1 x Channels
                   E = sum(w.^2, 1);
                   if sum(E) > 0
                       channels = 1:numel(E);
                       com = sum(E .* channels) / sum(E);
                   end
               end
            end
        end

        % Read Spike Times
        try
            [d, t] = el_obj.readtimeseries(epochid, -Inf, Inf);
            spike_times = t;
        catch
            spike_times = [];
        end

        label = sprintf('%d %s Q%d', i, el_obj.elementstring(), quality);

        spiking_info(i).element_obj = el_obj;
        spiking_info(i).element_doc = el_doc;
        spiking_info(i).neuron_doc = n_doc;
        spiking_info(i).label = label;
        spiking_info(i).spike_times = spike_times;
        spiking_info(i).center_of_mass = com;
    end
end
