function results = findAndReplaceBlockParams(modelName, options)
%FINDANDREPLACEBLOCKPARAMS Search and optionally replace block parameter values in a Simulink model.
%
%   Searches blocks by type, property name, and/or property value. Supports
%   exact matching, substring matching (PartialValueMatch), and MATLAB regex
%   for flexible pattern-based searches.
%
%   --- Basic Usage (exact matching) ---
%
%   results = findAndReplaceBlockParams('myModel', BlockType='Gain')
%   Lists all Gain blocks in the model hierarchy.
%
%   results = findAndReplaceBlockParams('myModel', PropertyName='SampleTime')
%   Lists all blocks that have a SampleTime property with their current values.
%
%   results = findAndReplaceBlockParams('myModel', BlockType='Gain', PropertyName='SampleTime')
%   Lists all Gain blocks and shows their SampleTime values.
%
%   results = findAndReplaceBlockParams('myModel', BlockType='Gain', PropertyName='SampleTime', SearchValue='0.01')
%   Searches only the SampleTime property of Gain blocks for the value '0.01'.
%
%   results = findAndReplaceBlockParams('myModel', SearchValue='0.01')
%   Searches all dialog properties of every block for the value '0.01'.
%
%   results = findAndReplaceBlockParams('myModel', SearchValue='0.01', NewValue='0.02')
%   Finds all blocks with any property equal to '0.01' and replaces with '0.02'.
%
%   results = findAndReplaceBlockParams('myModel', SearchValue='Sample', PartialValueMatch=true)
%   Finds all blocks with any property containing the substring 'Sample'.
%
%   --- Regex Usage ---
%
%   BlockType, PropertyName, and SearchValue each support MATLAB regex.
%   Regex is automatically enabled when a value contains metacharacters:
%       * + ? [ ] ( ) { } ^ $ | \
%   Note: The dot character (.) does NOT trigger regex on its own, so values
%   like '0.01' are treated as literal strings. When regex is already active
%   (due to other metacharacters), use \. to match a literal dot.
%
%   Regex detection is independent per parameter — regex in BlockType does
%   not affect how PropertyName or SearchValue are matched, and vice versa.
%
%   results = findAndReplaceBlockParams('myModel', BlockType='.*Integrator')
%   Matches Integrator, DiscreteIntegrator, etc.
%
%   results = findAndReplaceBlockParams('myModel', BlockType='Gain|Constant')
%   Matches Gain and Constant blocks using regex OR.
%
%   results = findAndReplaceBlockParams('myModel', PropertyName='.*SampleTime')
%   Matches SampleTime, OutPortSampleTime, InPortSampleTime, etc.
%
%   results = findAndReplaceBlockParams('myModel', PropertyName='SampleTime', SearchValue='0\.0[1-5]')
%   Matches SampleTime values 0.01 through 0.05.
%
%   results = findAndReplaceBlockParams('myModel', BlockType='Gain|Constant', PropertyName='.*[Tt]ime', SearchValue='0\.0[1-5]')
%   Combined regex across all three parameters.
%
%   --- Case Sensitivity ---
%
%   results = findAndReplaceBlockParams('myModel', BlockType='gain', CaseSensitive=false)
%   Case-insensitive search: 'gain' matches 'Gain' blocks.
%
%   Arguments:
%       modelName                - Name of the Simulink model (without .slx extension).
%       BlockType                - (Optional) Restrict search to a specific block type
%                                  (e.g. 'Gain', 'SubSystem'). When specified without a
%                                  SearchValue, lists all blocks of this type.
%                                  Supports regex when metacharacters are detected.
%                                  Regex only applies to BlockType filtering.
%       PropertyName             - (Optional) Specific block property to search. If omitted,
%                                  all dialog parameters are searched. Supports regex
%                                  when metacharacters are detected. Regex only applies
%                                  to PropertyName matching.
%       SearchValue              - (Optional) Value to search for in block properties.
%                                  Supports regex when metacharacters are detected.
%                                  Regex only applies to SearchValue matching.
%       NewValue                 - (Optional) Replacement value. If omitted, search-only mode.
%       PartialValueMatch        - (Optional) Use substring matching instead of exact match
%                                  for SearchValue comparisons. Default: false.
%       CaseSensitive            - (Optional) Case-sensitive matching for all searches
%                                  (BlockType, PropertyName, SearchValue, PartialValueMatch).
%                                  Default: true. Set to false for case-insensitive matching.
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
        options.PartialValueMatch (1,1) logical = false
        options.CaseSensitive (1,1) logical = true
        options.SearchAllVariants (1,1) logical = false
        options.IncludeModelReferences (1,1) logical = true
    end

    modelName = char(modelName);
    blockType = char(options.BlockType);
    searchValue = char(options.SearchValue);
    propertyName = char(options.PropertyName);
    newValue = char(options.NewValue);
    partialMatch = options.PartialValueMatch;
    caseSensitive = options.CaseSensitive;

    % Require at least one search criterion
    if isempty(blockType) && isempty(searchValue) && isempty(propertyName)
        error('findAndReplaceBlockParams:InsufficientArgs', ...
            'Specify a BlockType, a SearchValue, a PropertyName, or a combination.');
    end

    % Build optional filter args for find_system
    if options.SearchAllVariants
        variantFilter = {'MatchFilter', @Simulink.match.allVariants};
    else
        variantFilter = {};
    end

    % Auto-enable RegExp if BlockType contains regex metacharacters
    regexPattern = '[\*\+\?\[\]\(\)\{\}\^\$\|\\]';

    if ~isempty(blockType)
        useBlockTypeRegex = ~isempty(regexp(blockType, regexPattern, 'once'));
        if useBlockTypeRegex && ~caseSensitive
            blockTypeFilter = {'BlockType', ['(?i)' blockType]};
            regexpFilter = {'RegExp', 'on'};
        elseif useBlockTypeRegex
            blockTypeFilter = {'BlockType', blockType};
            regexpFilter = {'RegExp', 'on'};
        elseif ~caseSensitive
            % Convert exact BlockType to case-insensitive regex
            blockTypeFilter = {'BlockType', ['(?i)^' regexptranslate('escape', blockType) '$']};
            regexpFilter = {'RegExp', 'on'};
        else
            blockTypeFilter = {'BlockType', blockType};
            regexpFilter = {};
        end
    else
        blockTypeFilter = {};
        regexpFilter = {};
    end

    % Auto-enable regex matching for PropertyName and SearchValue independently
    usePropertyRegex = ~isempty(regexp(propertyName, regexPattern, 'once'));
    useValueRegex = ~isempty(regexp(searchValue, regexPattern, 'once'));

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
        partialMatch, usePropertyRegex, useValueRegex, caseSensitive, ...
        variantFilter, blockTypeFilter, regexpFilter, options.IncludeModelReferences, searchedModels);

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
        partialMatch, usePropertyRegex, useValueRegex, caseSensitive, ...
        variantFilter, blockTypeFilter, regexpFilter, includeModelRefs, searchedModels)
    % Skip if already searched (handles circular model references)
    if searchedModels.isKey(modelName)
        results = emptyResults();
        return;
    end
    searchedModels(modelName) = true;

    fprintf('Searching model: %s\n', modelName);

    if isempty(searchValue)
        results = listBlocks(modelName, propertyName, usePropertyRegex, caseSensitive, ...
            variantFilter, blockTypeFilter, regexpFilter);
    elseif ~isempty(propertyName)
        results = searchSpecificProperty(modelName, searchValue, propertyName, ...
            partialMatch, usePropertyRegex, useValueRegex, caseSensitive, ...
            variantFilter, blockTypeFilter, regexpFilter);
    else
        results = searchAllProperties(modelName, searchValue, partialMatch, ...
            useValueRegex, caseSensitive, variantFilter, blockTypeFilter, regexpFilter);
    end

    % Recurse into model references
    if includeModelRefs
        results = searchModelReferences(modelName, searchValue, propertyName, ...
            partialMatch, usePropertyRegex, useValueRegex, caseSensitive, ...
            variantFilter, blockTypeFilter, regexpFilter, includeModelRefs, searchedModels, results);
    end
