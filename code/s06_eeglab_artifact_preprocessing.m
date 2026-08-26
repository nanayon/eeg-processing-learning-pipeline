function s06_eeglab_artifact_preprocessing()
%% s06_eeglab_artifact_preprocessing
% TWC_USA：补上原 pipeline 中“连续滤波 -> epoch”之间缺失的伪迹处理。
%
% 本文件是一个独立的学习型处理脚本：
%   1) 导入连续 EDF，不立即 epoch；
%   2) 在连续数据上生成自动伪迹候选（只作参考）；
%   3) 打开连续波形，人工标注需要删除的时间片段；
%   4) 删除人工确认的连续伪迹；需要时再用剩余连续数据拟合 ICA；
%   5) 需要 ICA 时人工复核成分并移除眼动/肌电等成分；
%   6) 在清洗后的连续数据上分别滤波 EEG/EOG/EMG；
%   7) 最后才截取最后一个 code 32 的 epoch；
%   8) 保存中间结果、评分表、伪迹区间和质控图。
%
% 重要：
%   - TWC_USA 发布包已经对多数坏 EEG 通道做过球面插值。本文件不会重复
%     插值，并会在 ICA 拟合时排除这些已插值通道。
%   - 自动阈值和 EOG/EMG 相关性只用来提出候选，不能代替人工判断。
%   - 第一次运行建议只处理 case07_sub106，并保留默认的人工复核模式。

%% 0. 学习参数：先从这里读懂并修改
caseName = 'case07_sub106';

% 连续伪迹处理：人工标注为主。
manualContinuousReview = true;
showAutomaticIntervalsInReview = false;
deleteMarkedContinuousArtifacts = true;
manualReviewWindowSeconds = 30;

% ICA 是可选的第二阶段。先掌握人工连续伪迹删除，再改为 true 学习 ICA。
enableICA = false;

% ICA 成分复核：
%   true  -> 有候选 IC 时在命令窗口询问要删除哪些成分；
%   false -> 不询问，只保存候选 IC。
reviewComponents = true;

% 如果已经人工确认了 IC，可以直接写入，例如 [1 4]。
% 该变量优先级高于下面两个自动/交互选项。
componentsToRemove = [];

% 第一次学习建议 false。只有你确认相关性候选可靠时才改成 true。
autoRemoveSuggestedComponents = false;

% 信号频带。ICA 副本与最终分析副本分开，避免 1 Hz 高通改变最终慢波分析。
icaBand = [1 40];
eegBand = [0.5 35];
eogBand = [0.1 15];
emgBand = [10 100];

% 连续伪迹检测阈值。BioSig 导入本数据后，EEGLAB 数据按 uV 使用。
peakThresholdUV = 500;
robustZThreshold = 10;
jumpThresholdUV = 200;
flatThresholdUV = 0.01;
flatWindowSeconds = 1.0;
flatChannelFraction = 0.80;
minimumBadDurationSeconds = 0.05;
artifactPadSeconds = 0.25;
maxICARejectFraction = 0.25;

% EOG/EMG 与 IC 的绝对 Pearson 相关性达到该值时，列为候选。
componentCorrelationThreshold = 0.35;
icaMaxSteps = 512;

% 与既有 s03 保持一致：最后一个 code 32，前后各 10 秒。
referenceEvent = '32';
epochWindow = [-10 10];

% epoch 级残余伪迹默认只写入日志，不自动删除；连续标记按上面的配置删除。
rejectDetectedEpoch = false;
epochPeakToPeakThresholdUV = 500;

%% 1. 定位工程目录并初始化 EEGLAB/BioSig
projectDir = fileparts(fileparts(mfilename('fullpath')));
codeDir = fileparts(mfilename('fullpath'));
rawDir = fullfile(projectDir, 'raw', 'TWC_USA', 'Data', 'PSG');
outputDir = fullfile(projectDir, 'results', 'artifact_preprocessing', caseName);
figureDir = fullfile(projectDir, 'figures', 'artifact_preprocessing');

if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end
if ~exist(figureDir, 'dir')
    mkdir(figureDir);
end

eeglabRoot = 'E:\Application\Matlab\toolbox\eeglab2026.0.0';
if ~isfolder(eeglabRoot)
    error('找不到 EEGLAB 安装目录：%s', eeglabRoot);
end
addpath(eeglabRoot);
addpath(codeDir);
eeglab('nogui');

requiredFunctions = {'pop_biosig','pop_eegfiltnew','eeg_eegrej', ...
    'eegplot','pop_epoch','pop_rejepoch','pop_saveset', ...
    'pop_runica','pop_subcomp'};
for k = 1:numel(requiredFunctions)
    if isempty(which(requiredFunctions{k}))
        error('找不到 EEGLAB 函数：%s。请检查插件和 MATLAB 路径。', ...
            requiredFunctions{k});
    end
end

edfFile = fullfile(rawDir, [caseName, '.edf']);
if ~exist(edfFile, 'file')
    error('找不到 EDF 文件：%s', edfFile);
end

