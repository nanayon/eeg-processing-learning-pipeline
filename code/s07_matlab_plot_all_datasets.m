%% s07_matlab_plot_all_datasets
% 按照 s05 的连续信号绘图方法，批量处理 TWC_USA 的全部 EDF。
%
% 输出逻辑：
%   1. 每个数据集生成一张“第一条有效事件到最后一条有效事件”的连续总览图；
%   2. 连续总览保留全部事件，并为事件写入序号、代码、类别和含义；
%   3. 对 code 1-20、23、29 生成事件锁定 epoch 截图；
%   4. epoch 默认使用 [-2, 20] 秒，并对记录边界进行裁剪标记；
%   5. 沿用 s05 的显示通道：EMG、R-HEOG、L-VEOG、26、27。
%
% 本脚本是新的批处理入口，不修改 s05 或其他已有脚本。
% 结果图、事件表和运行汇总写入本地被 .gitignore 排除的目录。

clear;
clc;

%% 1. 工程路径、输出目录与 EEGLAB 初始化
projectDir = fileparts(fileparts(mfilename('fullpath')));
rawDir = fullfile(projectDir, 'raw', 'TWC_USA', 'Data', 'PSG');
resultDir = fullfile(projectDir, 'results', 's07_all_datasets');
figureDir = fullfile(projectDir, 'figures', 's07_all_datasets');
codeDir = fileparts(mfilename('fullpath'));

if ~isfolder(rawDir)
    error('找不到 EDF 数据目录：%s', rawDir);
end
if ~isfolder(resultDir)
    mkdir(resultDir);
end
if ~isfolder(figureDir)
    mkdir(figureDir);
end

addpath(codeDir);
eeglabRoot = 'E:\Application\Matlab\toolbox\eeglab2026.0.0';
if ~isfolder(eeglabRoot)
    error('找不到 EEGLAB 安装目录：%s', eeglabRoot);
end
addpath(eeglabRoot);
eeglab('nogui');

%% 2. 批量参数
edfFiles = dir(fullfile(rawDir, '*.edf'));
if isempty(edfFiles)
    error('在 %s 中没有找到 EDF 文件。', rawDir);
end

[~, sortIndex] = sort(lower({edfFiles.name}));
edfFiles = edfFiles(sortIndex);

preferredDisplayLabels = ["EMG", "R-HEOG", "L-VEOG", "26", "27"];
displayRate = 250;
eegBand = [0.5, 35];
eogBand = [0.1, 15];
emgBand = [10, 100];
epochWindow = [-2, 20];

nCases = numel(edfFiles);
summaryRows = cell(nCases, 16);

%% 3. 逐个数据集导入、绘图并保存 epoch
for caseIndex = 1:nCases
    edfFile = fullfile(edfFiles(caseIndex).folder, edfFiles(caseIndex).name);
    [~, caseName] = fileparts(edfFiles(caseIndex).name);

    fprintf('[%02d/%02d] %s\n', caseIndex, nCases, caseName);
    try
        result = processOneCase(edfFile, resultDir, figureDir, ...
            preferredDisplayLabels, displayRate, eegBand, eogBand, ...
            emgBand, epochWindow);

        summaryRows(caseIndex, :) = { ...
            caseName, edfFiles(caseIndex).name, 'success', ...
            result.inputChannelCount, result.displayChannelCount, ...
            result.samplingRate, result.durationSeconds, ...
            result.eventCount, result.firstEventSeconds, ...
            result.lastEventSeconds, ...
            strjoin(cellstr(result.displayLabels), ', '), ...
            strjoin(cellstr(result.missingLabels), ', '), ...
            result.nativePngFile, result.epochDir, result.eventFile, ''};
    catch ME
        summaryRows(caseIndex, :) = { ...
            caseName, edfFiles(caseIndex).name, 'failed', ...
            NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
            '', '', '', '', '', ME.message};
        warning('处理 %s 失败：%s', caseName, ME.message);
    end
end

%% 4. 保存批处理汇总
summaryTable = cell2table(summaryRows, 'VariableNames', { ...
    'case_name','edf_file','status','input_channel_count', ...
    'display_channel_count','sampling_rate_hz','duration_seconds', ...
    'event_count','first_event_seconds','last_event_seconds', ...
    'display_channels','missing_channels','continuous_png', ...
    'epoch_directory','event_csv','error_message'});