end

function results = listBlocks(modelName, propertyName, usePropertyRegex, caseSensitive, ...
        variantFilter, blockTypeFilter, regexpFilter)
    % List blocks without value matching (used when SearchValue is empty)
    results = emptyResults();

    blocks = find_system(modelName, ...
        'LookUnderMasks', 'all', ...
        'FollowLinks', 'on', ...
        variantFilter{:}, ...
        regexpFilter{:}, ...
        'Type', 'block', ...
        blockTypeFilter{:});

    % Remove model root from results
    isRoot = strcmp(blocks, modelName);
    blocks = blocks(~isRoot);

    for k = 1:numel(blocks)
        if ~isempty(propertyName)
            matchingProps = getMatchingProperties(blocks{k}, propertyName, usePropertyRegex, caseSensitive);
            for p = 1:numel(matchingProps)
                try
                    val = get_param(blocks{k}, matchingProps{p});
                    if ~ischar(val)
                        val = mat2str(val);
                    end
                catch
                    continue;
                end
                results(end+1) = struct( ...
                    'BlockPath', blocks{k}, ...
                    'PropertyName', matchingProps{p}, ...
                    'CurrentValue', val); %#ok<AGROW>
            end
        else
            val = get_param(blocks{k}, 'BlockType');
            results(end+1) = struct( ...
                'BlockPath', blocks{k}, ...
                'PropertyName', 'BlockType', ...
                'CurrentValue', val); %#ok<AGROW>
        end
    end
end

