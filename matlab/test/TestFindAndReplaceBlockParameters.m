function TestFindAndReplaceBlockParameters()
%TESTFINDANDREPLACEBLOCKPARAMETERS Functional tests for findAndReplaceBlockParams.
%   Builds ExampleModel.slx programmatically and verifies all calling
%   variations of findAndReplaceBlockParams.
%
%   Usage:
%       TestFindAndReplaceBlockParameters

    fprintf('\n========================================\n');
    fprintf('  findAndReplaceBlockParams Test Suite\n');
    fprintf('========================================\n\n');

    % Setup paths
    testDir = fileparts(mfilename('fullpath'));
    toolsDir = fullfile(testDir, '..', 'tools');
    addpath(toolsDir, testDir);
    cleanupPaths = onCleanup(@() rmpath(toolsDir, testDir));

    % Build and load model
    modelName = 'ExampleModel';
    buildExampleModel(modelName, testDir);
    cleanupModel = onCleanup(@() closeModel(modelName));

    % Define test cases: {name, function handle}
    testCases = {
        'List blocks by type',                       @() testListByType(modelName)
        'List blocks by type with PropertyName',     @() testListByTypeWithProperty(modelName)
        'Block type + SearchValue + PropertyName',   @() testBlockTypeSearchProperty(modelName)
        'Block type + SearchValue (all properties)', @() testBlockTypeSearchAll(modelName)
        'SearchValue + PropertyName (all types)',    @() testSearchValueProperty(modelName)
        'SearchValue only (all types, all props)',   @() testSearchValueAll(modelName)
        'Partial match',                             @() testPartialMatch(modelName)
        'No matches found',                          @() testNoMatches(modelName)
        'Value replacement',                         @() testReplacement(modelName)
        'NewValue ignored in listing mode',          @() testNewValueWarning(modelName)
        'Error when no criteria provided',           @() testErrorNoCriteria(modelName)
    };

    % Run tests
    totalPassed = 0;
    totalFailed = 0;
    failMessages = {};

    for k = 1:size(testCases, 1)
        [p, f, msgs] = runTest(testCases{k, 1}, testCases{k, 2});
        totalPassed = totalPassed + p;
        totalFailed = totalFailed + f;
        failMessages = [failMessages, msgs]; %#ok<AGROW>
    end

    % Summary
    fprintf('\n========================================\n');
    if totalFailed == 0
        fprintf('  ALL PASSED: %d / %d\n', totalPassed, totalPassed);
    else
        fprintf('  RESULTS: %d passed, %d FAILED\n', totalPassed, totalFailed);
        fprintf('\n  Failures:\n');
        for k = 1:numel(failMessages)
            fprintf('    - %s\n', failMessages{k});
        end
    end
    fprintf('========================================\n\n');
end

%% --- Test Runner ---

function [passed, failed, messages] = runTest(testName, testFn)
    fprintf('\n--- Test: %s ---\n', testName);
    try
        [callStr, description, testExec] = testFn();
        fprintf('  Call:   %s\n', callStr);
        fprintf('  Expect: %s\n', description);
        % Suppress function output; capture it to show on failure
        [functionOutput, failures] = evalc('testExec()');
        if isempty(failures)
            fprintf('  >> PASS\n');
            passed = 1; failed = 0; messages = {};
        else
            fprintf('  >> FAIL\n');
            fprintf('%s', functionOutput);
            for k = 1:numel(failures)
                fprintf('     %s\n', failures{k});
            end
            passed = 0; failed = 1;
            messages = {sprintf('%s: %s', testName, strjoin(failures, '; '))};
        end
    catch ME
        fprintf('  >> ERROR: %s\n', ME.message);
        passed = 0; failed = 1;
        messages = {sprintf('%s: %s', testName, ME.message)};
    end
end

%% --- Model Builder ---
%
%   Block layout:
%       Gain1       Gain='2'                  SampleTime='-1' (default)
%       Gain2       Gain='3'                  SampleTime='0.01'
%       Gain3       Gain='2'                  SampleTime='0.05'
%       Constant1   Value='42'                SampleTime='0.01'
%       Constant2   Value='99'                SampleTime='0.1'
%       UnitDelay1  InitialCondition='0'      SampleTime='0.01'
%       UnitDelay2  InitialCondition='0'      SampleTime='0.1'
%       SubSystem/
%           Gain4   Gain='2'                  SampleTime='0.01'