summaryFile = fullfile(resultDir, 's07_all_datasets_summary.csv');
writetable(summaryTable, summaryFile);

successCount = sum(strcmp(summaryTable.status, 'success'));
fprintf('\n===== s07 全数据集事件绘图完成 =====\n');
fprintf('成功：%d/%d；失败：%d。\n', successCount, nCases, nCases - successCount);
fprintf('截图目录：%s\n', figureDir);
fprintf('汇总表：%s\n', summaryFile);

%% 局部函数
function result = processOneCase(edfFile, resultDir, figureDir, ...
        preferredDisplayLabels, displayRate, eegBand, eogBand, ...
        emgBand, epochWindow)

[~, caseName] = fileparts(edfFile);
caseId = parseCaseId(caseName);

% 导入完整连续记录；本批处理阶段不先切成一个总 epoch。
EEG = pop_biosig(edfFile, 'importevent', 'on', ...
    'importannot', 'on', 'blockepoch', 'off', 'rmeventchan', 'on');
EEG = eeg_checkset(EEG);

recordSeconds = EEG.pnts / EEG.srate;
inputChannelCount = EEG.nbchan;
[eventTable, EEG] = buildEventTable(EEG, caseId);

validEventRows = find(isfinite(eventTable.TimeSeconds));
if isempty(validEventRows)
    error('%s 没有可用事件。', caseName);
end

eventTable = sortrows(eventTable, 'TimeSeconds');
validEventRows = find(isfinite(eventTable.TimeSeconds));
firstEventSeconds = eventTable.TimeSeconds(validEventRows(1));
lastEventSeconds = eventTable.TimeSeconds(validEventRows(end));

eventFile = fullfile(resultDir, [caseName, '_s07_events.csv']);
writetable(eventTable, eventFile);

[displayIndices, displayLabels, missingLabels, channelKinds] = ...
    resolveDisplayChannels(EEG, preferredDisplayLabels);
if isempty(displayIndices)
    error('%s 没有找到可显示的通道。', caseName);
end

% 只保留 s05 的显示通道，再按通道类别分别滤波和重采样。
displayEEG = pop_select(EEG, 'channel', displayIndices);
clear EEG;
[displayData, displayTime] = buildDisplayData(displayEEG, channelKinds, ...
    displayRate, eegBand, eogBand, emgBand);
clear displayEEG;

[~, signalY, offsets] = stackDisplayData(displayData);
clear displayData;

% 当记录只有一条事件时，首末事件时间相同；此时退回整段记录，避免只画一个点。
overviewStart = max(0, firstEventSeconds);
overviewEnd = min(displayTime(end), lastEventSeconds);
if overviewEnd <= overviewStart
    overviewStart = 0;
    overviewEnd = displayTime(end);
end

nativeBase = fullfile(figureDir, ...
    [caseName, '_s07_first_event_to_last_event']);
[~, nativePngFile] = saveTimelineFigure(displayTime, signalY, offsets, ...
    displayLabels, eventTable, overviewStart, overviewEnd, false, ...
    nativeBase, caseName);

epochDir = fullfile(figureDir, caseName, 'target_epochs');
if ~isfolder(epochDir)
    mkdir(epochDir);
end

% 目标事件：数学题、TLR 光提示和 TLR 声音提示。
targetMask = isfinite(eventTable.NumericCode) & ...
    ((eventTable.NumericCode >= 1 & eventTable.NumericCode <= 20) | ...
    eventTable.NumericCode == 23 | eventTable.NumericCode == 29);
targetRows = find(targetMask);

epochEventIndex = zeros(numel(targetRows), 1);
epochTime = nan(numel(targetRows), 1);
epochCode = nan(numel(targetRows), 1);
epochClass = strings(numel(targetRows), 1);
epochName = strings(numel(targetRows), 1);
epochRequestedStart = nan(numel(targetRows), 1);
epochRequestedEnd = nan(numel(targetRows), 1);
epochUsedStart = nan(numel(targetRows), 1);
epochUsedEnd = nan(numel(targetRows), 1);
epochClipped = false(numel(targetRows), 1);
epochPng = strings(numel(targetRows), 1);

