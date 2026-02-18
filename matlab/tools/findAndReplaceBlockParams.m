function results = findAndReplaceBlockParams(modelName, options)
%FINDANDREPLACEBLOCKPARAMS Search and optionally replace block parameter values in a Simulink model.
%
%   results = findAndReplaceBlockParams('myModel', BlockType='Gain')
%   Lists all Gain blocks in the model hierarchy.
%
%   results = findAndReplaceBlockParams('myModel', BlockType='Gain')
%   Lists all Gain blocks in the currently active model.
%
%   results = findAndReplaceBlockParams('myModel', BlockType='Gain', PropertyName='SampleTime')
%   Lists all Gain blocks and shows their SampleTime values.
%
%   results = findAndReplaceBlockParams('myModel', BlockType='Gain', SearchValue='0.01')
%   Searches only Gain blocks for the value '0.01' across all dialog properties.
%
%   results = findAndReplaceBlockParams('myModel', BlockType='Gain', PropertyName='SampleTime', SearchValue='0.01')
%   Searches only the SampleTime property of Gain blocks for the value '0.01'.
%
%   results = findAndReplaceBlockParams('myModel', SearchValue='0.01')
%   Searches all dialog properties of every block for the value '0.01'.
%
%   results = findAndReplaceBlockParams('myModel', PropertyName='SampleTime', SearchValue='0.01')
%   Searches the SampleTime property of every block for the value '0.01'.
%
%   results = findAndReplaceBlockParams('myModel', SearchValue='0.01', NewValue='0.02')
%   Finds all blocks with any property equal to '0.01' and replaces with '0.02'.
%
%   results = findAndReplaceBlockParams('myModel', SearchValue='Sample', PartialMatch=true)
%   Finds all blocks with any property containing the substring 'Sample'.
%
%   Arguments:
%       modelName                - Name of the Simulink model (without .slx extension).
%       BlockType                - (Optional) Restrict search to a specific block type
%                                  (e.g. 'Gain', 'SubSystem'). When specified without a
%                                  SearchValue, lists all blocks of this type.
%       PropertyName             - (Optional) Specific block property to search. If omitted,
%                                  all dialog parameters are searched.
%       SearchValue              - (Optional) Value to search for in block properties.
%       NewValue                 - (Optional) Replacement value. If omitted, search-only mode.
%       PartialMatch             - (Optional) Use substring matching instead of exact match
%                                  (case-sensitive). Default: false.
%       SearchAllVariants        - (Optional) Search inactive Variant Subsystem choices in
%                                  addition to active ones. Default: false.
%       IncludeModelReferences   - (Optional) Recurse into Model Reference blocks.
%                                  Default: true.
%
%   Returns:
%       results - Struct array with fields: BlockPath, PropertyName, CurrentValue

    arguments
        modelName (1,:) {mustBeText}
        options.BlockType (1,:) {mustBeText} = ''
        options.SearchValue (1,:) {mustBeText} = ''
        options.PropertyName (1,:) {mustBeText} = ''
        options.NewValue (1,:) {mustBeText} = ''
        options.PartialMatch (1,1) logical = false
        options.SearchAllVariants (1,1) logical = false
        options.IncludeModelReferences (1,1) logical = true
    end

    modelName = char(modelName);
    blockType = char(options.BlockType);
    searchValue = char(options.SearchValue);
    propertyName = char(options.PropertyName);
    newValue = char(options.NewValue);
    partialMatch = options.PartialMatch;

    % Require at least one search criterion
    if isempty(blockType) && isempty(searchValue)
        error('findAndReplaceBlockParams:InsufficientArgs', ...
            'Specify a BlockType, a SearchValue, or both.');
    end

    % Build optional filter args for find_system
    if options.SearchAllVariants
        variantFilter = {'MatchFilter', @Simulink.match.allVariants};
    else
        variantFilter = {};
    end

    if ~isempty(blockType)
        blockTypeFilter = {'BlockType', blockType};
    else
        blockTypeFilter = {};
    end

    % Strip .slx or .mdl extension if provided
    [~, modelName, ~] = fileparts(modelName);

    % Load model if not already loaded
    wasLoaded = bdIsLoaded(modelName);
    if ~wasLoaded
        fprintf('Loading model: %s\n', modelName);
        load_system(modelName);
    end
    cleanupModel = onCleanup(@() closeIfNotLoaded(modelName, wasLoaded));

    % Track searched models to avoid infinite recursion with circular references
    searchedModels = containers.Map('KeyType', 'char', 'ValueType', 'logical');

    % Perform the search
    results = searchModel(modelName, searchValue, propertyName, ...
        partialMatch, variantFilter, blockTypeFilter, options.IncludeModelReferences, searchedModels);

    % Display results
    if isempty(results)
        fprintf('\nNo matches found');
        if ~isempty(searchValue)
            fprintf(' for value "%s"', searchValue);
        end
        if ~isempty(blockType)
            fprintf(' in BlockType "%s"', blockType);
        end
        if ~isempty(propertyName)
            fprintf(' in property "%s"', propertyName);
        end
        fprintf(' in model "%s".\n', modelName);
        return;
    end

    if isempty(searchValue)
        fprintf('\n=== Found %d block(s) ===\n\n', numel(results));
    else
        fprintf('\n=== Found %d match(es) for "%s" ===\n\n', numel(results), searchValue);
    end
    T = table({results.BlockPath}', {results.PropertyName}', {results.CurrentValue}', ...
        'VariableNames', {'BlockPath', 'PropertyName', 'CurrentValue'});
    disp(T);

    % Replace values if NewValue was specified
    if ~isempty(newValue)
        if isempty(searchValue)
            warning('findAndReplaceBlockParams:NoSearchValue', ...
                'NewValue is ignored when SearchValue is empty (block listing mode).');
        else
            performReplacement(results, searchValue, newValue, modelName);
        end
    end
