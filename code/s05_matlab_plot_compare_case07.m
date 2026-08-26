%% s05_matlab_plot_compare_case07
% 对比 EEGLAB eegplot 和 MATLAB 原生 plot 的连续 EEG/EOG/EMG 显示方式
%
% 数据处理部分：使用 EEGLAB/BioSig 导入、EEGLAB 滤波、EEGLAB 重采样。
% 图像显示部分：同时打开 EEGLAB eegplot 和 MATLAB 原生 tiledlayout/plot。
%
% 本脚本的特点：
% 1. 不以任何事件为锚点；不调用 pop_epoch；整个记录保持连续。
% 2. 默认只显示 EMG、两个 EOG、26、27 五个通道。
% 3. 用户可以直接修改 displayLabels 手动选择通道。
% 4. MATLAB 原生图默认显示完整 816 秒，并支持工具栏缩放、平移和数据光标。

clear;
clc;

%% 1. 工程路径与 EEGLAB 初始化
projectDir = fileparts(fileparts(mfilename('fullpath')));
rawDir = fullfile(projectDir, 'raw', 'TWC_USA', 'Data', 'PSG');
resultDir = fullfile(projectDir, 'results');
figureDir = fullfile(projectDir, 'figures');
codeDir = fileparts(mfilename('fullpath'));

addpath(codeDir);

if ~exist(resultDir, 'dir')
    mkdir(resultDir);
end
if ~exist(figureDir, 'dir')
    mkdir(figureDir);
end

eeglabRoot = 'E:\Application\Matlab\toolbox\eeglab2026.0.0';
addpath(eeglabRoot);
eeglab('nogui');

%% 2. 用 EEGLAB/BioSig 导入完整连续 EDF
caseName = 'case07_sub106';
edfFile = fullfile(rawDir, [caseName, '.edf']);

if ~exist(edfFile, 'file')
    error('找不到 EDF 文件：%s', edfFile);
end

% 不切 epoch；导入后 EEG.data 始终表示整段连续记录。
EEG = pop_biosig(edfFile, 'importevent', 'on', ...
    'importannot', 'on', 'blockepoch', 'off', 'rmeventchan', 'on');
EEG = eeg_checkset(EEG);

%% 3. 给全部事件加上可读标签，但不筛选、不删除、不选择事件
nEvents = numel(EEG.event);
eventIndex = (1:nEvents)';
eventLabel = strings(nEvents, 1);
numericCode = nan(nEvents, 1);
eventLatency = nan(nEvents, 1);
eventTimeSeconds = nan(nEvents, 1);
eventMeaning = strings(nEvents, 1);
eventCategory = strings(nEvents, 1);

for k = 1:nEvents
    rawType = char(string(EEG.event(k).type));
    numericType = str2double(rawType);
    eventLatency(k) = EEG.event(k).latency;
    eventTimeSeconds(k) = (eventLatency(k) - 1) / EEG.srate;

    if isfinite(numericType)
        code = round(numericType);
        numericCode(k) = code;
        meaning = twcUSA_event_meaning(code, 7);
        category = eventCategoryFromCode(code);
        eventMeaning(k) = meaning;
        eventCategory(k) = category;
        eventLabel(k) = string(code) + ": " + meaning;
        EEG.event(k).type = char(eventLabel(k));
    else
        eventMeaning(k) = "非数字事件代码";
        eventCategory(k) = "其他事件";
        eventLabel(k) = string(rawType);
    end
end

EEG = eeg_checkset(EEG);
eventTable = table(eventIndex, eventLabel, numericCode, eventLatency, ...
    eventTimeSeconds, eventMeaning, eventCategory, ...
    'VariableNames', {'EventIndex','EventLabel','NumericCode', ...
    'LatencySamples','TimeSeconds','EventMeaning','EventCategory'});

eventFile = fullfile(resultDir, [caseName, '_s05_events.csv']);
writetable(eventTable, eventFile);