function buildExampleModel(modelName, saveDir)
    if bdIsLoaded(modelName)
        close_system(modelName, 0);
    end

    % Delete stale file to avoid shadow warning on rebuild
    oldFile = fullfile(saveDir, [modelName '.slx']);
    if exist(oldFile, 'file')
        delete(oldFile);
    end

    new_system(modelName);

    % Gain blocks
    add_block('simulink/Math Operations/Gain', [modelName '/Gain1'], ...
        'Gain', '2', 'Position', [100 30 160 60]);

    add_block('simulink/Math Operations/Gain', [modelName '/Gain2'], ...
        'Gain', '3', 'Position', [100 100 160 130]);
    set_param([modelName '/Gain2'], 'SampleTime', '0.01');

    add_block('simulink/Math Operations/Gain', [modelName '/Gain3'], ...
        'Gain', '2', 'Position', [100 170 160 200]);
    set_param([modelName '/Gain3'], 'SampleTime', '0.05');

    % Constant blocks
    add_block('simulink/Sources/Constant', [modelName '/Constant1'], ...
        'Value', '42', 'Position', [280 30 340 60]);
    set_param([modelName '/Constant1'], 'SampleTime', '0.01');

    add_block('simulink/Sources/Constant', [modelName '/Constant2'], ...
        'Value', '99', 'Position', [280 100 340 130]);
    set_param([modelName '/Constant2'], 'SampleTime', '0.1');

    % Discrete blocks
    add_block('simulink/Discrete/Unit Delay', [modelName '/UnitDelay1'], ...
        'SampleTime', '0.01', 'Position', [280 170 340 200]);

    add_block('simulink/Discrete/Unit Delay', [modelName '/UnitDelay2'], ...
        'SampleTime', '0.1', 'Position', [280 240 340 270]);

    % Subsystem with a Gain block inside
    add_block('simulink/Ports & Subsystems/Subsystem', [modelName '/SubSystem'], ...
        'Position', [100 260 200 310]);
    delete_line([modelName '/SubSystem'], 'In1/1', 'Out1/1');
    delete_block([modelName '/SubSystem/In1']);
    delete_block([modelName '/SubSystem/Out1']);

    add_block('simulink/Math Operations/Gain', [modelName '/SubSystem/Gain4'], ...
        'Gain', '2', 'Position', [100 30 160 60]);
    set_param([modelName '/SubSystem/Gain4'], 'SampleTime', '0.01');

    save_system(modelName, fullfile(saveDir, modelName));
    fprintf('Built and saved %s.slx\n\n', modelName);
end

%% --- Test Cases ---

function [callStr, description, execFn] = testListByType(modelName)
    callStr = sprintf('findAndReplaceBlockParams(''%s'', BlockType=''Gain'')', modelName);
    description = 'Lists all Gain blocks (expects 4 across model and subsystem)';
    execFn = @() checkResults( ...
        findAndReplaceBlockParams(modelName, BlockType='Gain'), 4, {
            [modelName '/Gain1']
            [modelName '/Gain2']
            [modelName '/Gain3']
            [modelName '/SubSystem/Gain4']});
end

function [callStr, description, execFn] = testListByTypeWithProperty(modelName)
    callStr = sprintf('findAndReplaceBlockParams(''%s'', BlockType=''Gain'', PropertyName=''Gain'')', modelName);
    description = 'Lists all Gain blocks and shows their Gain property values';
    execFn = @() runListByTypeWithProperty(modelName);
end

function failures = runListByTypeWithProperty(modelName)
    results = findAndReplaceBlockParams(modelName, BlockType='Gain', PropertyName='Gain');
    failures = checkResults(results, 4, {
        [modelName '/Gain1']
        [modelName '/Gain2']
        [modelName '/Gain3']
        [modelName '/SubSystem/Gain4']});
    for k = 1:numel(results)
        if ~strcmp(results(k).PropertyName, 'Gain')
            failures{end+1} = sprintf('Expected PropertyName=Gain, got %s for %s', ...
                results(k).PropertyName, results(k).BlockPath); %#ok<AGROW>
        end
    end
