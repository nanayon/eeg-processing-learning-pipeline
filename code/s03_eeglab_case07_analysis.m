%% s03_eeglab_case07_analysis
% TWC_USA 清醒梦数据：case07 的第一个正式 EEGLAB 分析
%
% 研究目的：
% 1. 以“新脚本开始”(Status code 32) 为时间参考，截取事件前后 EEG/EOG/EMG。
% 2. 在 EOG 中计算候选眼动活动，而不是把单个高峰直接当作回应。
% 3. 用 EEGLAB 的频谱函数比较 EEG 事件前后频带活动。
% 4. 用 EMG 振幅检查是否存在明显肌肉活动或觉醒迹象。
%
% 重要说明：
% 报告中的“做过几次眼动回应”不是 EDF 内置的逐采样标签。
% 因此本脚本输出的是“候选眼动活动”和可复核的特征，不能自动宣称每个高峰
% 都是一次 LR/LRLR 回应。最终眼动编码仍需结合 EOG 图形和实验说明确认。

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

% 加载本机安装的 EEGLAB。正式信号导入和处理均使用 EEGLAB 函数。
eeglabRoot = 'E:\Application\Matlab\toolbox\eeglab2026.0.0';
addpath(eeglabRoot);
eeglab('nogui');

%% 2. 用 EEGLAB/BioSig 导入 EDF
caseName = 'case07_sub106';
edfFile = fullfile(rawDir, [caseName, '.edf']);

if ~exist(edfFile, 'file')
    error('找不到 EDF 文件：%s', edfFile);
end

% importevent/importannot：导入事件；blockepoch='off'：保持整段连续记录；
% rmeventchan：把 Status 通道提取为 EEG.event 后从连续通道中移除。
EEG = pop_biosig(edfFile, 'importevent', 'on', ...
    'importannot', 'on', 'blockepoch', 'off', 'rmeventchan', 'on');
EEG = eeg_checkset(EEG);

%% 3. 统一事件代码格式
% BioSig 有时会把整数事件读成 4.9998、31.9996 等浮点数。
% 这里把它们四舍五入为字符串事件类型，便于 EEGLAB 的 pop_epoch 使用。
for k = 1:numel(EEG.event)
    rawType = char(string(EEG.event(k).type));
    numericType = str2double(rawType);
    if isfinite(numericType)
        EEG.event(k).type = num2str(round(numericType));
    end
end
EEG = eeg_checkset(EEG);

%% 4. 识别 EEG、EOG、EMG 通道
labels = {EEG.chanlocs.labels};

% TWC_USA 的 21 个头皮 EEG 通道。
eegLabels = {'Fpz','Fz','Cz','Pz','Oz','Fp1','Fp2','F3','F4', ...
    'C3','C4','P3','P4','O1','O2','F7','F8','T3','T4','T5','T6'};
eegIdx = find(ismember(labels, eegLabels));

% R-HEOG 是水平眼电；L-VEOG 是垂直眼电。
eogIdx = find(ismember(labels, {'R-HEOG','L-VEOG'}));

% EMG 可能以 EMG、26、27 中的一个或多个标签存在。
emgIdx = find(ismember(labels, {'EMG','26','27'}));

if isempty(eegIdx) || isempty(eogIdx) || isempty(emgIdx)
    error('EEG/EOG/EMG 通道识别失败，请检查通道标签。');
end

horizontalEogIdx = find(strcmp(labels, 'R-HEOG'), 1);
verticalEogIdx = find(strcmp(labels, 'L-VEOG'), 1);
czIdx = find(strcmp(labels, 'Cz'), 1);

%% 5. 确定参考事件，但暂不分段
% Code 32 表示新脚本开始。case07 有多个 code 32；这里选择最后一个，
% 因为它位于最终实验片段附近，可观察后续数学题和眼动活动。
referenceEvent = {'32'};
epochWindow = [-10, 10];     % 单位：秒，事件前 10 秒到事件后 10 秒

code32Idx = find(strcmp({EEG.event.type}, '32'));
if isempty(code32Idx)
    error('当前记录没有找到 code 32 事件，无法进行示范分段。');
end

% 只保留最后一个 code 32 作为分段参考，避免前后事件重叠或超出记录边界。
[~, latestPosition] = max([EEG.event(code32Idx).latency]);
targetCode32Idx = code32Idx(latestPosition);
for k = 1:numel(code32Idx)
    if code32Idx(k) ~= targetCode32Idx
        EEG.event(code32Idx(k)).type = '32_non_target';
    end
end
EEG = eeg_checkset(EEG);