%% 4. 用 EEGLAB 在连续数据上滤波，再为显示重采样
% 这一步仍然是 EEGLAB 数据处理，不是 MATLAB 原生 plot 的处理。
EEG_eegContinuous = pop_eegfiltnew(EEG, 0.5, 35);
EEG_eogContinuous = pop_eegfiltnew(EEG, 0.1, 15);
EEG_emgContinuous = pop_eegfiltnew(EEG, 10, 100);

% 重采样只为让图形显示更流畅；原始 EDF 和正式分析数据不被覆盖。
displayRate = 250;
EEG_eegDisplay = pop_resample(EEG_eegContinuous, displayRate);
EEG_eogDisplay = pop_resample(EEG_eogContinuous, displayRate);
EEG_emgDisplay = pop_resample(EEG_emgContinuous, displayRate);

%% 5. 手动选择显示通道
% 这里修改通道名称，就能决定 MATLAB 原生图和 EEGLAB 图显示哪些通道。
% 顺序就是图中从上到下的顺序。
displayLabels = ["EMG", "R-HEOG", "L-VEOG", "26", "27"];

baseColors = {'k','b','r','m','g','c','y'};
displayColors = baseColors(1 + mod(0:numel(displayLabels)-1, ...
    numel(baseColors)));

nDisplayChannels = numel(displayLabels);
displayData = zeros(nDisplayChannels, EEG_eegDisplay.pnts);
displayChanlocs = EEG.chanlocs([]);

for k = 1:nDisplayChannels
    currentLabel = displayLabels(k);
    sourceIndex = find(strcmp(labelsFromEEG(EEG), currentLabel), 1);
    if isempty(sourceIndex)
        error('displayLabels 中的通道不存在：%s', currentLabel);
    end

    % EOG、EMG 和普通 EEG 分别读取各自的连续滤波副本。
    if ismember(sourceIndex, find(strcmp(labelsFromEEG(EEG), "R-HEOG") | ...
            strcmp(labelsFromEEG(EEG), "L-VEOG")))
        displayData(k, :) = EEG_eogDisplay.data(sourceIndex, :, 1);
    elseif ismember(sourceIndex, find(strcmp(labelsFromEEG(EEG), "EMG") | ...
            strcmp(labelsFromEEG(EEG), "26") | strcmp(labelsFromEEG(EEG), "27")))
        displayData(k, :) = EEG_emgDisplay.data(sourceIndex, :, 1);
    else
        displayData(k, :) = EEG_eegDisplay.data(sourceIndex, :, 1);
    end
    displayChanlocs(k) = EEG.chanlocs(sourceIndex);
end

displayTime = (0:size(displayData, 2)-1) / displayRate;
durationSeconds = EEG.pnts / EEG.srate;
displayEvents = EEG_eegDisplay.event;

% 事件类别的颜色和线型：数学题 1–20 统一归为一类。
categoryNames = ["数学题（1-20）", "TLR 光提示", "TLR 声音提示", ...
    "新脚本开始", "音量降低", "音量升高", "其他事件"];
categoryColors = [ ...
    0.15 0.45 0.85; ... % 数学题
    0.10 0.60 0.20; ... % TLR 光提示
    0.95 0.50 0.10; ... % TLR 声音提示
    0.85 0.10 0.10; ... % 新脚本开始
    0.55 0.20 0.75; ... % 音量降低
    0.00 0.60 0.60; ... % 音量升高
    0.40 0.40 0.40];    % 其他事件
categoryStyles = {'-', '--', '-.', ':', '--', '-.', '-'};

%% 6. 打开 EEGLAB eegplot：用于对比
% eegplot 的 60 秒只是初始窗口，不是数据长度；这里仍可滚动完整记录。
eegplot(displayData, 'srate', displayRate, 'winlength', 60, ...
    'eloc_file', displayChanlocs, 'events', displayEvents, ...
    'color', displayColors, 'xgrid', 'on', 'ygrid', 'on', ...
    'title', [caseName, ' | EEGLAB eegplot | 初始窗口 60 s'], ...
    'command', '');