end

%% --- Helper Functions ---

function results = searchModel(modelName, searchValue, propertyName, ...
        partialMatch, variantFilter, blockTypeFilter, includeModelRefs, searchedModels)
    % Skip if already searched (handles circular model references)
    if searchedModels.isKey(modelName)
        results = emptyResults();
        return;
    end
    searchedModels(modelName) = true;

    fprintf('Searching model: %s\n', modelName);

    if isempty(searchValue)
        results = listBlocks(modelName, propertyName, variantFilter, blockTypeFilter);
    elseif ~isempty(propertyName)
        results = searchSpecificProperty(modelName, searchValue, propertyName, ...
            partialMatch, variantFilter, blockTypeFilter);
    else
        results = searchAllProperties(modelName, searchValue, partialMatch, ...
            variantFilter, blockTypeFilter);
    end

    % Recurse into model references
    if includeModelRefs
        results = searchModelReferences(modelName, searchValue, propertyName, ...
            partialMatch, variantFilter, blockTypeFilter, includeModelRefs, searchedModels, results);
    end
end

function results = listBlocks(modelName, propertyName, variantFilter, blockTypeFilter)
    % List blocks without value matching (used when SearchValue is empty)
    results = emptyResults();

    blocks = find_system(modelName, ...
        'LookUnderMasks', 'all', ...
        'FollowLinks', 'on', ...
        variantFilter{:}, ...
        'Type', 'block', ...
        blockTypeFilter{:});

    % Remove model root from results
    isRoot = strcmp(blocks, modelName);
    blocks = blocks(~isRoot);

    for k = 1:numel(blocks)
        if ~isempty(propertyName)
            try
                val = get_param(blocks{k}, propertyName);
                if ~ischar(val)
                    val = mat2str(val);
                end
            catch
                val = '<N/A>';
            end
            propName = propertyName;
        else
            val = get_param(blocks{k}, 'BlockType');
            propName = 'BlockType';
        end
        results(end+1) = struct( ...
            'BlockPath', blocks{k}, ...
            'PropertyName', propName, ...
            'CurrentValue', val); %#ok<AGROW>
    end
end

function results = searchSpecificProperty(modelName, searchValue, propertyName, ...
        partialMatch, variantFilter, blockTypeFilter)
    results = emptyResults();

    if partialMatch
        [blocks, values] = manualPropertySearch(modelName, searchValue, ...
            propertyName, true, variantFilter, blockTypeFilter);
    else
        try
            blocks = find_system(modelName, ...
                'LookUnderMasks', 'all', ...
                'FollowLinks', 'on', ...
                variantFilter{:}, ...
                blockTypeFilter{:}, ...
                propertyName, searchValue);
            values = repmat({searchValue}, size(blocks));
        catch
            % If find_system fails (e.g. unrecognized parameter), fall back to manual search
            [blocks, values] = manualPropertySearch(modelName, searchValue, ...
                propertyName, false, variantFilter, blockTypeFilter);
        end
    end

    % Remove model root from results
    isRoot = strcmp(blocks, modelName);
    blocks = blocks(~isRoot);
    values = values(~isRoot);

    for k = 1:numel(blocks)
        results(end+1) = struct( ...
            'BlockPath', blocks{k}, ...
            'PropertyName', propertyName, ...
            'CurrentValue', values{k}); %#ok<AGROW>
    end
