function spiking_info = load_spiking_neurons(session, probe)
% LOAD_SPIKING_NEURONS - Load spiking neuron information for a probe
%
%   SPIKING_INFO = ndi.app.pyraview.load_spiking_neurons(SESSION, PROBE)
%
%   Inputs:
%       SESSION - An ndi.session object
%       PROBE   - An ndi.probe object
%
%   Outputs:
%       SPIKING_INFO - Struct array with fields:
%                      'element_obj' : The NDI element object
%                      'neuron_doc'  : The associated neuron_extracellular document (if any)
%                      'label'       : Display label for the UI
%

    arguments
        session (1,1) ndi.session
        probe (1,1) {mustBeA(probe, 'ndi.probe')}
    end

    spiking_info = struct('element_obj', {}, 'neuron_doc', {}, 'label', {});

    % 1. Find all spike elements for this probe
    Q1 = ndi.query('element.type', 'exact_string', 'spikes');
    Q2 = ndi.query('', 'depends_on', 'underlying_element_id', probe.id());
    element_docs = session.database_search(Q1 & Q2);

    if isempty(element_docs)
        return;
    end

    % 2. Find all neuron_extracellular documents in the session
    % Optimization: Load all once instead of querying per element
    Q_neuron = ndi.query('', 'isa', 'neuron_extracellular');
    all_neuron_docs = session.database_search(Q_neuron);

    % 3. Match elements to neurons
    for i = 1:numel(element_docs)
        el_doc = element_docs{i};
        el_id = el_doc.id();

        el_obj = ndi.database.fun.ndi_document2ndi_object(el_doc, session);

        % Find matching neuron doc
        n_doc = [];
        for j = 1:numel(all_neuron_docs)
            % Check if this neuron doc depends on el_id
            % dependency_value returns the value or error/empty
            % We need to check if 'element_id' dependency matches
            try
                dep_id = all_neuron_docs{j}.dependency_value('element_id');
                if strcmp(dep_id, el_id)
                    n_doc = all_neuron_docs{j};
                    break; % Assuming 1-to-1 or just taking first
                end
            catch
                % dependency might not exist
            end
        end

        quality = 0;
        if ~isempty(n_doc)
            if isfield(n_doc.document_properties, 'neuron_extracellular')
               if isfield(n_doc.document_properties.neuron_extracellular, 'quality_number')
                   quality = n_doc.document_properties.neuron_extracellular.quality_number;
               elseif isfield(n_doc.document_properties.neuron_extracellular, 'quality')
                   quality = n_doc.document_properties.neuron_extracellular.quality;
               end
            end
        end

        label = sprintf('%d %s Q%d', i, el_obj.elementstring(), quality);

        spiking_info(i).element_obj = el_obj;
        spiking_info(i).neuron_doc = n_doc;
        spiking_info(i).label = label;
    end
end
