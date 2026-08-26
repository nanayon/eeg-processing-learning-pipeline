%% s04_eeglab_case07_full_overview
% TWC_USA：查看 case07_sub106 的完整 EDF 记录
%
% 本脚本的目的不是围绕某一个 code 32 截取 epoch，而是回答：
% 1. 这个 EDF 文件有多长、多少通道、多少事件？
% 2. 全部事件分别发生在什么时间、代码含义是什么？
% 3. 整个记录中的 EOG/EMG 波形如何变化？
%
% 所有原始事件都会保留并显示。

clear;
clc;

%% 1. 设置工程目录并初始化 EEGLAB
projectDir = fileparts(fileparts(mfilename('fullpath')));
rawDir = fullfile(projectDir, 'raw', 'TWC_USA', 'Data', 'PSG');
resultDir = fullfile(projectDir, 'results');
figureDir = fullfile(projectDir, 'figures');
codeDir = fileparts(mfilename('fullpath'));

% 让脚本可以调用项目中的事件含义映射函数。
addpath(codeDir);

if ~exist(resultDir, 'dir')
    mkdir(resultDir);
end
if ~exist(figureDir, 'dir')
    mkdir(figureDir);
end

% 加载本机安装的 EEGLAB；EDF 导入和连续滤波均使用 EEGLAB 函数。
eeglabRoot = 'E:\Application\Matlab\toolbox\eeglab2026.0.0';
addpath(eeglabRoot);
eeglab('nogui');

%% 2. 使用 EEGLAB/BioSig 导入完整 EDF
caseName = 'case07_sub106';
edfFile = fullfile(rawDir, [caseName, '.edf']);

if ~exist(edfFile, 'file')
    error('找不到 EDF 文件：%s', edfFile);
end

% blockepoch='off'：保持整段记录为连续数据；
% rmeventchan：把 Status 通道中的事件提取为 EEG.event。
EEG = pop_biosig(edfFile, 'importevent', 'on', ...
    'importannot', 'on', 'blockepoch', 'off', 'rmeventchan', 'on');
EEG = eeg_checkset(EEG);

%% 3. 统一全部事件代码，并建立完整事件表
% BioSig 可能把整数事件读成 31.9996、64.0002 等浮点数。
% 这里只做四舍五入和可读标签，不删除事件，也不选择某一个 code 32。
nEvents = numel(EEG.event);
eventIndex = (1:nEvents)';
eventLabel = strings(nEvents, 1);
numericCode = nan(nEvents, 1);
eventLatency = nan(nEvents, 1);
eventTimeSeconds = nan(nEvents, 1);
eventMeaning = strings(nEvents, 1);

for k = 1:nEvents
    rawType = char(string(EEG.event(k).type));
    numericType = str2double(rawType);
    eventLatency(k) = EEG.event(k).latency;
    eventTimeSeconds(k) = (eventLatency(k) - 1) / EEG.srate;

    if isfinite(numericType)
        code = round(numericType);
        numericCode(k) = code;
        meaning = twcUSA_event_meaning(code, 7);
        eventMeaning(k) = meaning;
        eventLabel(k) = string(code) + ": " + meaning;

        % 让 EEGLAB 的 eegplot 直接显示“代码：含义”。
        EEG.event(k).type = char(eventLabel(k));
    else
        eventMeaning(k) = "非数字事件代码";
        eventLabel(k) = string(rawType);
    end
end

EEG = eeg_checkset(EEG);

eventTable = table(eventIndex, eventLabel, numericCode, eventLatency, ...
    eventTimeSeconds, eventMeaning, ...
    'VariableNames', {'EventIndex','EventLabel','NumericCode', ...
    'LatencySamples','TimeSeconds','EventMeaning'});

eventFile = fullfile(resultDir, [caseName, '_s04_all_events.csv']);
writetable(eventTable, eventFile);

%% 4. 建立完整通道信息表
labels = string({EEG.chanlocs.labels})';
channelIndex = (1:EEG.nbchan)';
channelGroup = repmat("Other", EEG.nbchan, 1);

eegLabels = { ...
    'Fpz','Fz','Cz','Pz','Oz','Fp1','Fp2','F3','F4', ...
    'C3','C4','P3','P4','O1','O2','F7','F8','T3','T4','T5','T6'};