end

function [blocks, values] = manualPropertySearch(modelName, searchValue, ...
        propertyName, partialMatch, variantFilter, blockTypeFilter)
    allBlocks = find_system(modelName, ...
        'LookUnderMasks', 'all', ...
        'FollowLinks', 'on', ...
        variantFilter{:}, ...
        'Type', 'block', ...
        blockTypeFilter{:});
    matched = false(size(allBlocks));
    matchedValues = cell(size(allBlocks));
    for k = 1:numel(allBlocks)
        try
            val = get_param(allBlocks{k}, propertyName);
            if ischar(val) && matchesValue(val, searchValue, partialMatch)
                matched(k) = true;
                matchedValues{k} = val;
            end
        catch
            % Block doesn't have this property
        end
    end
    blocks = allBlocks(matched);
    values = matchedValues(matched);
end

function results = searchAllProperties(modelName, searchValue, partialMatch, ...
        variantFilter, blockTypeFilter)
    results = emptyResults();

    allBlocks = find_system(modelName, ...
        'LookUnderMasks', 'all', ...
        'FollowLinks', 'on', ...
        variantFilter{:}, ...
        'Type', 'block', ...
        blockTypeFilter{:});

    fprintf('  Scanning %d blocks (all properties)...\n', numel(allBlocks));

    for k = 1:numel(allBlocks)
        blockPath = allBlocks{k};
        try
            dialogParams = get_param(blockPath, 'DialogParameters');
        catch
            continue;
        end

        if isempty(dialogParams) || ~isstruct(dialogParams)
            continue;
        end

        paramNames = fieldnames(dialogParams);
        for p = 1:numel(paramNames)
            try
                val = get_param(blockPath, paramNames{p});
                if ischar(val) && matchesValue(val, searchValue, partialMatch)
                    results(end+1) = struct( ...
                        'BlockPath', blockPath, ...
                        'PropertyName', paramNames{p}, ...
                        'CurrentValue', val); %#ok<AGROW>
                end
            catch
                % Skip inaccessible parameters
            end
        end
    end
end

function results = searchModelReferences(modelName, searchValue, propertyName, ...
        partialMatch, variantFilter, blockTypeFilter, includeModelRefs, searchedModels, results)
    refBlocks = find_system(modelName, ...
        'LookUnderMasks', 'all', ...
        'FollowLinks', 'on', ...
        variantFilter{:}, ...
        'BlockType', 'ModelReference');

    for k = 1:numel(refBlocks)
        refModelName = get_param(refBlocks{k}, 'ModelName');
        if searchedModels.isKey(refModelName)
            continue;
        end

        if ~bdIsLoaded(refModelName)
            try
                load_system(refModelName);
            catch ME
                warning('findAndReplaceBlockParams:LoadFailed', ...
                    'Could not load referenced model "%s": %s', refModelName, ME.message);
                continue;
            end
        end

        refResults = searchModel(refModelName, searchValue, propertyName, ...
            partialMatch, variantFilter, blockTypeFilter, includeModelRefs, searchedModels);
        results = [results, refResults]; %#ok<AGROW>
    end
end

function performReplacement(results, searchValue, newValue, modelName)
    fprintf('\nReplacing "%s" -> "%s" in %d block(s)...\n', ...
        searchValue, newValue, numel(results));

    successCount = 0;
    for k = 1:numel(results)
        try
            set_param(results(k).BlockPath, results(k).PropertyName, newValue);
            fprintf('  Updated: %s [%s]\n', results(k).BlockPath, results(k).PropertyName);
            successCount = successCount + 1;
        catch ME
            warning('findAndReplaceBlockParams:SetParamFailed', ...
                'Failed to set %s on %s: %s', ...
                results(k).PropertyName, results(k).BlockPath, ME.message);
        end
    end

    fprintf('\nReplacement complete. %d of %d block(s) updated.\n', successCount, numel(results));
    fprintf('NOTE: Changes are in memory only. Use save_system(''%s'') to persist.\n', modelName);
end

function tf = matchesValue(val, searchValue, partialMatch)
    if partialMatch
        tf = contains(val, searchValue);
    else
        tf = strcmp(val, searchValue);
    end
end

function results = emptyResults()
    results = struct('BlockPath', {}, 'PropertyName', {}, 'CurrentValue', {});
end

function closeIfNotLoaded(modelName, wasLoaded)
    if ~wasLoaded && bdIsLoaded(modelName)
        close_system(modelName, 0);
    end
end