for epochPosition = 1:numel(targetRows)
    row = targetRows(epochPosition);
    eventTime = eventTable.TimeSeconds(row);
    outputToken = eventFileToken(eventTable(row, :));
    outputBase = fullfile(epochDir, outputToken);

    [pngFile, usedStart, usedEnd, clipped] = saveEpochFigure( ...
        displayTime, signalY, displayLabels, eventTable, row, ...
        eventTime, epochWindow, outputBase, caseName);

    epochEventIndex(epochPosition) = eventTable.EventIndex(row);
    epochTime(epochPosition) = eventTime;
    epochCode(epochPosition) = eventTable.NumericCode(row);
    epochClass(epochPosition) = eventTable.EventClass(row);
    epochName(epochPosition) = eventTable.EventName(row);
    epochRequestedStart(epochPosition) = eventTime + epochWindow(1);
    epochRequestedEnd(epochPosition) = eventTime + epochWindow(2);
    epochUsedStart(epochPosition) = usedStart;
    epochUsedEnd(epochPosition) = usedEnd;
    epochClipped(epochPosition) = clipped;
    epochPng(epochPosition) = string(pngFile);
end

epochTable = table(epochEventIndex, epochTime, epochCode, epochClass, ...
    epochName, epochRequestedStart, epochRequestedEnd, epochUsedStart, ...
    epochUsedEnd, epochClipped, epochPng, ...
    'VariableNames', {'event_index','event_time_seconds','numeric_code', ...
    'event_class','event_name','requested_start_seconds', ...
    'requested_end_seconds','used_start_seconds','used_end_seconds', ...
    'edge_clipped','png_file'});
epochFile = fullfile(resultDir, [caseName, '_s07_target_epochs.csv']);
writetable(epochTable, epochFile);

result = struct();
result.inputChannelCount = inputChannelCount;
result.displayChannelCount = numel(displayLabels);
result.samplingRate = 1000;
result.durationSeconds = recordSeconds;
result.eventCount = height(eventTable);
result.firstEventSeconds = firstEventSeconds;
result.lastEventSeconds = lastEventSeconds;
result.displayLabels = displayLabels;
result.missingLabels = missingLabels;
result.nativePngFile = nativePngFile;
result.epochDir = epochDir;
result.eventFile = eventFile;
result.epochFile = epochFile;
end

function [displayData, displayTime] = buildDisplayData(displayEEG, ...
        channelKinds, displayRate, eegBand, eogBand, emgBand)

nChannels = numel(channelKinds);
displayData = [];
for channelIndex = 1:nChannels
    oneChannel = pop_select(displayEEG, 'channel', channelIndex);
    band = filterBandForKind(channelKinds(channelIndex), ...
        eegBand, eogBand, emgBand, oneChannel.srate);
    oneChannel = pop_eegfiltnew(oneChannel, band(1), band(2));
    oneChannel = pop_resample(oneChannel, displayRate);

    if channelIndex == 1
        displayData = zeros(nChannels, oneChannel.pnts);
    end

    nSamples = min(size(displayData, 2), oneChannel.pnts);
    displayData(channelIndex, 1:nSamples) = ...
        double(oneChannel.data(1, 1:nSamples, 1));
    clear oneChannel;
end

displayTime = (0:size(displayData, 2)-1) / displayRate;
end

function band = filterBandForKind(kind, eegBand, eogBand, emgBand, samplingRate)
switch kind
    case "EOG"
        band = eogBand;
    case "EMG"
        band = emgBand;
    otherwise
        band = eegBand;
end

nyquist = samplingRate / 2;
band(2) = min(band(2), nyquist - 1);
if band(2) <= band(1)
    band(1) = max(0.1, band(2) / 2);
end
end

function [eventTable, EEG] = buildEventTable(EEG, caseId)
nEvents = numel(EEG.event);
eventIndex = (1:nEvents)';
rawType = strings(nEvents, 1);
numericCode = nan(nEvents, 1);
eventLatency = nan(nEvents, 1);
eventTimeSeconds = nan(nEvents, 1);
eventClass = strings(nEvents, 1);
eventName = strings(nEvents, 1);
eventMeaning = strings(nEvents, 1);
eventRole = strings(nEvents, 1);
eventLabel = strings(nEvents, 1);
isTargetEpoch = false(nEvents, 1);