eegIdx = find(ismember(cellstr(labels), eegLabels));
eogIdx = find(ismember(cellstr(labels), {'R-HEOG','L-VEOG'}));
emgIdx = find(ismember(cellstr(labels), {'EMG','26','27'}));

channelGroup(eegIdx) = "EEG";
channelGroup(eogIdx) = "EOG";
channelGroup(emgIdx) = "EMG";

channelTable = table(channelIndex, labels, channelGroup, ...
    'VariableNames', {'ChannelIndex','Label','SignalGroup'});
channelFile = fullfile(resultDir, [caseName, '_s04_channels.csv']);
writetable(channelTable, channelFile);

%% 5. 在命令窗口输出完整文件信息
durationSeconds = EEG.pnts / EEG.srate;

fprintf('\n===== case 完整文件概览 =====\n');
fprintf('文件：%s\n', edfFile);
fprintf('案例：%s\n', caseName);
fprintf('通道数：%d\n', EEG.nbchan);
fprintf('采样率：%.1f Hz\n', EEG.srate);
fprintf('采样点数：%d\n', EEG.pnts);
fprintf('记录时长：%.3f 秒（%.2f 分钟）\n', ...
    durationSeconds, durationSeconds / 60);
fprintf('事件总数：%d\n', nEvents);
fprintf('EEG 通道：%s\n', strjoin(cellstr(labels(eegIdx)), ', '));
fprintf('EOG 通道：%s\n', strjoin(cellstr(labels(eogIdx)), ', '));
fprintf('EMG 通道：%s\n', strjoin(cellstr(labels(emgIdx)), ', '));

fprintf('\n----- 全部事件（没有筛选 code 32）-----\n');
disp(eventTable);

fprintf('\n----- code 32 的全部出现位置 -----\n');
disp(eventTable(eventTable.NumericCode == 32, :));

%% 6. 对连续记录建立不同信号的显示副本
% 这是为了让全程波形更容易观察；仍然先对完整连续数据滤波，
% 此处没有切 epoch，因此不存在“短 epoch 边缘滤波”的问题。
EEG_eegContinuous = pop_eegfiltnew(EEG, 0.5, 35);
EEG_eogContinuous = pop_eegfiltnew(EEG, 0.1, 15);
EEG_emgContinuous = pop_eegfiltnew(EEG, 10, 100);

% 仅为交互式显示降低采样率，不改变原始 EDF，也不用于正式特征计算。
% EOG 最高约 15 Hz，EMG 最高约 100 Hz；250 Hz 采样率足够用于显示。
displayRate = 250;
EEG_eegDisplay = pop_resample(EEG_eegContinuous, displayRate);
EEG_eogDisplay = pop_resample(EEG_eogContinuous, displayRate);
EEG_emgDisplay = pop_resample(EEG_emgContinuous, displayRate);

%% 7. 手动选择要显示的通道，并打开完整连续记录窗口
% 这里就是“手动选择显示哪个”的位置。顺序就是图中从上到下的顺序。
% 当前默认设置把两个 EOG 放在五条线的中间。
displayLabels = ["EMG", "R-HEOG", "L-VEOG", "26", "27"];

% 交互窗口第一次打开时显示多少秒；这不是数据长度。
% 整个记录仍然是 816 秒，可以用 <<、<、>、>> 滚动时间。
initialWindowSeconds = 60;

baseColors = {'k','b','r','m','g','c','y'};
displayColors = baseColors(1 + mod(0:numel(displayLabels)-1, ...
    numel(baseColors)));

nDisplayChannels = numel(displayLabels);
displayData = zeros(nDisplayChannels, EEG_eegDisplay.pnts);
displayChanlocs = EEG.chanlocs([]);