function results = searchSpecificProperty(modelName, searchValue, propertyName, ...
        partialMatch, usePropertyRegex, useValueRegex, caseSensitive, ...
        variantFilter, blockTypeFilter, regexpFilter)
    results = emptyResults();

    if partialMatch || usePropertyRegex || useValueRegex || ~isempty(regexpFilter) || ~caseSensitive
        % Use manual search when partial matching, property/value regex is active,
        % BlockType regex is active, or case-insensitive (to isolate each
        % matching behavior to its intended target)
        results = manualPropertySearch(modelName, searchValue, propertyName, ...
            partialMatch, usePropertyRegex, useValueRegex, caseSensitive, ...
            variantFilter, blockTypeFilter, regexpFilter);
    else
        try
            blocks = find_system(modelName, ...
                'LookUnderMasks', 'all', ...
                'FollowLinks', 'on', ...
                variantFilter{:}, ...
                blockTypeFilter{:}, ...
                propertyName, searchValue);
            % Remove model root from results
            isRoot = strcmp(blocks, modelName);
            blocks = blocks(~isRoot);
            for k = 1:numel(blocks)
                results(end+1) = struct( ...
                    'BlockPath', blocks{k}, ...
                    'PropertyName', propertyName, ...
                    'CurrentValue', searchValue); %#ok<AGROW>
            end
        catch
            % If find_system fails (e.g. unrecognized parameter), fall back to manual search
            results = manualPropertySearch(modelName, searchValue, propertyName, ...
                false, usePropertyRegex, useValueRegex, caseSensitive, ...
                variantFilter, blockTypeFilter, regexpFilter);
        end
    end
end

function results = manualPropertySearch(modelName, searchValue, propertyName, ...
        partialMatch, usePropertyRegex, useValueRegex, caseSensitive, ...
        variantFilter, blockTypeFilter, regexpFilter)
    results = emptyResults();
    allBlocks = find_system(modelName, ...
        'LookUnderMasks', 'all', ...
        'FollowLinks', 'on', ...
        variantFilter{:}, ...
        regexpFilter{:}, ...
        'Type', 'block', ...
        blockTypeFilter{:});

    % Remove model root from results
    isRoot = strcmp(allBlocks, modelName);
    allBlocks = allBlocks(~isRoot);

    for k = 1:numel(allBlocks)
        matchingProps = getMatchingProperties(allBlocks{k}, propertyName, usePropertyRegex, caseSensitive);
        for p = 1:numel(matchingProps)
            try
                val = get_param(allBlocks{k}, matchingProps{p});
                if ischar(val) && matchesValue(val, searchValue, partialMatch, useValueRegex, caseSensitive)
                    results(end+1) = struct( ...
                        'BlockPath', allBlocks{k}, ...
                        'PropertyName', matchingProps{p}, ...
                        'CurrentValue', val); %#ok<AGROW>
                end
            catch
                % Skip inaccessible parameters
            end
        end
    end
end

function results = searchAllProperties(modelName, searchValue, partialMatch, ...
        useValueRegex, caseSensitive, variantFilter, blockTypeFilter, regexpFilter)
    results = emptyResults();

    allBlocks = find_system(modelName, ...
        'LookUnderMasks', 'all', ...
        'FollowLinks', 'on', ...
        variantFilter{:}, ...
        regexpFilter{:}, ...
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
                if ischar(val) && matchesValue(val, searchValue, partialMatch, useValueRegex, caseSensitive)
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
        partialMatch, usePropertyRegex, useValueRegex, caseSensitive, ...
        variantFilter, blockTypeFilter, regexpFilter, includeModelRefs, searchedModels, results)
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
            partialMatch, usePropertyRegex, useValueRegex, caseSensitive, ...
            variantFilter, blockTypeFilter, regexpFilter, includeModelRefs, searchedModels);
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

function tf = matchesValue(val, searchValue, partialMatch, useValueRegex, caseSensitive)
    if partialMatch
        tf = contains(val, searchValue, 'IgnoreCase', ~caseSensitive);
    elseif useValueRegex
        if caseSensitive
            tf = ~isempty(regexp(val, searchValue, 'once'));
        else
            tf = ~isempty(regexp(val, searchValue, 'once', 'ignorecase'));
        end
    else
        if caseSensitive
            tf = strcmp(val, searchValue);
        else
            tf = strcmpi(val, searchValue);
        end
    end
end

function props = getMatchingProperties(block, propertyName, usePropertyRegex, caseSensitive)
    % Returns matching property names for a block. When usePropertyRegex is false,
    % returns the exact property name in a cell. When true, enumerates
    % DialogParameters and returns names matching the regex pattern.
    if ~usePropertyRegex
        props = {propertyName};
    else
        try
            dialogParams = get_param(block, 'DialogParameters');
        catch
            props = {};
            return;
        end
        if isempty(dialogParams) || ~isstruct(dialogParams)
            props = {};
            return;
        end
        allNames = fieldnames(dialogParams);
        if caseSensitive
            matches = ~cellfun('isempty', regexp(allNames, propertyName, 'once'));
        else
            matches = ~cellfun('isempty', regexp(allNames, propertyName, 'once', 'ignorecase'));
        end
        props = allNames(matches);
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