end

function [callStr, description, execFn] = testBlockTypeSearchProperty(modelName)
    callStr = sprintf('findAndReplaceBlockParams(''%s'', BlockType=''Gain'', SearchValue=''2'', PropertyName=''Gain'')', modelName);
    description = 'Searches only Gain blocks for Gain=''2'' (expects 3: Gain1, Gain3, SubSystem/Gain4)';
    execFn = @() checkResults( ...
        findAndReplaceBlockParams(modelName, BlockType='Gain', SearchValue='2', PropertyName='Gain'), 3, {
            [modelName '/Gain1']
            [modelName '/Gain3']
            [modelName '/SubSystem/Gain4']});
end

function [callStr, description, execFn] = testBlockTypeSearchAll(modelName)
    callStr = sprintf('findAndReplaceBlockParams(''%s'', BlockType=''Gain'', SearchValue=''3'')', modelName);
    description = 'Searches all dialog properties on Gain blocks for ''3'' (expects Gain2 only)';
    execFn = @() runBlockTypeSearchAll(modelName);
end

function failures = runBlockTypeSearchAll(modelName)
    results = findAndReplaceBlockParams(modelName, BlockType='Gain', SearchValue='3');
    failures = checkContains(results, {[modelName '/Gain2']});
    failures = [failures, checkExcludes(results, {
        [modelName '/Gain1']
        [modelName '/Gain3']
        [modelName '/SubSystem/Gain4']})];
end

function [callStr, description, execFn] = testSearchValueProperty(modelName)
    callStr = sprintf('findAndReplaceBlockParams(''%s'', SearchValue=''0.01'', PropertyName=''SampleTime'')', modelName);
    description = 'Searches SampleTime on all block types for ''0.01'' (expects 4 matches)';
    execFn = @() checkResults( ...
        findAndReplaceBlockParams(modelName, SearchValue='0.01', PropertyName='SampleTime'), 4, {
            [modelName '/Gain2']
            [modelName '/Constant1']
            [modelName '/UnitDelay1']
            [modelName '/SubSystem/Gain4']});
end

function [callStr, description, execFn] = testSearchValueAll(modelName)
    callStr = sprintf('findAndReplaceBlockParams(''%s'', SearchValue=''42'')', modelName);
    description = 'Searches all dialog properties on all blocks for ''42'' (expects Constant1 Value)';
    execFn = @() runSearchValueAll(modelName);
end

function failures = runSearchValueAll(modelName)
    results = findAndReplaceBlockParams(modelName, SearchValue='42');
    failures = checkContains(results, {[modelName '/Constant1']});
    idx = strcmp({results.BlockPath}, [modelName '/Constant1']);
    if any(idx)
        matches = results(idx);
        if ~any(strcmp({matches.PropertyName}, 'Value'))
            failures{end+1} = 'Expected Constant1 match on Value property';
        end
    end
end

function [callStr, description, execFn] = testPartialMatch(modelName)
    callStr = sprintf('findAndReplaceBlockParams(''%s'', SearchValue=''0.0'', PropertyName=''SampleTime'', PartialMatch=true)', modelName);
    description = 'Substring match ''0.0'' in SampleTime matches 0.01/0.05 but not 0.1/-1 (expects 5)';
    execFn = @() checkResults( ...
        findAndReplaceBlockParams(modelName, SearchValue='0.0', PropertyName='SampleTime', PartialMatch=true), 5, {
            [modelName '/Gain2']
            [modelName '/Gain3']
            [modelName '/Constant1']
            [modelName '/UnitDelay1']
            [modelName '/SubSystem/Gain4']});
end

function [callStr, description, execFn] = testNoMatches(modelName)
    callStr = sprintf('findAndReplaceBlockParams(''%s'', SearchValue=''nonexistent_value'', PropertyName=''Gain'')', modelName);
    description = 'Returns empty results when no blocks match';
    execFn = @() runNoMatches(modelName);
end