for k = 1:nDisplayChannels
    currentLabel = displayLabels(k);
    sourceIndex = find(labels == currentLabel, 1);
    if isempty(sourceIndex)
        error('displayLabels 中的通道不存在：%s', currentLabel);
    end

    % 根据通道类型，从对应的连续滤波副本读取数据。
    if ismember(sourceIndex, eogIdx)
        displayData(k, :) = EEG_eogDisplay.data(sourceIndex, :, 1);
    elseif ismember(sourceIndex, emgIdx)
        displayData(k, :) = EEG_emgDisplay.data(sourceIndex, :, 1);
    else
        displayData(k, :) = EEG_eegDisplay.data(sourceIndex, :, 1);
    end
    displayChanlocs(k) = EEG.chanlocs(sourceIndex);
end

% 三个显示副本的事件均已同步重采样；这里保留全部事件。
displayEvents = EEG_eegDisplay.event;

% eegplot 的 Settings 菜单中可以：
% - Settings > Time range to display：修改显示时间窗口；
% - Settings > Zoom on/off：框选放大或缩小时间/通道轴；
% - 右侧 +/-：调整振幅间距；
% - <<、<、>、>>：浏览完整 816 秒记录。
eegplot(displayData, 'srate', displayRate, ...
    'winlength', initialWindowSeconds, ...
    'eloc_file', displayChanlocs, 'events', displayEvents, ...
    'color', displayColors, 'xgrid', 'on', 'ygrid', 'on', ...
    'title', [caseName, ' | 手动选择通道 | 全程连续记录'], ...
    'command', '');

%% 8. 生成一张完整时间线摘要图
% 这张静态图只用于报告和快速浏览。每条信号先做通道内标准化，
% 因此纵轴主要表达波形变化，不用于比较不同信号的绝对幅值。
displayTime = (0:size(displayData, 2)-1) / displayRate;
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

figureHandle = figure('Name', [caseName, ' full overview'], ...
    'Color', 'w', 'Visible', 'off', 'Position', [100 100 1600 900]);

subplot(2, 1, 1);
hold on;
offsets = (nPlotChannels:-1:1) * 5;
for k = 1:nPlotChannels
    plot(displayTime, normalizedData(k, :) + offsets(k), ...
        'Color', displayColors{k}, 'LineWidth', 0.5);
end

% 画出全部事件；code 32 使用红色虚线，但不只画最后一个 code 32。
finiteEventMask = isfinite(eventTable.TimeSeconds);
for k = find(finiteEventMask)'
    if eventTable.NumericCode(k) == 32
        xline(eventTable.TimeSeconds(k), 'r--', 'LineWidth', 1.2);
    else
        xline(eventTable.TimeSeconds(k), ':', 'Color', [0.65 0.65 0.65]);
    end
end

% MATLAB 要求 yticks 从小到大排列；因此标签也同步反转。
tickPositions = sort(offsets);
displayChannelLabels = string({displayChanlocs.labels})';
yticks(tickPositions);
yticklabels(cellstr(flipud(displayChannelLabels)));
xlim([0 durationSeconds]);
grid on;
xlabel('记录时间 (s)');
ylabel('通道（通道内标准化）');
title('全程连续记录概览：通道可手动选择，全部事件均保留');

subplot(2, 1, 2);
finiteCodeMask = isfinite(eventTable.TimeSeconds) & ...
    isfinite(eventTable.NumericCode);
stem(eventTable.TimeSeconds(finiteCodeMask), ...
    eventTable.NumericCode(finiteCodeMask), 'filled', 'MarkerSize', 4);
xlim([0 durationSeconds]);
grid on;
xlabel('记录时间 (s)');
ylabel('事件代码');
title('完整事件时间线：每个点对应一个 EEG.event');

sgtitle([caseName, ' | 完整 EDF 概览（不选择单个 code 32）']);

overviewFigureFile = fullfile(figureDir, ...
    [caseName, '_s04_full_overview.png']);
exportgraphics(figureHandle, overviewFigureFile, 'Resolution', 150);
close(figureHandle);

%% 9. 输出结果文件位置
fprintf('\n===== s04 完整概览完成 =====\n');
fprintf('完整事件表：%s\n', eventFile);
fprintf('完整通道表：%s\n', channelFile);
fprintf('完整时间线图：%s\n', overviewFigureFile);
fprintf('已打开：手动选择通道的全程连续窗口。\n');
fprintf('初始显示窗口：%.0f 秒；完整记录长度：%.1f 秒。\n', ...
    initialWindowSeconds, durationSeconds);