%% 6. 先在连续记录上滤波，再用同一个事件分段
% 这是正式 EEG 分析中更稳妥的顺序：
% 连续 EDF -> 连续滤波 -> 事件分段。
% 如果先把只有 20 秒的短 epoch 切出来再滤波，滤波器在 epoch 左右边界
% 的起始/结束瞬态更容易污染边缘样本。
%
% 三类信号需要不同频带，因此分别建立三个连续数据副本。
% 注意：EEGLAB 的 pop_eegfiltnew 会对数据集中的通道执行滤波；后面只从
% 对应副本中读取 EEG、EOG 或 EMG 通道。
EEG_eegContinuous = pop_eegfiltnew(EEG, 0.5, 35);
EEG_eogContinuous = pop_eegfiltnew(EEG, 0.1, 15);
EEG_emgContinuous = pop_eegfiltnew(EEG, 10, 100);

% 滤波完成后，才以最后一个 code 32 为参考事件分段。
EEG_eeg = pop_epoch(EEG_eegContinuous, referenceEvent, epochWindow, ...
    'epochinfo', 'yes');
EEG_eog = pop_epoch(EEG_eogContinuous, referenceEvent, epochWindow, ...
    'epochinfo', 'yes');
EEG_emg = pop_epoch(EEG_emgContinuous, referenceEvent, epochWindow, ...
    'epochinfo', 'yes');

EEG_eeg = eeg_checkset(EEG_eeg);
EEG_eog = eeg_checkset(EEG_eog);
EEG_emg = eeg_checkset(EEG_emg);

% 以 EEG 频带版本作为主分段数据集保存；EOG/EMG 的特征分别来自各自的
% 滤波副本。这样保存的 .set 可以在 EEGLAB 中重新打开并检查事件。
EEG_epoch = EEG_eeg;

% 给分段后的事件加上可读含义，便于 eegplot 图形直接解释。
% 例如：65: 音量升高，而不是只显示数字 65。
for k = 1:numel(EEG_epoch.event)
    rawType = char(string(EEG_epoch.event(k).type));
    numericToken = regexp(rawType, '^-?\d+(\.\d+)?', 'match', 'once');
    if ~isempty(numericToken)
        code = round(str2double(numericToken));
        meaning = twcUSA_event_meaning(code, 7);
        suffix = "";
        if contains(rawType, 'non_target')
            suffix = "（非目标参考事件）";
        end
        EEG_epoch.event(k).type = char(string(code) + ": " + ...
            meaning + suffix);
    end
end

% 保存一个可在 EEGLAB 中重新打开的、已经按正确顺序处理的事件分段数据集。
EEG_epoch.setname = [caseName, '_event32_epoch'];
EEG_epoch = pop_saveset(EEG_epoch, ...
    'filename', [caseName, '_event32_epoch.set'], ...
    'filepath', resultDir);

%% 7. 计算 EOG 候选眼动活动
% 这里使用水平 EOG 作为主要眼动指标。
% 只有一个 R-HEOG 通道时，可以测量变化强度和时间，但不能仅凭该通道
% 可靠判断“向左”还是“向右”；方向需要结合电极参考和波形极性确认。
eogHorizontal = double(EEG_eog.data(horizontalEogIdx, :, 1));
eogVertical = double(EEG_eog.data(verticalEogIdx, :, 1));

% EEGLAB 在只有一个 epoch 时可能把 EEG_epoch.times 重置为 0 开始。
% 因此根据原始分段窗口重新建立“相对参考事件”的时间轴，
% 参考事件位于 0 秒，而不是把第一个采样点误当成事件时刻。
timeSec = epochWindow(1) + (0:EEG_epoch.pnts-1) / EEG_epoch.srate;
% EOG/EMG 仍使用事件前 5 秒和事件后 10 秒观察活动。
preMask = timeSec >= -10 & timeSec < -5;
postMask = timeSec >= 0 & timeSec < 10;

% PSD 专门使用等长窗口，保证前后频谱估计具有可比性。
psdPreWindow = [-10, -5];
psdPostWindow = [0, 5];
prePsdMask = timeSec >= psdPreWindow(1) & timeSec < psdPreWindow(2);
postPsdMask = timeSec >= psdPostWindow(1) & timeSec < psdPostWindow(2);

% 用事件前基线的标准差建立候选活动阈值。
eogBaseline = eogHorizontal(preMask);
eogBaseline = eogBaseline - mean(eogBaseline);
eogThreshold = 3 * std(eogBaseline);
eogCentered = eogHorizontal - mean(eogHorizontal(preMask));