cfg = struct();
cfg.caseName = caseName;
cfg.manualContinuousReview = manualContinuousReview;
cfg.showAutomaticIntervalsInReview = showAutomaticIntervalsInReview;
cfg.deleteMarkedContinuousArtifacts = deleteMarkedContinuousArtifacts;
cfg.manualReviewWindowSeconds = manualReviewWindowSeconds;
cfg.runICA = enableICA;
cfg.reviewComponents = reviewComponents;
cfg.componentsToRemove = componentsToRemove;
cfg.autoRemoveSuggestedComponents = autoRemoveSuggestedComponents;
cfg.icaBand = icaBand;
cfg.eegBand = eegBand;
cfg.eogBand = eogBand;
cfg.emgBand = emgBand;
cfg.peakThresholdUV = peakThresholdUV;
cfg.robustZThreshold = robustZThreshold;
cfg.jumpThresholdUV = jumpThresholdUV;
cfg.flatThresholdUV = flatThresholdUV;
cfg.flatWindowSeconds = flatWindowSeconds;
cfg.flatChannelFraction = flatChannelFraction;
cfg.minimumBadDurationSeconds = minimumBadDurationSeconds;
cfg.artifactPadSeconds = artifactPadSeconds;
cfg.maxICARejectFraction = maxICARejectFraction;
cfg.componentCorrelationThreshold = componentCorrelationThreshold;
cfg.icaMaxSteps = icaMaxSteps;
cfg.referenceEvent = referenceEvent;
cfg.epochWindow = epochWindow;
cfg.rejectDetectedEpoch = rejectDetectedEpoch;
cfg.epochPeakToPeakThresholdUV = epochPeakToPeakThresholdUV;

processOneCase(edfFile, outputDir, figureDir, cfg);

end


function processOneCase(edfFile, outputDir, figureDir, cfg)

caseName = cfg.caseName;

%% A. 导入连续 EDF
% 这里故意不调用 pop_epoch：先保留完整连续记录，方便检测连续伪迹并拟合 ICA。
EEG_raw = pop_biosig(edfFile, ...
    'importevent', 'on', ...
    'importannot', 'on', ...
    'blockepoch', 'off', ...
    'rmeventchan', 'on');
EEG_raw = eeg_checkset(EEG_raw);
EEG_raw = ensureEtcStruct(EEG_raw);
EEG_raw = normalizeNumericEventTypes(EEG_raw);

labels = {EEG_raw.chanlocs.labels};
[eegIdx, eogIdx, emgIdx, statusIdx] = identifyTWCChannels(labels);

if numel(eegIdx) < 2
    error('%s：识别到的头皮 EEG 通道少于 2 个。', caseName);
end

knownInterpolatedLabels = getKnownInterpolatedLabels(caseName);
knownInterpolatedIdx = find(ismember(labels, knownInterpolatedLabels));
icaEegIdx = setdiff(eegIdx, knownInterpolatedIdx, 'stable');

if numel(icaEegIdx) < 2
    error('%s：排除已插值通道后，ICA 可用 EEG 少于 2 个。', caseName);
end

%% B. 检查 EDF 转换造成的末尾平坦 EEG
% DREAM 说明只说“可能”有约 1 秒平坦尾部，所以只在实际检测到时记录。
flatTail = detectFlatTail(EEG_raw, eegIdx, 1.0, cfg.flatThresholdUV);

%% C. 在连续 EEG 上检测高振幅、突变和平坦片段
% 这一步只生成自动候选；最终是否删除由连续波形人工复核决定。
EEG_detection = pop_eegfiltnew(EEG_raw, ...
    'locutoff', 0.5, 'hicutoff', 35, 'channels', eegIdx);
detectionDataUV = double(EEG_detection.data(icaEegIdx, :, 1));

[badMask, detectionSummary] = detectContinuousArtifacts( ...
    detectionDataUV, EEG_raw.srate, cfg);

autoBadIntervals = maskToIntervals(badMask, EEG_raw.srate, ...
    cfg.minimumBadDurationSeconds, cfg.artifactPadSeconds, EEG_raw.pnts);

if flatTail.detected
    tailStart = EEG_raw.pnts - flatTail.samples + 1;
    tailEnd = EEG_raw.pnts;
    autoBadIntervals = mergeIntervals( ...
        [autoBadIntervals; tailStart tailEnd], EEG_raw.pnts);
end

[~, originalTargetLatency] = keepLatestReferenceEvent( ...
    EEG_raw, cfg.referenceEvent);

% 自动区间在界面中默认不预先标色；这样“删除什么”由人工观察决定。
% 如希望把自动候选作为起点，可将 showAutomaticIntervalsInReview 改为 true。
if cfg.manualContinuousReview
    [badIntervals, manualReviewAccepted] = manuallyReviewContinuousArtifacts( ...
        EEG_detection, eegIdx, autoBadIntervals, cfg);
else
    badIntervals = autoBadIntervals;
    manualReviewAccepted = false;
end

recordSeconds = EEG_raw.pnts / EEG_raw.srate;
badSeconds = intervalDurationSeconds(badIntervals, EEG_raw.srate);
badFraction = badSeconds / recordSeconds;

% 人工确认的区间会同时用于 ICA 训练和最终连续数据删除。
intervalsForICA = badIntervals;
if cfg.runICA && badFraction > cfg.maxICARejectFraction
    warning('%s：人工标记区间占 %.2f%%，超过 ICA 建议上限 %.0f%%；请复核标记。', ...
        caseName, 100 * badFraction, 100 * cfg.maxICARejectFraction);
end

referenceIndices = [eogIdx, emgIdx];
referenceLabels = labels(referenceIndices);
componentScores = zeros(0, numel(referenceIndices));
suggestedComponents = zeros(1, 0);
removedComponents = zeros(1, 0);
componentCsv = '';