function failures = runNoMatches(modelName)
    results = findAndReplaceBlockParams(modelName, SearchValue='nonexistent_value', PropertyName='Gain');
    failures = {};
    if ~isempty(results)
        failures{end+1} = sprintf('Expected 0 results, got %d', numel(results));
    end
end

function [callStr, description, execFn] = testReplacement(modelName)
    callStr = sprintf('findAndReplaceBlockParams(''%s'', BlockType=''Gain'', SearchValue=''3'', PropertyName=''Gain'', NewValue=''7'')', modelName);
    description = 'Replaces Gain2 Gain property from ''3'' to ''7'', then restores';
    execFn = @() runReplacement(modelName);
end

function failures = runReplacement(modelName)
    failures = {};
    findAndReplaceBlockParams(modelName, BlockType='Gain', ...
        SearchValue='3', PropertyName='Gain', NewValue='7');
    actualValue = get_param([modelName '/Gain2'], 'Gain');
    if ~strcmp(actualValue, '7')
        failures{end+1} = sprintf('Expected Gain=7 after replacement, got %s', actualValue);
    end
    set_param([modelName '/Gain2'], 'Gain', '3');
end

function [callStr, description, execFn] = testNewValueWarning(modelName)
    callStr = sprintf('findAndReplaceBlockParams(''%s'', BlockType=''Gain'', NewValue=''999'')', modelName);
    description = 'Warns that NewValue is ignored when SearchValue is empty, no blocks modified';
    execFn = @() runNewValueWarning(modelName);
end

function failures = runNewValueWarning(modelName)
    failures = {};
    lastwarn('', '');
    findAndReplaceBlockParams(modelName, BlockType='Gain', NewValue='999');
    [~, warnId] = lastwarn;
    if ~strcmp(warnId, 'findAndReplaceBlockParams:NoSearchValue')
        failures{end+1} = sprintf('Expected NoSearchValue warning, got: %s', warnId);
    end
    actualValue = get_param([modelName '/Gain1'], 'Gain');
    if ~strcmp(actualValue, '2')
        failures{end+1} = sprintf('Gain1 was modified unexpectedly: Gain=%s', actualValue);
    end
end

function [callStr, description, execFn] = testErrorNoCriteria(modelName)
    callStr = sprintf('findAndReplaceBlockParams(''%s'')', modelName);
    description = 'Throws InsufficientArgs error when neither BlockType nor SearchValue provided';
    execFn = @() runErrorNoCriteria(modelName);
end

function failures = runErrorNoCriteria(modelName)
    failures = {};
    try
        findAndReplaceBlockParams(modelName);
        failures{end+1} = 'Expected an error but none was thrown';
    catch ME
        if ~strcmp(ME.identifier, 'findAndReplaceBlockParams:InsufficientArgs')
            failures{end+1} = sprintf('Expected InsufficientArgs error, got: %s', ME.identifier);
        end
    end
end

%% --- Assertion Helpers ---

function failures = checkResults(results, expectedCount, expectedPaths)
    failures = {};
    if numel(results) ~= expectedCount
        failures{end+1} = sprintf('Expected %d results, got %d', expectedCount, numel(results));
    end
    failures = [failures, checkContains(results, expectedPaths)];
end

function failures = checkContains(results, expectedPaths)
    failures = {};
    if isempty(results) && ~isempty(expectedPaths)
        failures{end+1} = 'Expected results but got empty';
        return;
    end
    actualPaths = {results.BlockPath};
    for k = 1:numel(expectedPaths)
        if ~any(strcmp(actualPaths, expectedPaths{k}))
            failures{end+1} = sprintf('Missing: %s', expectedPaths{k}); %#ok<AGROW>
        end
    end
end

function failures = checkExcludes(results, excludedPaths)
    failures = {};
    if isempty(results)
        return;
    end
    actualPaths = {results.BlockPath};
    for k = 1:numel(excludedPaths)
        if any(strcmp(actualPaths, excludedPaths{k}))
            failures{end+1} = sprintf('Unexpected match: %s', excludedPaths{k}); %#ok<AGROW>
        end
    end
end

%% --- Cleanup ---

function closeModel(modelName)
    if bdIsLoaded(modelName)
        close_system(modelName, 0);
    end
end