% 统计事件前后峰峰值；这反映波动强度，不等于回应次数。
eogPrePeakToPeak = max(eogCentered(preMask)) - min(eogCentered(preMask));
eogPostPeakToPeak = max(eogCentered(postMask)) - min(eogCentered(postMask));

% 统计超过阈值的连续候选活动段数量。
candidateMask = abs(eogCentered) > eogThreshold;
candidateStarts = find(diff([false, candidateMask]) == 1);
candidateEnds = find(diff([candidateMask, false]) == -1);
candidateCount = numel(candidateStarts);

%% 8. 计算 EMG 活动
% 对多个 EMG 通道先求均方根，得到该窗口内的肌肉活动强度。
emgData = double(EEG_emg.data(emgIdx, :, 1));
emgRms = sqrt(mean(emgData .^ 2, 1));
emgPreRms = mean(emgRms(preMask));
emgPostRms = mean(emgRms(postMask));

%% 9. 使用 EEGLAB spectopo 计算 Cz 的 EEG 频谱
% 前后 PSD 窗口均为 5 秒：PRE=-10~-5，POST=0~+5。
% spectopo 输出 dB 形式的功率谱密度，不直接把 dB 平均值当成 band power。
czSignal = double(EEG_eeg.data(czIdx, :, 1));

[spectrumPre, frequencies] = spectopo(czSignal(prePsdMask), ...
    numel(czSignal(prePsdMask)), EEG_eeg.srate, ...
    'plot', 'off');
[spectrumPost, frequenciesPost] = spectopo(czSignal(postPsdMask), ...
    numel(czSignal(postPsdMask)), EEG_eeg.srate, ...
    'plot', 'off');

if ~isequal(frequencies, frequenciesPost)
    error('事件前后频谱频率轴不一致。');
end

bandNames = {'delta','theta','alpha','sigma','beta'}';
bandLimits = [1 4; 4 8; 8 13; 12 16; 13 30];
preBandPower = nan(size(bandNames));
postBandPower = nan(size(bandNames));
preMeanPsdDb = nan(size(bandNames));
postMeanPsdDb = nan(size(bandNames));

% dB PSD -> 线性 PSD：dB=10*log10(linear)，所以 linear=10^(dB/10)。
linearSpectrumPre = 10 .^ (spectrumPre / 10);
linearSpectrumPost = 10 .^ (spectrumPost / 10);

for b = 1:numel(bandNames)
    bandMask = frequencies >= bandLimits(b,1) & frequencies < bandLimits(b,2);

    % 对频率范围内的线性 PSD 积分，得到标准 band power。
    preBandPower(b) = trapz(frequencies(bandMask), ...
        linearSpectrumPre(bandMask));
    postBandPower(b) = trapz(frequencies(bandMask), ...
        linearSpectrumPost(bandMask));

    % 另外保留平均 dB，明确标记为平均 log-PSD，而不是 band power。
    preMeanPsdDb(b) = mean(spectrumPre(bandMask));
    postMeanPsdDb(b) = mean(spectrumPost(bandMask));
end

%% 10. 用 EEGLAB eegplot 保存 EOG/EMG 交互式检查图
% 这张图是后续人工确认眼动模式的依据。
% 这里必须使用各自已经“连续滤波后再分段”的副本，不能重新从
% EEG_epoch（0.5–35 Hz 的 EEG 版本）中取 EOG/EMG，否则会把信号频带弄混。
% 显示顺序特意安排为：EMG、R-HEOG、L-VEOG、其余 EMG。
% 这样两个眼电通道位于五条线的中间，观察眼动时不容易被挤在顶部。
firstEmgIdx = emgIdx(1);
remainingEmgIdx = emgIdx(2:end);
plotData = [EEG_emg.data(firstEmgIdx, :, 1); ...
    EEG_eog.data(eogIdx, :, 1); ...
    EEG_emg.data(remainingEmgIdx, :, 1)];