%% 7. 用 MATLAB 原生单坐标轴绘制完整记录、事件和图例
% 与 eegplot 的窗口式显示不同，这里把五个选定通道堆叠在同一个坐标轴中。
% 每条波形使用不同颜色；所有事件也在同一坐标轴上标出。
% 这张图初始显示完整记录，不会因为事件而切 epoch。
nativeFig = figure('Name', [caseName, ' | MATLAB native single axes'], ...
    'Color', 'w', 'Position', [70 50 1600 900]);
nativeAxes = axes(nativeFig);
hold(nativeAxes, 'on');

% 每个通道单独标准化后加垂直偏移，既保留波形形状，又避免不同单位粘在一起。
% 标准化只用于显示；不会修改 EEG 数据，也不会用于正式数值分析。
nPlotChannels = size(displayData, 1);
normalizedData = zeros(size(displayData));
for k = 1:nPlotChannels
    channelData = double(displayData(k, :));
    channelData = channelData - median(channelData);
    channelScale = std(channelData);
    if channelScale == 0 || ~isfinite(channelScale)
        channelScale = 1;
    end
    normalizedData(k, :) = channelData / channelScale;
end

offsets = (nPlotChannels:-1:1) * 6;
signalY = normalizedData + offsets(:);
for k = 1:nPlotChannels
    plot(nativeAxes, displayTime, signalY(k, :), ...
        'Color', displayColors{k}, 'LineWidth', 0.6, ...
        'HandleVisibility', 'off');
end

% 所有事件按类别使用稳定的颜色和线型；数学题 1–20 共用一个类别样式。
% 这里仅要求事件具有有效时间，不要求 NumericCode 一定是数字，
% 这样即使以后遇到文字型 EDF 事件，也不会被漏画。
finiteEventMask = isfinite(eventTable.TimeSeconds);
validRows = find(finiteEventMask);
for k = validRows'
    categoryIndex = find(categoryNames == eventTable.EventCategory(k), 1);
    eventLine = xline(nativeAxes, eventTable.TimeSeconds(k));
    eventLine.Color = categoryColors(categoryIndex, :);
    eventLine.LineStyle = categoryStyles{categoryIndex};
    eventLine.LineWidth = 1.0;
    eventLine.HandleVisibility = 'off';
end

% 为图例建立每个类别一个示例线；图例不会为 1–20 的每个数学题单独列项。
legendHandles = gobjects(numel(categoryNames), 1);
for k = 1:numel(categoryNames)
    legendHandles(k) = plot(nativeAxes, nan, nan, ...
        'Color', categoryColors(k, :), ...
        'LineStyle', categoryStyles{k}, 'LineWidth', 1.5);
end
legend(nativeAxes, legendHandles, cellstr(categoryNames), ...
    'Location', 'eastoutside');

% 在同一张图上标出每一个事件的代码和含义；密集事件放大后可逐个阅读。
finiteSignalValues = signalY(isfinite(signalY));
signalMin = min(finiteSignalValues);
signalMax = max(finiteSignalValues);
labelBase = signalMax + 3;
labelSpacing = 5;
for k = 1:numel(validRows)
    row = validRows(k);
    categoryIndex = find(categoryNames == eventTable.EventCategory(row), 1);
    labelY = labelBase + mod(k-1, 4) * labelSpacing;
    text(nativeAxes, eventTable.TimeSeconds(row), labelY, ...
        char(eventTable.EventLabel(row)), ...
        'Rotation', 90, 'VerticalAlignment', 'bottom', ...
        'HorizontalAlignment', 'left', 'FontSize', 8, ...
        'Color', categoryColors(categoryIndex, :), ...
        'Interpreter', 'none');
end