for eventPosition = 1:nEvents
    rawType(eventPosition) = string(EEG.event(eventPosition).type);
    numericType = str2double(strtrim(rawType(eventPosition)));
    eventLatency(eventPosition) = double(EEG.event(eventPosition).latency);
    eventTimeSeconds(eventPosition) = ...
        (eventLatency(eventPosition) - 1) / EEG.srate;

    if isfinite(numericType)
        code = round(numericType);
        numericCode(eventPosition) = code;
        eventClass(eventPosition) = eventClassFromCode(code);
        eventMeaning(eventPosition) = string( ...
            twcUSA_event_meaning(code, caseId));
        eventName(eventPosition) = eventNameFromCode(code);
        eventRole(eventPosition) = triggerRoleFromCode(code);
        isTargetEpoch(eventPosition) = isTargetCode(code);
        eventLabel(eventPosition) = string(sprintf( ...
            'E%03d | code_%d | %s | %s', eventPosition, code, ...
            char(eventClass(eventPosition)), ...
            char(eventMeaning(eventPosition))));
        EEG.event(eventPosition).type = char(eventLabel(eventPosition));
    else
        eventClass(eventPosition) = "other";
        eventName(eventPosition) = "other_event";
        eventMeaning(eventPosition) = "非数字事件代码";
        eventRole(eventPosition) = "context_only";
        eventLabel(eventPosition) = string(sprintf( ...
            'E%03d | %s | other', eventPosition, char(rawType(eventPosition))));
    end
end

eventTable = table(eventIndex, rawType, numericCode, eventLatency, ...
    eventTimeSeconds, eventClass, eventName, eventMeaning, eventRole, ...
    isTargetEpoch, eventLabel, ...
    'VariableNames', {'EventIndex','RawType','NumericCode', ...
    'LatencySamples','TimeSeconds','EventClass','EventName', ...
    'EventMeaning','TriggerRole','IsTargetEpoch','EventLabel'});
end

function [indices, displayLabels, missingLabels, channelKinds] = ...
        resolveDisplayChannels(EEG, preferredLabels)

labels = string({EEG.chanlocs.labels})';
used = false(numel(labels), 1);
indices = zeros(0, 1);
displayLabels = strings(0, 1);
missingLabels = strings(0, 1);
channelKinds = strings(0, 1);

% 26、27 根据 DREAM 数据说明是备用下巴 EMG，而不是普通 EEG。
kindNames = ["EMG", "EOG", "EOG", "EMG", "EMG"];
aliasGroups = { ...
    ["EMG", "EMG1", "EMG2", "CHIN", "CHIN-EMG", "CHIN EMG"], ...
    ["R-HEOG", "RHEOG", "HEOG-R", "ROC", "R-EOG", "EOG2"], ...
    ["L-VEOG", "LVEOG", "VEOG-L", "LOC", "L-EOG", "EOG1"], ...
    ["26"], ...
    ["27"]};

for labelIndex = 1:numel(preferredLabels)
    actualKind = kindNames(labelIndex);
    idx = findChannel(labels, aliasGroups{labelIndex}, used);

    if isempty(idx) && labelIndex >= 4
        idx = findFallbackEEG(labels, used);
        if ~isempty(idx)
            actualKind = "EEG";
        end
    end

    if isempty(idx)
        missingLabels(end+1, 1) = preferredLabels(labelIndex); %#ok<AGROW>
        continue;
    end

    used(idx) = true;
    indices(end+1, 1) = idx; %#ok<AGROW>
    displayLabels(end+1, 1) = labels(idx); %#ok<AGROW>
    channelKinds(end+1, 1) = actualKind; %#ok<AGROW>
end
end

function idx = findChannel(labels, aliases, used)
normalizedLabels = normalizeChannelLabels(labels);
normalizedAliases = normalizeChannelLabels(aliases(:));
idx = find(ismember(normalizedLabels, normalizedAliases) & ~used, 1);

if isempty(idx)
    for aliasIndex = 1:numel(normalizedAliases)
        candidate = find(contains(normalizedLabels, ...
            normalizedAliases(aliasIndex)) & ~used, 1);
        if ~isempty(candidate)
            idx = candidate;
            return;
        end
    end
end
end

function idx = findFallbackEEG(labels, used)
normalizedLabels = normalizeChannelLabels(labels);
isPhysiology = contains(normalizedLabels, "eog") | ...
    contains(normalizedLabels, "heog") | ...
    contains(normalizedLabels, "veog") | ...
    contains(normalizedLabels, "emg") | ...
    contains(normalizedLabels, "chin") | ...
    contains(normalizedLabels, "status");
idx = find(~used & ~isPhysiology, 1);
end