eogChanlocs =      EEG_eog.chanlocs(eogIdx);
firstEmgChanloc = EEG_emg.chanlocs(firstEmgIdx);
remainingEmgChanlocs = EEG_emg.chanlocs(remainingEmgIdx);
% find 的结果在不同情况下可能是行向量或列向量，先统一成行向量再拼接。
plotChanlocs = [firstEmgChanloc(:).', eogChanlocs(:).', ...
    remainingEmgChanlocs(:).'];
plotEvents = EEG_epoch.event;

eegplot(plotData, 'srate', EEG_epoch.srate, ...
    'winlength', 30, 'eloc_file', plotChanlocs, 'events', plotEvents, ...
    'color', {'k','b','r','m','g'}, 'command', '');
drawnow;

% 同时输出一张静态摘要图，方便写报告和复核。
referenceMeaning = twcUSA_event_meaning(32, 7);
summaryFig = figure('Name', [caseName, ' EEGLAB analysis summary'], ...
    'Color', 'w', 'Visible', 'off');

subplot(3,1,1);
plot(timeSec, eogCentered, 'b');
hold on;
yline(eogThreshold, 'r--', '阈值');
yline(-eogThreshold, 'r--');
xline(0, 'k--', 'code 32');
grid on;
xlabel('相对事件时间 (s)');
ylabel('R-HEOG');
title('水平 EOG：候选眼动活动');

subplot(3,1,2);
plot(timeSec, eogVertical, 'Color', [0.85 0.33 0.10]);
hold on;
% 同一个参考事件只在第一个子图显示文字，下面只保留对齐竖线。
xline(0, 'k--');
grid on;
xlabel('相对事件时间 (s)');
ylabel('L-VEOG');
title('垂直 EOG');

subplot(3,1,3);
plot(timeSec, emgRms, 'Color', [0.20 0.50 0.20]);
hold on;
xline(0, 'k--');
grid on;
xlabel('相对事件时间 (s)');
ylabel('EMG RMS');
title('EMG 肌肉活动强度');

% 用简短总标题说明案例和参考事件，避免标题过长被截断。
sgtitle([caseName, ' | code 32：新脚本开始']);

summaryFigureFile = fullfile(figureDir, [caseName, '_s03_summary.png']);
exportgraphics(summaryFig, summaryFigureFile, 'Resolution', 150);
close(summaryFig);

%% 11. 导出真正的分析特征
% 每个结果都带有明确含义，后续可扩展为多案例表格。
featureTable = table( ...
    {caseName}, 32, referenceMeaning, epochWindow(1), epochWindow(2), ...
    psdPreWindow(1), psdPreWindow(2), psdPostWindow(1), psdPostWindow(2), ...
    eogThreshold, eogPrePeakToPeak, eogPostPeakToPeak, candidateCount, ...
    emgPreRms, emgPostRms, ...
    'VariableNames', {'case_name','reference_code','reference_event_meaning', ...
    'epoch_start_s','epoch_end_s','psd_pre_start_s','psd_pre_end_s', ...
    'psd_post_start_s','psd_post_end_s','eog_threshold', ...
    'eog_pre_peak_to_peak', ...
    'eog_post_peak_to_peak','eog_candidate_burst_count', ...
    'emg_pre_rms','emg_post_rms'});

for b = 1:numel(bandNames)
    % 标准 band power：线性 PSD 在频带内的积分。
    featureTable.(['cz_pre_', bandNames{b}, '_power']) = preBandPower(b);
    featureTable.(['cz_post_', bandNames{b}, '_power']) = postBandPower(b);

    % 描述性指标：频带内平均 dB PSD，不等同于 band power。
    featureTable.(['cz_pre_', bandNames{b}, '_mean_psd_db']) = preMeanPsdDb(b);
    featureTable.(['cz_post_', bandNames{b}, '_mean_psd_db']) = postMeanPsdDb(b);
end

featureFile = fullfile(resultDir, [caseName, '_s03_features.csv']);
writetable(featureTable, featureFile);

%% 12. 在命令窗口给出结果摘要
fprintf('\n===== s03 正式分析完成 =====\n');
fprintf('案例：%s\n', caseName);
fprintf('参考事件：code 32 = %s\n', referenceMeaning);
fprintf('分段：%.1f 到 %.1f 秒\n', epochWindow(1), epochWindow(2));
fprintf('PSD前窗：%.1f 到 %.1f 秒（%.1f秒）\n', ...
    psdPreWindow(1), psdPreWindow(2), diff(psdPreWindow));
fprintf('PSD后窗：%.1f 到 %.1f 秒（%.1f秒）\n', ...
    psdPostWindow(1), psdPostWindow(2), diff(psdPostWindow));
fprintf('EOG 阈值：%.4f\n', eogThreshold);
fprintf('EOG 事件前峰峰值：%.4f\n', eogPrePeakToPeak);
fprintf('EOG 事件后峰峰值：%.4f\n', eogPostPeakToPeak);
fprintf('候选 EOG 活动段数量：%d（不是最终眼动回应次数）\n', candidateCount);
fprintf('EMG 事件前 RMS：%.4f\n', emgPreRms);
fprintf('EMG 事件后 RMS：%.4f\n', emgPostRms);
fprintf('特征表：%s\n', featureFile);
fprintf('摘要图：%s\n', summaryFigureFile);
