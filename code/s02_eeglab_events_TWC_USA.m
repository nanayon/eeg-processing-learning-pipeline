%% s02_eeglab_events_TWC_USA
% 【正式 EEGLAB 流程：第二步】
% 用 EEGLAB/BioSig 批量导入 EDF，并从 EEG.event 提取实验事件。
%
% 本脚本不直接读取 Status 原始波形。
% 它使用 pop_biosig 完成：Status 通道 -> EEGLAB 事件结构 EEG.event。
%
% 输出每个事件的文件名、病例号、受试者号、事件类型、发生时间、
% 数学题候选标签和事件类别。

clearvars;
clc;

%% 1. 定位工程目录
thisFile = mfilename('fullpath');
codeDir = fileparts(thisFile);
projectRoot = fileparts(codeDir);
rawRoot = fullfile(projectRoot, 'raw', 'TWC_USA');
resultsDir = fullfile(projectRoot, 'results');
% 让本脚本可以调用项目中的事件含义映射函数。
addpath(codeDir);

%% 2. 初始化 EEGLAB/BioSig
% 加入 EEGLAB 根目录，并初始化所有插件。
eeglabRoot = 'E:\Application\Matlab\toolbox\eeglab2026.0.0';
addpath(eeglabRoot);
eeglab('nogui');

if isempty(which('pop_biosig'))
    error('找不到 pop_biosig，请确认 BioSig 插件已经安装。');
end

%% 3. 读取 Records.csv 和 EDF 文件列表
% Records.csv 用于补充病例号和受试者号等实验信息。
records = readtable(fullfile(rawRoot, 'Records.csv'), ...
    'TextType', 'string', ...
    'VariableNamingRule', 'preserve');

% 递归搜索所有 EDF 文件。
edfFiles = dir(fullfile(rawRoot, '**', '*.edf'));

%% 4. 准备事件结果暂存区
% 每一行最终代表 EEG.event 中的一个事件。
rows = cell(0, 10);

%% 5. 用 EEGLAB 导入并读取 EEG.event
% 外层循环逐个处理 EDF 文件。
for i = 1:numel(edfFiles)
    filename = string(edfFiles(i).name);
    filepath = fullfile(edfFiles(i).folder, edfFiles(i).name);
    recordRow = find(records.Filename == filename, 1);

    fprintf('[%02d/%02d] EEGLAB reading events from %s\n', ...
        i, numel(edfFiles), filename);

    try
        % 通过 EEGLAB/BioSig 导入连续 EDF。
        % importevent='on' 是把实验事件写入 EEG.event 的关键。
        EEG = pop_biosig(filepath, ...
            'importevent', 'on', ...
            'importannot', 'on', ...
            'blockepoch', 'off', ...
            'rmeventchan', 'on');

        % 检查 EEG 结构，保证 event 字段可以安全使用。
        EEG = eeg_checkset(EEG);

        % 遍历当前文件中的每一个 EEGLAB 事件。
        for j = 1:numel(EEG.event)
            % 事件类型可能是数字、字符或字符串，统一转为 string。
            rawType = string(EEG.event(j).type);

            % 尝试转成数字，用于识别 1–20、23、29 等代码。
            rawNumericCode = str2double(rawType);

            % BioSig 可能把整数事件读成 1.9995、29.0000 等浮点数。
            % 这些小数误差不是新的事件代码，因此统一四舍五入。
            code = round(rawNumericCode);

            % 根据 ExperimentalDescription.txt 对代码进行分类。
            if isnan(rawNumericCode)
                category = "non-numeric event";
                isMathCandidate = false;
            elseif code == 23
                category = "TLR light cue";
                isMathCandidate = false;
            elseif code == 29
                category = "TLR auditory cue";
                isMathCandidate = false;
            elseif code == 32
                category = "new script";
                isMathCandidate = false;
            elseif code == 64
                category = "volume down";
                isMathCandidate = false;
            elseif code == 65
                category = "volume up";
                isMathCandidate = false;
            elseif code >= 1 && code <= 20
                category = "math problem candidate";
                isMathCandidate = true;
            else
                category = "other numeric event";
                isMathCandidate = false;
            end

            % EEGLAB latency 以采样点表示；除以采样率得到发生时间。
            timeSeconds = (double(EEG.event(j).latency) - 1) / EEG.srate;

            if isempty(recordRow)
                caseID = NaN;
                subjectID = NaN;
            else
                caseID = records.('Case ID')(recordRow);
                subjectID = records.('Subject ID')(recordRow);
            end

            % 把数字代码转换为可读的实验含义。
            eventMeaning = twcUSA_event_meaning(code, caseID);

            % 保存当前事件的一行结果。
            rows(end+1, :) = {filename, caseID, subjectID, ...
                rawType, code, timeSeconds, category, ...
                eventMeaning, isMathCandidate, numel(EEG.event)}; %#ok<SAGROW>
        end

        % 当前文件处理完后清除波形，避免内存持续增长。
        clear EEG;
    catch ME
        % 一个文件异常时记录警告，但不让整个批处理停止。
        warning('读取 %s 的事件失败：%s', filename, ME.message);
    end
end

%% 6. 整理并保存事件表
% 把暂存的 cell 数组转换成带列名的 MATLAB table。
eventTable = cell2table(rows, 'VariableNames', ...
    {'Filename','CaseID','SubjectID','RawType','NumericCode', ...
    'TimeSeconds','Category','EventMeaning','IsMathCandidate', ...
    'EventsInFile'});

% 按文件名和时间排序，恢复实验事件发生的时间顺序。
if ~isempty(eventTable)
    eventTable = sortrows(eventTable, {'Filename','TimeSeconds'});
end

% 保存为 CSV，供后续 EOG 事件锁定脚本使用。
outputFile = fullfile(resultsDir, 'TWC_USA_events_eeglab.csv');
writetable(eventTable, outputFile);

fprintf('\nEEGLAB 事件扫描完成。\n');
fprintf('事件表：%s\n', outputFile);
fprintf('事件总数：%d\n', height(eventTable));

if ~isempty(eventTable)
    % 统计每一种数字事件代码出现的次数。
    fprintf('\n数字事件代码汇总：\n');
    numericEvents = eventTable(~isnan(eventTable.NumericCode), :);
    % 同一代码在不同案例中可能对应不同数学表达式，
    % 因此按“代码 + 含义”一起汇总，避免只看数字产生歧义。
    disp(groupsummary(numericEvents, {'NumericCode','EventMeaning'}));

    fprintf('数学题候选事件数：%d\n', ...
        sum(eventTable.IsMathCandidate));
end