function normalizedLabels = normalizeChannelLabels(labels)
normalizedLabels = regexprep(lower(string(labels)), ...
    '[^a-zA-Z0-9]', '');
end

function [normalizedData, signalY, offsets] = stackDisplayData(displayData)
nChannels = size(displayData, 1);
normalizedData = zeros(size(displayData));

for channelIndex = 1:nChannels
    channelData = double(displayData(channelIndex, :));
    centerValue = median(channelData, 'omitnan');
    if ~isfinite(centerValue)
        centerValue = 0;
    end
    channelData = channelData - centerValue;

    channelScale = std(channelData, 'omitnan');
    if channelScale == 0 || ~isfinite(channelScale)
        channelScale = 1;
    end
    normalizedData(channelIndex, :) = channelData / channelScale;
end

offsets = (nChannels:-1:1) * 6;
signalY = normalizedData + offsets(:);
end

function [figureFile, pngFile] = saveTimelineFigure(displayTime, signalY, ...
        offsets, displayLabels, eventTable, startTime, endTime, ...
        relativeTime, outputBase, caseName)

sampleMask = displayTime >= startTime & displayTime <= endTime;
if ~any(sampleMask)
    error('%s 没有落在绘图区间内的显示样本。', caseName);
end

plotTime = displayTime(sampleMask);
if relativeTime
    plotTime = plotTime - startTime;
    xStart = 0;
    xEnd = endTime - startTime;
else
    xStart = startTime;
    xEnd = endTime;
end
if xEnd <= xStart
    xEnd = xStart + 1;
end

plotSignal = signalY(:, sampleMask);
[categoryNames, categoryColors, categoryStyles] = eventStyles();
displayColors = {'k','b','r','m','g','c','y'};

figureHandle = figure('Name', [caseName, ' | s07 all events'], ...
    'Color', 'w', 'Position', [50 40 1800 1000], 'Visible', 'off');
axesHandle = axes(figureHandle);
hold(axesHandle, 'on');

for channelIndex = 1:size(plotSignal, 1)
    colorIndex = 1 + mod(channelIndex - 1, numel(displayColors));
    plot(axesHandle, plotTime, plotSignal(channelIndex, :), ...
        'Color', displayColors{colorIndex}, 'LineWidth', 0.6, ...
        'HandleVisibility', 'off');
end

eventRows = find(isfinite(eventTable.TimeSeconds) & ...
    eventTable.TimeSeconds >= startTime & ...
    eventTable.TimeSeconds <= endTime);

for eventPosition = 1:numel(eventRows)
    row = eventRows(eventPosition);
    categoryIndex = find(categoryNames == ...
        eventTable.EventClass(row), 1);
    if isempty(categoryIndex)
        categoryIndex = numel(categoryNames);
    end

    eventX = eventTable.TimeSeconds(row);
    if relativeTime
        eventX = eventX - startTime;
    end
    eventLine = xline(axesHandle, eventX);
    eventLine.Color = categoryColors(categoryIndex, :);
    eventLine.LineStyle = categoryStyles{categoryIndex};
    eventLine.LineWidth = 1.0;
    eventLine.HandleVisibility = 'off';
end

legendHandles = gobjects(numel(categoryNames), 1);
for categoryIndex = 1:numel(categoryNames)
    legendHandles(categoryIndex) = plot(axesHandle, nan, nan, ...
        'Color', categoryColors(categoryIndex, :), ...
        'LineStyle', categoryStyles{categoryIndex}, ...
        'LineWidth', 1.5);
end
legend(axesHandle, legendHandles, cellstr(categoryNames), ...
    'Location', 'eastoutside');

finiteSignalValues = plotSignal(isfinite(plotSignal));
if isempty(finiteSignalValues)
    finiteSignalValues = [0, 1];
end
signalMin = min(finiteSignalValues);
signalMax = max(finiteSignalValues);
labelBase = signalMax + 3;
labelSpacing = 5;

for eventPosition = 1:numel(eventRows)
    row = eventRows(eventPosition);
    categoryIndex = find(categoryNames == ...
        eventTable.EventClass(row), 1);
    if isempty(categoryIndex)
        categoryIndex = numel(categoryNames);
    end

    eventX = eventTable.TimeSeconds(row);
    if relativeTime
        eventX = eventX - startTime;
    end
    labelY = labelBase + mod(eventPosition - 1, 4) * labelSpacing;
    text(axesHandle, eventX, labelY, ...
        char(eventTable.EventLabel(row)), ...
        'Rotation', 90, 'VerticalAlignment', 'bottom', ...
        'HorizontalAlignment', 'left', 'FontSize', 7, ...
        'Color', categoryColors(categoryIndex, :), ...
        'Interpreter', 'none');