% 根据所有实际波形数据计算纵轴范围，给出边距，避免大幅波形被截断。
% 如果存在很大的生理/运动伪迹，它会占据较大范围，但不会被人为裁掉。
yLower = min(signalMin, 0) - 2;
yUpper = labelBase + 4 * labelSpacing + 5;
ylim(nativeAxes, [yLower, yUpper]);
xlim(nativeAxes, [0, durationSeconds]);
grid(nativeAxes, 'on');
yticks(nativeAxes, sort(offsets));
yticklabels(nativeAxes, cellstr(flipud(displayLabels(:))));
xlabel(nativeAxes, '记录时间 (s)');
ylabel(nativeAxes, '显示波形（通道内标准化并错开）');
title(nativeAxes, ...
    'MATLAB 原生单坐标轴：五条波形 + 全部事件 + 类别图例');

% MATLAB 图窗的工具栏可以切换 Zoom、Pan、Data Cursor。
zoom(nativeFig, 'on');
datacursormode(nativeFig, 'on');

% 保存 .fig 后，之后双击打开仍可继续缩放；PNG 是静态报告图。
nativeFigureFile = fullfile(figureDir, ...
    [caseName, '_s05_matlab_native.fig']);
nativePngFile = fullfile(figureDir, ...
    [caseName, '_s05_matlab_native.png']);
savefig(nativeFig, nativeFigureFile);
exportgraphics(nativeFig, nativePngFile, 'Resolution', 150);

%% 8. 额外绘制“第一条事件到记录结束”的详细连续波形图
% 完整统一图仍然保留。这里再生成一张从事件表第一条事件开始、
% 一直画到 EEG 采集结束的连续波形图；这不是 EEGLAB epoch，
% 也不会修改原始数据。
% 注意：case07 的第一条事件是 code 5，发生在 0.000 秒，
% 因此本图实际覆盖整段 0–815.999 秒记录。
detailStartRow = validRows(1);
detailStartTime = eventTable.TimeSeconds(detailStartRow);
detailStartLabel = eventTable.EventLabel(detailStartRow);

% 取显示采样率下最接近起始事件的样本；相对时间从这个样本开始计时。
detailStartSample = max(1, min(size(signalY, 2), ...
    round(detailStartTime * displayRate) + 1));
detailSamples = detailStartSample:size(signalY, 2);
detailAxisStartTime = displayTime(detailStartSample);
detailTime = displayTime(detailSamples) - detailAxisStartTime;
detailSignalY = signalY(:, detailSamples);

detailEventRows = validRows(eventTable.TimeSeconds(validRows) >= detailAxisStartTime);

detailFig = figure('Name', [caseName, ' | first-event-to-end detail'], ...
    'Color', 'w', 'Position', [80 50 1600 900]);
detailAxes = axes(detailFig);
hold(detailAxes, 'on');

% 使用完整图相同的偏移和标准化尺度，便于在两张图之间对照。
for k = 1:nPlotChannels
    plot(detailAxes, detailTime, detailSignalY(k, :), ...
        'Color', displayColors{k}, 'LineWidth', 0.8, ...
        'HandleVisibility', 'off');
end

for k = detailEventRows'
    categoryIndex = find(categoryNames == eventTable.EventCategory(k), 1);
    relativeEventTime = eventTable.TimeSeconds(k) - detailAxisStartTime;
    detailEventLine = xline(detailAxes, relativeEventTime);
    detailEventLine.Color = categoryColors(categoryIndex, :);
    detailEventLine.LineStyle = categoryStyles{categoryIndex};
    detailEventLine.LineWidth = 1.2;
    detailEventLine.HandleVisibility = 'off';
end

% 详细图也保留完整类别图例。
detailLegendHandles = gobjects(numel(categoryNames), 1);
for k = 1:numel(categoryNames)
    detailLegendHandles(k) = plot(detailAxes, nan, nan, ...
        'Color', categoryColors(k, :), ...
        'LineStyle', categoryStyles{k}, 'LineWidth', 1.5);
end
legend(detailAxes, detailLegendHandles, cellstr(categoryNames), ...
    'Location', 'eastoutside');