%% D. 可选：在删除连续伪迹后拟合 ICA
% enableICA=false 时，流程到这里不会运行 ICA；先学习人工波形标注和删除。
if cfg.runICA
    % ICA 使用 1-40 Hz 副本；最终 EEG 仍会使用 0.5-35 Hz 副本。
    icaFilterChannels = unique([icaEegIdx, eogIdx, emgIdx]);
    EEG_ica = pop_eegfiltnew(EEG_raw, ...
        'locutoff', cfg.icaBand(1), ...
        'hicutoff', cfg.icaBand(2), ...
        'channels', icaFilterChannels);

    if ~isempty(intervalsForICA)
        EEG_ica = eeg_eegrej(EEG_ica, intervalsForICA);
    end

    % 只用未插值的 EEG 通道估计独立成分；EOG/EMG 留在结构中作参考信号。
    EEG_ica = pop_runica(EEG_ica, ...
        'icatype', 'runica', ...
        'chanind', icaEegIdx, ...
        'options', {'extended', 1, ...
        'verbose', 'off', ...
        'interrupt', 'off', ...
        'maxsteps', cfg.icaMaxSteps});
    EEG_ica = eeg_checkset(EEG_ica);

    icaActivity = calculateICAActivity(EEG_ica);
    componentScores = zeros(size(icaActivity, 1), numel(referenceIndices));
    for ic = 1:size(icaActivity, 1)
        for r = 1:numel(referenceIndices)
            referenceSignal = double(EEG_ica.data(referenceIndices(r), :, 1));
            componentScores(ic, r) = abs(safeCorrelation( ...
                icaActivity(ic, :), referenceSignal));
        end
    end

    if isempty(referenceIndices)
        suggestedComponents = zeros(1, 0);
    else
        suggestedComponents = find(max(componentScores, [], 2) >= ...
            cfg.componentCorrelationThreshold)';
    end

    componentTable = makeComponentTable(componentScores, referenceLabels, ...
        cfg.componentCorrelationThreshold, suggestedComponents);
    componentCsv = fullfile(outputDir, [caseName, '_component_scores.csv']);
    writetable(componentTable, componentCsv);

    %% E. 选择要移除的 IC
    % 相关性是候选机制，不是最终判据。应结合 IC 图形/波形后再输入。
    if ~isempty(cfg.componentsToRemove)
        removedComponents = unique(cfg.componentsToRemove(:)');
    elseif cfg.autoRemoveSuggestedComponents
        removedComponents = suggestedComponents;
    elseif cfg.reviewComponents && ~isempty(suggestedComponents)
        fprintf('\n候选 IC：%s\n', mat2str(suggestedComponents));
        fprintf('请结合 ICA 成分图形后输入要移除的 IC；直接回车表示暂不移除。\n');
        answer = input('IC 编号，例如 [1 4]： ');
        if isempty(answer)
            removedComponents = zeros(1, 0);
        else
            removedComponents = unique(answer(:)');
        end
    end

    nComponents = size(icaActivity, 1);
    if any(removedComponents < 1 | removedComponents > nComponents | ...
            removedComponents ~= round(removedComponents))
        error('%s：要移除的 IC 编号无效。', caseName);
    end
end

%% F. 应用可选 ICA，并删除人工确认的时间片段
% 如果 deleteMarkedContinuousArtifacts=true，人工标记片段会从工作数据中删除；
% eeg_eegrej 会同步更新事件 latency，并保留 boundary 事件。
EEG_cleanBase = EEG_raw;
continuousIntervalsDeleted = cfg.deleteMarkedContinuousArtifacts && ...
    ~isempty(badIntervals);
if continuousIntervalsDeleted
    EEG_cleanBase = eeg_eegrej(EEG_cleanBase, badIntervals);
    EEG_cleanBase = eeg_checkset(EEG_cleanBase);
end

if cfg.runICA
    EEG_clean = copyICAFields(EEG_cleanBase, EEG_ica, icaEegIdx);
    if ~isempty(removedComponents)
        EEG_clean = pop_subcomp(EEG_clean, removedComponents, 0);
    end
else
    EEG_clean = EEG_cleanBase;
end
EEG_clean = eeg_checkset(EEG_clean);

%% G. 清洗后再建立 EEG/EOG/EMG 滤波副本
EEG_eegContinuous = pop_eegfiltnew(EEG_clean, ...
    'locutoff', cfg.eegBand(1), ...
    'hicutoff', cfg.eegBand(2), ...
    'channels', eegIdx);

EEG_eogContinuous = EEG_clean;
if ~isempty(eogIdx)
    EEG_eogContinuous = pop_eegfiltnew(EEG_eogContinuous, ...
        'locutoff', cfg.eogBand(1), ...
        'hicutoff', cfg.eogBand(2), ...
        'channels', eogIdx);
end

EEG_emgContinuous = EEG_clean;
if ~isempty(emgIdx)
    EEG_emgContinuous = pop_eegfiltnew(EEG_emgContinuous, ...
        'locutoff', cfg.emgBand(1), ...
        'hicutoff', cfg.emgBand(2), ...
        'channels', emgIdx);
end

artifactInfo = struct();
artifactInfo.sourceFile = edfFile;
artifactInfo.knownInterpolatedLabels = knownInterpolatedLabels;
artifactInfo.icaChannels = labels(icaEegIdx);
artifactInfo.icaBandHz = cfg.icaBand;
artifactInfo.eegBandHz = cfg.eegBand;
artifactInfo.eogBandHz = cfg.eogBand;
artifactInfo.emgBandHz = cfg.emgBand;
artifactInfo.removedComponents = removedComponents;
artifactInfo.suggestedComponents = suggestedComponents;
artifactInfo.componentScoresFile = componentCsv;
artifactInfo.automaticBadIntervalsSamples = autoBadIntervals;
artifactInfo.manualReviewAccepted = manualReviewAccepted;
artifactInfo.badIntervalsSamples = badIntervals;
artifactInfo.badIntervalsSeconds = badIntervals / EEG_raw.srate;
artifactInfo.continuousIntervalsDeleted = continuousIntervalsDeleted;
artifactInfo.originalReferenceLatencySamples = originalTargetLatency;
artifactInfo.flatTail = flatTail;
artifactInfo.detectionSummary = detectionSummary;
artifactInfo.thresholds = cfg;

EEG_clean.etc.artifactProcessing = artifactInfo;
EEG_eegContinuous.etc.artifactProcessing = artifactInfo;
EEG_eogContinuous.etc.artifactProcessing = artifactInfo;
EEG_emgContinuous.etc.artifactProcessing = artifactInfo;

pop_saveset(EEG_eegContinuous, ...
    'filename', [caseName, '_artifact_clean_continuous.set'], ...
    'filepath', outputDir);
pop_saveset(EEG_eogContinuous, ...
    'filename', [caseName, '_artifact_clean_eog_continuous.set'], ...
    'filepath', outputDir);
pop_saveset(EEG_emgContinuous, ...
    'filename', [caseName, '_artifact_clean_emg_continuous.set'], ...
    'filepath', outputDir);

%% H. 保存伪迹区间和完整日志
intervalTable = makeIntervalTable(badIntervals, EEG_raw.srate);
intervalCsv = fullfile(outputDir, [caseName, '_artifact_intervals.csv']);
writetable(intervalTable, intervalCsv);

artifactLog = struct();
artifactLog.caseName = caseName;
artifactLog.sourceFile = edfFile;
artifactLog.samplingRateHz = EEG_raw.srate;
artifactLog.durationSeconds = recordSeconds;
artifactLog.channelLabels = labels;
artifactLog.eegLabels = labels(eegIdx);
artifactLog.eogLabels = labels(eogIdx);
artifactLog.emgLabels = labels(emgIdx);
artifactLog.statusIndex = statusIdx;
artifactLog.knownInterpolatedLabels = knownInterpolatedLabels;
artifactLog.knownInterpolatedIndices = knownInterpolatedIdx;
artifactLog.icaChannels = labels(icaEegIdx);
artifactLog.automaticBadIntervalsSamples = autoBadIntervals;
artifactLog.manualReviewAccepted = manualReviewAccepted;
artifactLog.badIntervalsSamples = badIntervals;
artifactLog.badIntervalsSeconds = badIntervals / EEG_raw.srate;
artifactLog.continuousIntervalsDeleted = continuousIntervalsDeleted;
artifactLog.originalReferenceLatencySamples = originalTargetLatency;
artifactLog.componentsSuggested = suggestedComponents;
artifactLog.componentsRemoved = removedComponents;
artifactLog.componentReferenceLabels = referenceLabels;
artifactLog.componentScores = componentScores;
artifactLog.componentScoresFile = componentCsv;
artifactLog.eogContinuousSet = fullfile(outputDir, ...
    [caseName, '_artifact_clean_eog_continuous.set']);
artifactLog.emgContinuousSet = fullfile(outputDir, ...
    [caseName, '_artifact_clean_emg_continuous.set']);
artifactLog.flatTail = flatTail;
artifactLog.detectionSummary = detectionSummary;
artifactLog.config = cfg;

logFile = fullfile(outputDir, [caseName, '_artifact_log.mat']);
save(logFile, 'artifactLog', '-v7.3');

%% I. 清洗后才截取最后一个 code 32 epoch
[EEG_eegContinuous, targetLatency] = keepLatestReferenceEvent( ...
    EEG_eegContinuous, cfg.referenceEvent);

epochContainsContinuousArtifact = false;
epochArtifactOverlap = zeros(0, 2);
residualEpochArtifact = false;

if ~isempty(originalTargetLatency)
    originalEpochStart = originalTargetLatency + ...
        cfg.epochWindow(1) * EEG_raw.srate;
    originalEpochEnd = originalTargetLatency + ...
        cfg.epochWindow(2) * EEG_raw.srate;
    epochArtifactOverlap = intervalsOverlap( ...
        badIntervals, originalEpochStart, originalEpochEnd);
    epochContainsContinuousArtifact = ~isempty(epochArtifactOverlap);
end

if isempty(targetLatency)
    warning('%s：没有找到参考事件 %s，跳过 epoch。', ...
        caseName, cfg.referenceEvent);
else
    EEG_epoch = pop_epoch(EEG_eegContinuous, ...
        {cfg.referenceEvent}, cfg.epochWindow, 'epochinfo', 'yes');
    EEG_epoch = eeg_checkset(EEG_epoch);

    epochData = double(EEG_epoch.data(eegIdx, :, :));
    epochPeakToPeakUV = max(epochData, [], 2) - min(epochData, [], 2);
    residualEpochArtifact = any(epochPeakToPeakUV(:) > ...
        cfg.epochPeakToPeakThresholdUV);

    EEG_epoch.etc.artifactProcessing = artifactInfo;
    EEG_epoch.etc.artifactProcessing.epochContainsContinuousArtifact = ...
        epochContainsContinuousArtifact;
    EEG_epoch.etc.artifactProcessing.epochArtifactOverlap = ...
        epochArtifactOverlap;
    EEG_epoch.etc.artifactProcessing.residualEpochArtifact = ...
        residualEpochArtifact;

    pop_saveset(EEG_epoch, ...
        'filename', [caseName, '_artifact_clean_event32_epoch.set'], ...
        'filepath', outputDir);

    if cfg.rejectDetectedEpoch && ...
            (epochContainsContinuousArtifact || residualEpochArtifact)
        EEG_epochAccepted = pop_rejepoch(EEG_epoch, 1, 0);
        EEG_epochAccepted.etc.artifactProcessing = ...
            EEG_epoch.etc.artifactProcessing;
        pop_saveset(EEG_epochAccepted, ...
            'filename', [caseName, '_artifact_clean_event32_epoch_accepted.set'], ...
            'filepath', outputDir);
        clear EEG_epochAccepted;
    end
end

epochSummary = struct();
epochSummary.caseName = caseName;
epochSummary.referenceEvent = cfg.referenceEvent;
epochSummary.referenceLatencySamples = targetLatency;
epochSummary.epochWindowSeconds = cfg.epochWindow;
epochSummary.containsContinuousArtifact = epochContainsContinuousArtifact;
epochSummary.continuousArtifactOverlap = epochArtifactOverlap;
epochSummary.residualEpochArtifact = residualEpochArtifact;
epochSummary.rejectDetectedEpoch = cfg.rejectDetectedEpoch;
epochSummary.originalReferenceLatencySamples = originalTargetLatency;
epochSummary.cleanedDurationSeconds = EEG_eegContinuous.pnts / EEG_eegContinuous.srate;
epochSummary.intervalCsv = intervalCsv;
epochSummary.continuousSet = fullfile(outputDir, ...
    [caseName, '_artifact_clean_continuous.set']);
epochSummary.epochSet = fullfile(outputDir, ...
    [caseName, '_artifact_clean_event32_epoch.set']);
save(fullfile(outputDir, [caseName, '_epoch_qc.mat']), 'epochSummary');

%% J. 保存前后波形质控图
figureFile = fullfile(figureDir, [caseName, '_artifact_qc.png']);
plotArtifactQC(EEG_raw, EEG_detection, EEG_raw, EEG_raw, ...
    labels, eegIdx, eogIdx, emgIdx, originalTargetLatency, ...
    cfg.epochWindow, badIntervals, removedComponents, ...
    figureFile, caseName);

end


function [intervals, accepted] = manuallyReviewContinuousArtifacts( ...
        EEG, displayIdx, automaticIntervals, cfg)
% 打开 EEGLAB 的连续波形浏览器。用户拖动时间范围进行标记，
% 点击 ACCEPT AND DELETE 后返回 TMPREJ；关闭/取消则不删除任何时间片段。
% 这里的时间标记会作用于全部通道，而不只是当前显示的通道。

intervals = zeros(0, 2);
accepted = false;
if isempty(displayIdx)
    return;
end

displayData = double(EEG.data(displayIdx, :, 1));
nDisplayChannels = numel(displayIdx);
winrej = zeros(0, 5 + nDisplayChannels);
if cfg.showAutomaticIntervalsInReview && ~isempty(automaticIntervals)
    winrej = [automaticIntervals, ...
        repmat([1.0 0.75 0.75], size(automaticIntervals, 1), 1), ...
        true(size(automaticIntervals, 1), nDisplayChannels)];
end

% eegplot 的按钮回调在 MATLAB base workspace 中执行，因此用一个专用
% 临时变量接收 TMPREJ，避免依赖函数工作区变量。
evalin('base', 'clear TWC_MANUAL_TMPREJ');
oldFigures = findall(0, 'Type', 'figure', 'Tag', 'EEGPLOT');

eegplotArgs = { ...
    'srate', EEG.srate, ...
    'winlength', cfg.manualReviewWindowSeconds, ...
    'title', 'TWC_USA 连续伪迹人工标注（拖动标记，点击 ACCEPT AND DELETE）', ...
    'events', EEG.event, ...
    'winrej', winrej, ...
    'command', 'assignin(''base'', ''TWC_MANUAL_TMPREJ'', TMPREJ);', ...
    'butlabel', 'ACCEPT AND DELETE'};

if ~isempty(EEG.chanlocs)
    eegplotArgs = [eegplotArgs, {'eloc_file', EEG.chanlocs(displayIdx)}];
end

eegplot(displayData, eegplotArgs{:});
drawnow;
newFigures = setdiff(findall(0, 'Type', 'figure', 'Tag', 'EEGPLOT'), ...
    oldFigures);
if isempty(newFigures)
    evalin('base', 'clear TWC_MANUAL_TMPREJ');
    return;
end

uiwait(newFigures(1));
hasMarks = evalin('base', ...
    'exist(''TWC_MANUAL_TMPREJ'', ''var'')');
if hasMarks
    marks = evalin('base', 'TWC_MANUAL_TMPREJ');
    evalin('base', 'clear TWC_MANUAL_TMPREJ TMPREJ');
    if ~isempty(marks) && size(marks, 2) >= 2
        intervals = mergeIntervals(marks(:, 1:2), EEG.pnts);
    end
    accepted = true;
else
    evalin('base', 'clear TWC_MANUAL_TMPREJ TMPREJ');
end
end


function EEG = normalizeNumericEventTypes(EEG)
for k = 1:numel(EEG.event)
    rawType = char(string(EEG.event(k).type));
    numericType = str2double(rawType);
    if isfinite(numericType)
        EEG.event(k).type = num2str(round(numericType));
    end
end
EEG = eeg_checkset(EEG);
end


function [eegIdx, eogIdx, emgIdx, statusIdx] = identifyTWCChannels(labels)
eegLabels = {'Fpz','Fz','Cz','Pz','Oz','Fp1','Fp2','F3','F4', ...
    'C3','C4','P3','P4','O1','O2','F7','F8','T3','T4','T5','T6'};
eogLabels = {'R-HEOG','L-VEOG'};
emgLabels = {'EMG','26','27'};
statusLabels = {'Status','status'};

eegIdx = find(ismember(labels, eegLabels));
eogIdx = find(ismember(labels, eogLabels));
emgIdx = find(ismember(labels, emgLabels));
statusIdx = find(ismember(labels, statusLabels));
end


function labels = getKnownInterpolatedLabels(caseName)
% 来源：raw/TWC_USA/ExperimentalDescription.txt。
switch caseName
    case {'case01_sub101'}
        labels = {'C4'};
    case {'case02_sub102','case03_sub102'}
        labels = {'Fz','Cz','F3','C3','P4'};
    case {'case04_sub103'}
        labels = {'Fz','Cz','Oz','Fp1','F4','C3','C4','P3','P4'};
    case {'case05_sub104'}
        labels = {'F7'};
    case {'case06_sub105'}
        labels = {'Fp1','Fp2','F3','F4'};
    case {'case07_sub106','case08_sub106'}
        labels = {'Fp1','Fp2','T4','T6'};
    case {'case09_sub106','case10_sub106'}
        labels = {'Fz','Fp1'};
    case {'case11_sub106'}
        labels = {'Fp2','F3'};
    case {'case12_sub106','case13_sub106'}
        labels = {'Fpz','Fp1'};
    case {'case14_sub107'}
        labels = {'Pz','Oz','C4','P4','T4','T5'};
    case {'case15_sub108','case16_sub108'}
        labels = {'Cz','Pz','Oz','C4','P3','P4','O2','T3','T4','T5'};
    case {'case17_sub109'}
        labels = {'Fpz','Fz','Cz','Pz','F3','F4','C3','C4','P3','P4', ...
            'F7','F8','T4','T5'};
    case {'case18_sub110'}
        labels = {'Cz','Oz','F3','F4','C4','P3','O1','O2','F7','F8', ...
            'T4','T5','T6'};
    case {'case19_sub111','case20_sub111','case21_sub111'}
        labels = {'Fp1','Fp2'};
    case {'case22_sub113'}
        labels = {'Fpz','Fz','Cz','Pz','F3','C3','C4','P3','P4','O1', ...
            'O2','F7','T4','T5','T6'};
    case {'case23_sub114'}
        labels = {'Fpz','Cz','F4','C3','O1','F7','T5'};
    case {'case24_sub116'}
        labels = {'Fpz','Cz','Pz','Oz','F4','C3','O2','P4','T3','T4','T5','T6'};
    case {'case25_sub117'}
        labels = {'Fz','Cz','Pz','Oz','F4','C3','C4','P3','P4','O1','O2', ...
            'F7','F8','T3','T4','T6'};
    case {'case26_sub118'}
        labels = {'Fz','Cz','F4'};
    case {'case27_sub119','case28_sub119'}
        labels = {'Fpz','Fp1','F3','T4'};
    case {'case29_sub121'}
        labels = {'Fp2','C3','P4','Pz','O2'};
    case {'case30_sub121','case31_sub121'}
        labels = {'Oz','F4','C3','C4'};
    case {'case32_sub122','case33_sub122'}
        labels = {'C3'};
    otherwise
        labels = {};
end
end


function result = detectFlatTail(EEG, eegIdx, tailSeconds, flatThresholdUV)
result = struct('detected', false, 'durationSeconds', 0, ...
    'samples', 0, 'flatChannelFraction', 0, ...
    'channelPeakToPeakUV', []);

if isempty(eegIdx) || EEG.pnts < 2
    return;
end

samples = min(EEG.pnts, max(2, round(tailSeconds * EEG.srate)));
tailData = double(EEG.data(eegIdx, EEG.pnts-samples+1:EEG.pnts, 1));
channelPeakToPeakUV = max(tailData, [], 2) - min(tailData, [], 2);
flatChannels = channelPeakToPeakUV <= flatThresholdUV;
flatFraction = mean(flatChannels);

result.durationSeconds = samples / EEG.srate;
result.samples = samples;
result.flatChannelFraction = flatFraction;
result.channelPeakToPeakUV = channelPeakToPeakUV;
result.detected = flatFraction >= 0.80;

if ~result.detected
    result.durationSeconds = 0;
    result.samples = 0;
end
end


function [badMask, summary] = detectContinuousArtifacts(dataUV, srate, cfg)
centered = dataUV - median(dataUV, 2, 'omitnan');
robustScale = 1.4826 * median(abs(centered), 2, 'omitnan');
fallbackScale = std(centered, 0, 2, 'omitnan');

replaceScale = ~isfinite(robustScale) | robustScale <= eps;
robustScale(replaceScale) = fallbackScale(replaceScale);
robustScale(~isfinite(robustScale) | robustScale <= eps) = 1;

perChannelThreshold = max(cfg.peakThresholdUV, ...
    cfg.robustZThreshold * robustScale);
peakMask = any(abs(centered) > perChannelThreshold, 1);

jumpMask = false(1, size(dataUV, 2));
if size(dataUV, 2) > 1
    jumpMask(2:end) = any(abs(diff(dataUV, 1, 2)) > ...
        cfg.jumpThresholdUV, 1);
end

flatMask = false(1, size(dataUV, 2));
windowSamples = max(2, round(cfg.flatWindowSeconds * srate));
for startSample = 1:windowSamples:size(dataUV, 2)
    endSample = min(size(dataUV, 2), ...
        startSample + windowSamples - 1);
    windowData = dataUV(:, startSample:endSample);
    windowPeakToPeak = max(windowData, [], 2) - ...
        min(windowData, [], 2);
    if mean(windowPeakToPeak <= cfg.flatThresholdUV) >= ...
            cfg.flatChannelFraction
        flatMask(startSample:endSample) = true;
    end
end

badMask = peakMask | jumpMask | flatMask;
summary = struct();
summary.peakSamples = sum(peakMask);
summary.jumpSamples = sum(jumpMask);
summary.flatSamples = sum(flatMask);
summary.peakSeconds = summary.peakSamples / srate;
summary.jumpSeconds = summary.jumpSamples / srate;
summary.flatSeconds = summary.flatSamples / srate;
summary.robustScaleUV = robustScale;
end


function intervals = maskToIntervals(mask, srate, minDurationSeconds, padSeconds, nSamples)
mask = logical(mask(:)');
if isempty(mask) || ~any(mask)
    intervals = zeros(0, 2);
    return;
end

starts = find(diff([false mask]) == 1);
ends = find(diff([mask false]) == -1);
minimumSamples = max(1, round(minDurationSeconds * srate));
keep = (ends - starts + 1) >= minimumSamples;
starts = starts(keep);
ends = ends(keep);

padding = round(padSeconds * srate);
starts = max(1, starts - padding);
ends = min(nSamples, ends + padding);
intervals = mergeIntervals([starts(:), ends(:)], nSamples);
end


function merged = mergeIntervals(intervals, nSamples)
if isempty(intervals)
    merged = zeros(0, 2);
    return;
end

intervals = round(double(intervals));
intervals(:,1) = max(1, intervals(:,1));
intervals(:,2) = min(nSamples, intervals(:,2));
intervals = intervals(intervals(:,2) >= intervals(:,1), :);

if isempty(intervals)
    merged = zeros(0, 2);
    return;
end

intervals = sortrows(intervals, 1);
merged = intervals(1,:);
for k = 2:size(intervals, 1)
    if intervals(k,1) <= merged(end,2) + 1
        merged(end,2) = max(merged(end,2), intervals(k,2));
    else
        merged(end+1,:) = intervals(k,:); %#ok<AGROW>
    end
end
end


function seconds = intervalDurationSeconds(intervals, srate)
if isempty(intervals)
    seconds = 0;
else
    seconds = sum(intervals(:,2) - intervals(:,1) + 1) / srate;
end
end


function icaActivity = calculateICAActivity(EEG)
if isempty(EEG.icaweights) || isempty(EEG.icasphere)
    error('ICA 权重为空，无法计算成分激活。');
end
data = double(EEG.data(EEG.icachansind, :, 1));
icaActivity = double(EEG.icaweights) * double(EEG.icasphere) * data;
end


function r = safeCorrelation(x, y)
x = double(x(:));
y = double(y(:));
valid = isfinite(x) & isfinite(y);

if sum(valid) < 10 || std(x(valid)) <= eps || std(y(valid)) <= eps
    r = 0;
else
    r = corr(x(valid), y(valid), 'Type', 'Pearson');
    if isempty(r) || ~isfinite(r)
        r = 0;
    end
end
end


function componentTable = makeComponentTable(scores, referenceLabels, threshold, suggested)
nComponents = size(scores, 1);
componentTable = table((1:nComponents)', 'VariableNames', {'IC'});

for k = 1:numel(referenceLabels)
    variableName = matlab.lang.makeValidName( ...
        ['absCorr_', referenceLabels{k}]);
    componentTable.(variableName) = scores(:, k);
end

if isempty(scores)
    maxScore = zeros(nComponents, 1);
else
    maxScore = max(scores, [], 2);
end
componentTable.maxAbsCorrelation = maxScore;
componentTable.threshold = repmat(threshold, nComponents, 1);
componentTable.suggestedForReview = ismember((1:nComponents)', suggested);
end


function EEGout = copyICAFields(EEGin, EEGica, icaEegIdx)
EEGout = EEGin;
EEGout = ensureEtcStruct(EEGout);
EEGout.icaweights = EEGica.icaweights;
EEGout.icasphere = EEGica.icasphere;
EEGout.icawinv = EEGica.icawinv;
EEGout.icachansind = icaEegIdx;
EEGout.icaact = [];
end


function EEG = ensureEtcStruct(EEG)
if ~isfield(EEG, 'etc') || isempty(EEG.etc) || ~isstruct(EEG.etc)
    EEG.etc = struct();
end
end


function [EEG, targetLatency] = keepLatestReferenceEvent(EEG, referenceEvent)
EEG = normalizeNumericEventTypes(EEG);
eventTypes = cellfun(@(x) char(string(x)), ...
    {EEG.event.type}, 'UniformOutput', false);
indices = find(strcmp(eventTypes, referenceEvent));
targetLatency = [];

if isempty(indices)
    return;
end

[~, latestPosition] = max([EEG.event(indices).latency]);
targetIndex = indices(latestPosition);
targetLatency = double(EEG.event(targetIndex).latency);

for k = indices
    if k ~= targetIndex
        EEG.event(k).type = [referenceEvent, '_non_target'];
    end
end
EEG = eeg_checkset(EEG);
end


function overlap = intervalsOverlap(intervals, startSample, endSample)
if isempty(intervals)
    overlap = zeros(0, 2);
    return;
end
overlap = intervals(intervals(:,2) >= startSample & ...
    intervals(:,1) <= endSample, :);
end


function intervalTable = makeIntervalTable(intervals, srate)
if isempty(intervals)
    intervalTable = table(zeros(0,1), zeros(0,1), ...
        zeros(0,1), zeros(0,1), strings(0,1), ...
        'VariableNames', {'StartSample','EndSample', ...
        'StartSeconds','EndSeconds','Reason'});
    return;
end

startSample = intervals(:,1);
endSample = intervals(:,2);
startSeconds = (startSample - 1) / srate;
endSeconds = endSample / srate;
reason = repmat("continuous_artifact_candidate", size(intervals,1), 1);

intervalTable = table(startSample, endSample, startSeconds, ...
    endSeconds, reason, 'VariableNames', {'StartSample','EndSample', ...
    'StartSeconds','EndSeconds','Reason'});
end


function text = joinOrNone(items)
if isempty(items)
    text = '(none)';
elseif isstring(items)
    text = strjoin(cellstr(items), ', ');
else
    text = strjoin(items, ', ');
end
end


function plotArtifactQC(EEGraw, EEGcleanEEG, EEGeog, EEGemg, labels, ...
        eegIdx, eogIdx, emgIdx, targetLatency, epochWindow, ...
        badIntervals, removedComponents, figureFile, caseName)

if isempty(targetLatency)
    targetLatency = round(EEGraw.pnts / 2);
end

windowStart = max(1, round(targetLatency + epochWindow(1) * EEGraw.srate));
windowEnd = min(EEGraw.pnts, round(targetLatency + epochWindow(2) * EEGraw.srate));
sampleRange = windowStart:windowEnd;
time = (sampleRange - targetLatency) / EEGraw.srate;

czIdx = find(strcmp(labels, 'Cz'), 1);
if isempty(czIdx)
    czIdx = eegIdx(1);
end

eogPlotIdx = eogIdx(1:min(2, numel(eogIdx)));
emgPlotIdx = emgIdx(1:min(2, numel(emgIdx)));

figureHandle = figure('Name', [caseName, ' artifact QC'], ...
    'Color', 'w', 'Visible', 'off', 'Position', [100 100 1500 900]);

subplot(4,1,1);
plot(time, double(EEGraw.data(czIdx, sampleRange, 1)), ...
    'Color', [0.45 0.45 0.45]);
hold on;
plot(time, double(EEGcleanEEG.data(czIdx, sampleRange, 1)), 'k');
drawBadPatches(gca, badIntervals, targetLatency, EEGraw.srate, ...
    windowStart, windowEnd);
xline(0, 'r--');
grid on;
xlabel('相对最后一个 code 32 的时间 (s)');
ylabel('Cz (uV)');
title('Cz：原始导入波形 vs 0.5-35 Hz 连续观察滤波波形');
legend({'原始','观察滤波'}, 'Location', 'best');

subplot(4,1,2);
if isempty(eogPlotIdx)
    text(0.02, 0.5, '没有识别到 EOG 通道', 'Units', 'normalized');
else
    hold on;
    for k = 1:numel(eogPlotIdx)
        plot(time, double(EEGeog.data(eogPlotIdx(k), sampleRange, 1)));
    end
    drawBadPatches(gca, badIntervals, targetLatency, EEGraw.srate, ...
        windowStart, windowEnd);
    xline(0, 'r--');
    legend(labels(eogPlotIdx), 'Location', 'best');
end
grid on;
xlabel('相对时间 (s)');
ylabel('EOG (uV)');
title('EOG：眼动参考信号');

subplot(4,1,3);
if isempty(emgPlotIdx)
    text(0.02, 0.5, '没有识别到 EMG 通道', 'Units', 'normalized');
else
    hold on;
    for k = 1:numel(emgPlotIdx)
        plot(time, double(EEGemg.data(emgPlotIdx(k), sampleRange, 1)));
    end
    drawBadPatches(gca, badIntervals, targetLatency, EEGraw.srate, ...
        windowStart, windowEnd);
    xline(0, 'r--');
    legend(labels(emgPlotIdx), 'Location', 'best');
end
grid on;
xlabel('相对时间 (s)');
ylabel('EMG (uV)');
title('EMG：肌肉活动参考信号');

subplot(4,1,4);
ylim([0 1]);
xlim([time(1), time(end)]);
drawBadPatches(gca, badIntervals, targetLatency, EEGraw.srate, ...
    windowStart, windowEnd);
xline(0, 'r--');
yticks([]);
grid on;
xlabel('相对时间 (s)');
title(sprintf('人工确认的连续伪迹区间；移除 IC：%s', ...
    mat2str(removedComponents)));

sgtitle([caseName, ' | 连续伪迹处理质控']);
exportgraphics(figureHandle, figureFile, 'Resolution', 150);
close(figureHandle);
end


function drawBadPatches(ax, intervals, targetLatency, srate, windowStart, windowEnd)
if isempty(intervals)
    return;
end

hold(ax, 'on');
for k = 1:size(intervals,1)
    overlapStart = max(intervals(k,1), windowStart);
    overlapEnd = min(intervals(k,2), windowEnd);
    if overlapEnd < overlapStart
        continue;
    end

    x1 = (overlapStart - targetLatency) / srate;
    x2 = (overlapEnd - targetLatency) / srate;
    yLimits = ylim(ax);
    patch(ax, [x1 x2 x2 x1], ...
        [yLimits(1) yLimits(1) yLimits(2) yLimits(2)], ...
        [1.0 0.75 0.75], 'FaceAlpha', 0.35, ...
        'EdgeColor', 'none', 'HandleVisibility', 'off');
end

lineObjects = findobj(ax, 'Type', 'line');
if ~isempty(lineObjects)
    uistack(lineObjects, 'top');
end
end