end

yLower = min(signalMin, 0) - 2;
yUpper = labelBase + 4 * labelSpacing + 5;
ylim(axesHandle, [yLower, yUpper]);
xlim(axesHandle, [xStart, xEnd]);
grid(axesHandle, 'on');
yticks(axesHandle, sort(offsets));
yticklabels(axesHandle, cellstr(flipud(displayLabels(:))));
xlabel(axesHandle, '记录时间 (s)');
ylabel(axesHandle, '显示波形（通道内标准化并错开）');

if relativeTime
    title(axesHandle, sprintf( ...
        '%s：首事件到末事件（相对时间）；原始 %.3f–%.3f s', ...
        caseName, startTime, endTime));
else
    title(axesHandle, sprintf( ...
        '%s：首事件到末事件（绝对时间 %.3f–%.3f s）', ...
        caseName, startTime, endTime));
end

figureFile = [outputBase, '.fig'];
pngFile = [outputBase, '.png'];
drawnow;
savefig(figureHandle, figureFile);
exportgraphics(figureHandle, pngFile, 'Resolution', 150);
close(figureHandle);
end

function [pngFile, usedStart, usedEnd, clipped] = saveEpochFigure( ...
        displayTime, signalY, displayLabels, eventTable, row, ...
        eventTime, epochWindow, outputBase, caseName)

requestedStart = eventTime + epochWindow(1);
requestedEnd = eventTime + epochWindow(2);
usedStart = max(0, requestedStart);
usedEnd = min(displayTime(end), requestedEnd);
clipped = usedStart > requestedStart || usedEnd < requestedEnd;

startSample = find(displayTime >= usedStart, 1, 'first');
endSample = find(displayTime <= usedEnd, 1, 'last');
if isempty(startSample) || isempty(endSample) || endSample < startSample
    error('%s 的事件 %d 没有可用 epoch 样本。', ...
        caseName, eventTable.EventIndex(row));
end

epochData = signalY(:, startSample:endSample);
[~, epochSignalY, offsets] = stackDisplayData(epochData);
epochTime = displayTime(startSample:endSample) - eventTime;

[categoryNames, categoryColors, categoryStyles] = eventStyles();
displayColors = {'k','b','r','m','g','c','y'};

figureHandle = figure('Name', [caseName, ' | ', ...
    char(eventTable.EventName(row))], 'Color', 'w', ...
    'Position', [80 60 1600 900], 'Visible', 'off');
axesHandle = axes(figureHandle);
hold(axesHandle, 'on');

for channelIndex = 1:size(epochSignalY, 1)
    colorIndex = 1 + mod(channelIndex - 1, numel(displayColors));
    plot(axesHandle, epochTime, epochSignalY(channelIndex, :), ...
        'Color', displayColors{colorIndex}, 'LineWidth', 0.8, ...
        'HandleVisibility', 'off');
end

epochEventRows = find(isfinite(eventTable.TimeSeconds) & ...
    eventTable.TimeSeconds >= usedStart & ...
    eventTable.TimeSeconds <= usedEnd);
for eventPosition = 1:numel(epochEventRows)
    eventRow = epochEventRows(eventPosition);
    categoryIndex = find(categoryNames == ...
        eventTable.EventClass(eventRow), 1);
    if isempty(categoryIndex)
        categoryIndex = numel(categoryNames);
    end

    eventX = eventTable.TimeSeconds(eventRow) - eventTime;
    eventLine = xline(axesHandle, eventX);
    eventLine.Color = categoryColors(categoryIndex, :);
    eventLine.LineStyle = categoryStyles{categoryIndex};
    eventLine.LineWidth = 1.0;
    eventLine.HandleVisibility = 'off';
end

finiteSignalValues = epochSignalY(isfinite(epochSignalY));
if isempty(finiteSignalValues)
    finiteSignalValues = [0, 1];
end
signalMin = min(finiteSignalValues);
signalMax = max(finiteSignalValues);
labelBase = signalMax + 3;