% 把详细片段中每一个事件的代码和含义写在同一坐标轴上。
detailSignalValues = detailSignalY(isfinite(detailSignalY));
detailSignalMax = max(detailSignalValues);
detailSignalMin = min(detailSignalValues);
detailLabelBase = detailSignalMax + 3;
for k = 1:numel(detailEventRows)
    row = detailEventRows(k);
    categoryIndex = find(categoryNames == eventTable.EventCategory(row), 1);
    labelY = detailLabelBase + mod(k-1, 4) * labelSpacing;
    text(detailAxes, eventTable.TimeSeconds(row) - detailAxisStartTime, ...
        labelY, char(eventTable.EventLabel(row)), 'Rotation', 90, ...
        'VerticalAlignment', 'bottom', 'HorizontalAlignment', 'left', ...
        'FontSize', 8, 'Color', categoryColors(categoryIndex, :), ...
        'Interpreter', 'none');
end

detailYLower = min(detailSignalMin, 0) - 2;
detailYUpper = detailLabelBase + 4 * labelSpacing + 5;
ylim(detailAxes, [detailYLower, detailYUpper]);
xlim(detailAxes, [0, detailTime(end)]);
grid(detailAxes, 'on');
yticks(detailAxes, sort(offsets));
yticklabels(detailAxes, cellstr(flipud(displayLabels(:))));
xlabel(detailAxes, '从起始事件开始的相对时间 (s)');
ylabel(detailAxes, '显示波形（通道内标准化并错开）');
title(detailAxes, sprintf(...
    '第一条事件到记录结束：%s；原始时间 %.3f s', ...
    char(detailStartLabel), detailStartTime));

zoom(detailFig, 'on');
datacursormode(detailFig, 'on');

detailFigureFile = fullfile(figureDir, ...
    [caseName, '_s05_first_event_to_end.fig']);
detailPngFile = fullfile(figureDir, ...
    [caseName, '_s05_first_event_to_end.png']);
savefig(detailFig, detailFigureFile);
exportgraphics(detailFig, detailPngFile, 'Resolution', 150);

%% 9. 输出说明
fprintf('\n===== s05 MATLAB 原生绘图对比完成 =====\n');
fprintf('完整记录：%.1f 秒；采样率：%.1f Hz；显示采样率：%.1f Hz。\n', ...
    durationSeconds, EEG.srate, displayRate);
fprintf('显示通道：%s\n', strjoin(cellstr(displayLabels), ', '));
fprintf('EEGLAB 图：初始显示 60 秒，可滚动完整记录。\n');
fprintf('MATLAB 图：初始显示完整 %.1f 秒，可使用 Zoom/Pan。\n', ...
    durationSeconds);
fprintf('事件表：%s\n', eventFile);
fprintf('MATLAB 可缩放 FIG：%s\n', nativeFigureFile);
fprintf('MATLAB 静态 PNG：%s\n', nativePngFile);
fprintf('事件类别：数学题 1-20 归为同一类，其余类别分别显示。\n');
fprintf('详细图起始：第一条事件（%s），原始时间 %.3f s。\n', ...
    char(detailStartLabel), detailStartTime);
fprintf('第一条事件到记录结束的 FIG：%s\n', detailFigureFile);
fprintf('第一条事件到记录结束的 PNG：%s\n', detailPngFile);

%% 本脚本使用的局部函数
function labelArray = labelsFromEEG(EEG)
% 返回 EEG 通道标签的 string 列向量，避免反复处理 cell 标签。
labelArray = string({EEG.chanlocs.labels})';
end

function category = eventCategoryFromCode(code)
% 将事件代码归并为用于颜色和图例的事件类别。
% 数学题代码 1–20 统一作为一个类别，而不是生成 20 个图例项目。
if ~isfinite(code)
    category = "其他事件";
elseif code >= 1 && code <= 20
    category = "数学题（1-20）";
elseif code == 23
    category = "TLR 光提示";
elseif code == 29
    category = "TLR 声音提示";
elseif code == 32
    category = "新脚本开始";
elseif code == 64
    category = "音量降低";
elseif code == 65
    category = "音量升高";
else
    category = "其他事件";
end
end