for eventPosition = 1:numel(epochEventRows)
    eventRow = epochEventRows(eventPosition);
    categoryIndex = find(categoryNames == ...
        eventTable.EventClass(eventRow), 1);
    if isempty(categoryIndex)
        categoryIndex = numel(categoryNames);
    end

    labelX = eventTable.TimeSeconds(eventRow) - eventTime;
    labelY = labelBase + mod(eventPosition - 1, 4) * 5;
    text(axesHandle, labelX, labelY, ...
        char(eventTable.EventLabel(eventRow)), ...
        'Rotation', 90, 'VerticalAlignment', 'bottom', ...
        'HorizontalAlignment', 'left', 'FontSize', 7, ...
        'Color', categoryColors(categoryIndex, :), ...
        'Interpreter', 'none');
end

yLower = min(signalMin, 0) - 2;
yUpper = labelBase + 4 * 5 + 5;
ylim(axesHandle, [yLower, yUpper]);
xlim(axesHandle, [epochTime(1), epochTime(end)]);
grid(axesHandle, 'on');
yticks(axesHandle, sort(offsets));
yticklabels(axesHandle, cellstr(flipud(displayLabels(:))));
xlabel(axesHandle, '相对事件时间 (s)');
ylabel(axesHandle, '窗口内标准化波形（通道内错开）');

if clipped
    edgeText = '；记录边界已裁剪';
else
    edgeText = '';
end
title(axesHandle, sprintf( ...
    '%s | event_%03d | code_%d | %s | %s | [%.1f, %.1f] s%s', ...
    caseName, eventTable.EventIndex(row), ...
    eventTable.NumericCode(row), ...
    char(eventTable.EventClass(row)), ...
    char(eventTable.EventMeaning(row)), ...
    epochWindow(1), epochWindow(2), edgeText));

pngFile = [outputBase, '.png'];
drawnow;
exportgraphics(figureHandle, pngFile, 'Resolution', 150);
close(figureHandle);
end

function [categoryNames, categoryColors, categoryStyles] = eventStyles()
categoryNames = ["math", "cue_audio", "cue_light_manual", ...
    "script_start", "volume_down", "volume_up", "other"];
categoryColors = [ ...
    0.15 0.45 0.85; ...
    0.95 0.50 0.10; ...
    0.10 0.60 0.20; ...
    0.85 0.10 0.10; ...
    0.55 0.20 0.75; ...
    0.00 0.60 0.60; ...
    0.40 0.40 0.40];
categoryStyles = {'-', '-.', '--', ':', '--', '-.', '-'};
end

function token = eventFileToken(eventRow)
if isfinite(eventRow.NumericCode)
    token = sprintf('event_%03d_code_%d_%s', ...
        eventRow.EventIndex, eventRow.NumericCode, ...
        char(eventRow.EventClass));
else
    token = sprintf('event_%03d_other', eventRow.EventIndex);
end
token = regexprep(token, '[^A-Za-z0-9_-]', '_');
end

function caseId = parseCaseId(caseName)
tokens = regexp(caseName, 'case(\d+)', 'tokens', 'once');
if isempty(tokens)
    caseId = 0;
else
    caseId = str2double(tokens{1});
end
end

function tf = isTargetCode(code)
tf = isfinite(code) && ...
    ((code >= 1 && code <= 20) || code == 23 || code == 29);
end

function category = eventClassFromCode(code)
if ~isfinite(code)
    category = "other";
elseif code >= 1 && code <= 20
    category = "math";
elseif code == 23
    category = "cue_light_manual";
elseif code == 29
    category = "cue_audio";
elseif code == 32
    category = "script_start";
elseif code == 64
    category = "volume_down";
elseif code == 65
    category = "volume_up";
else
    category = "other";
end
end

function name = eventNameFromCode(code)
if ~isfinite(code)
    name = "other_event";
elseif code >= 1 && code <= 20
    name = string(sprintf('math_problem_%02d', code));
elseif code == 23
    name = "cue_light_manual";
elseif code == 29
    name = "cue_audio";
elseif code == 32
    name = "script_start";
elseif code == 64
    name = "volume_down";
elseif code == 65
    name = "volume_up";
else
    name = string(sprintf('code_%d_other', code));
end
end

function role = triggerRoleFromCode(code)
if isTargetCode(code)
    role = "target_eye_response";
elseif code == 32 || code == 64 || code == 65
    role = "context_only";
else
    role = "context_only";
end
end
