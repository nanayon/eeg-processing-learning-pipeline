%% s01_eeglab_inventory_TWC_USA
% 【正式 EEGLAB 流程：第一步】
% 用 EEGLAB/BioSig 批量导入每个 EDF，并从 EEG 结构中建立数据字典。
% 每个 EDF 都通过 pop_biosig 进入 EEGLAB，后续分析使用同一种数据结构。
% 输出内容包括：文件名、通道数、采样点数、时长、采样率、事件数、
% 睡眠阶段、梦境体验标签、EOG/EMG 是否存在以及通道名称。

clearvars;
clc;

%% 1. 定位工程目录
% 当前脚本位于工程的 code 文件夹中，因此向上一级就是工程根目录。
thisFile = mfilename('fullpath');
codeDir = fileparts(thisFile);
projectRoot = fileparts(codeDir);
rawRoot = fullfile(projectRoot, 'raw', 'TWC_USA');
resultsDir = fullfile(projectRoot, 'results');

if ~isfolder(rawRoot)
    error('找不到原始数据目录：%s', rawRoot);
end
if ~isfolder(resultsDir)
    mkdir(resultsDir);
end

%% 2. 初始化 EEGLAB 和 BioSig
% EEGLAB 根目录必须加入 MATLAB 搜索路径，才能找到 eeglab.m。
eeglabRoot = 'E:\Application\Matlab\toolbox\eeglab2026.0.0';
addpath(eeglabRoot);

% nogui 只初始化 EEGLAB 和插件，不打开交互式窗口。
% 这适合 MCP 批量执行。
eeglab('nogui');

% 检查批处理导入函数是否可用。
if isempty(which('pop_biosig'))
    error('找不到 pop_biosig，请确认 BioSig 插件已经安装。');
end

%% 3. 读取 Records.csv
% Records.csv 是数据集附带的实验元数据表。
% 它提供梦境体验、最后睡眠阶段和受试者信息，
% 这些信息不能仅靠 EEG 波形自动推断出来。
records = readtable(fullfile(rawRoot, 'Records.csv'), ...
    'TextType', 'string', ...
    'VariableNamingRule', 'preserve');

%% 4. 搜索所有 EDF 文件
% 使用递归搜索，兼容 Data/PSG 等多层文件夹结构。
edfFiles = dir(fullfile(rawRoot, '**', '*.edf'));
nFiles = numel(edfFiles);

if nFiles == 0
    error('没有找到 EDF 文件：%s', rawRoot);
end

%% 5. 创建保存批量结果的表格
% 每一行对应一个 EDF 文件，每一列对应一个属性。
inventory = table('Size', [nFiles 16], ...
    'VariableTypes', {'string','double','double','double','double', ...
    'double','double','double','double','double','double','double', ...
    'string','string','string','string'}, ...
    'VariableNames', {'Filename','NumChannels','DataPoints','NumTrials', ...
    'DurationSeconds','SamplingRateHz','EventCount','NumEEGChannels', ...
    'LastSleepStage','Experience','SubjectID','CaseID','HasEOG','HasEMG', ...
    'SignalLabels','ImportStatus'});

%% 6. 用 EEGLAB 批量导入每个 EDF
% for 循环逐个处理文件，避免一次性把整个数据集载入内存。
for i = 1:nFiles
    filename = string(edfFiles(i).name);
    filepath = fullfile(edfFiles(i).folder, edfFiles(i).name);
    row = find(records.Filename == filename, 1);

    fprintf('[%02d/%02d] EEGLAB importing %s\n', ...
        i, nFiles, filename);

    try
        % pop_biosig 是 EEGLAB 的 BioSig 导入函数。
        % importevent='on'：把 Status 事件导入 EEG.event。
        % importannot='on'：如果有 EDF+ 注释，也一并导入。
        % blockepoch='off'：保持整段连续数据，不自动切成 1 秒小段。
        % rmeventchan='on'：事件提取后移除 Status 连续通道。
        EEG = pop_biosig(filepath, ...
            'importevent', 'on', ...
            'importannot', 'on', ...
            'blockepoch', 'off', ...
            'rmeventchan', 'on');

        % eeg_checkset 检查 EEGLAB 结构是否完整。
        EEG = eeg_checkset(EEG);

        % 从 EEGLAB 数据结构读取维度和时间信息。
        inventory.Filename(i) = filename;
        inventory.NumChannels(i) = EEG.nbchan;
        inventory.DataPoints(i) = EEG.pnts;
        inventory.NumTrials(i) = EEG.trials;
        inventory.DurationSeconds(i) = EEG.xmax - EEG.xmin;
        inventory.SamplingRateHz(i) = EEG.srate;
        inventory.EventCount(i) = numel(EEG.event);

        % 从 Records.csv 补充实验标签和受试者信息。
        if ~isempty(row)
            inventory.NumEEGChannels(i) = records.('Number of EEG channels')(row);
            inventory.LastSleepStage(i) = records.('Last sleep stage')(row);
            inventory.Experience(i) = records.Experience(row);
            inventory.SubjectID(i) = records.('Subject ID')(row);
            inventory.CaseID(i) = records.('Case ID')(row);
            inventory.HasEOG(i) = records.('Has EOG')(row);
            inventory.HasEMG(i) = records.('Has EMG')(row);
        end

        % EEG.chanlocs 中保存通道标签；拼接后存入一列文字。
        inventory.SignalLabels(i) = join(string({EEG.chanlocs.labels}), ', ');
        inventory.ImportStatus(i) = "OK";

        fprintf('       %d channels | %.1f s | %d events\n', ...
            EEG.nbchan, EEG.xmax - EEG.xmin, numel(EEG.event));

        % 清除当前文件的波形，避免批量运行时内存持续增长。
        clear EEG;
    catch ME
        % 单个文件出错时记录错误，并继续处理其他文件。
        inventory.Filename(i) = filename;
        inventory.ImportStatus(i) = "ERROR: " + string(ME.message);
        warning('导入 %s 失败：%s', filename, ME.message);
    end
end

%% 7. 保存 EEGLAB 盘点结果
% CSV 可以被 MATLAB、Excel 或 Python 继续使用。
outputFile = fullfile(resultsDir, 'TWC_USA_inventory_eeglab.csv');
writetable(inventory, outputFile);

fprintf('\nEEGLAB 批量盘点完成。\n');
fprintf('结果文件：%s\n', outputFile);

%% 8. 输出简要汇总
% 代码通常为：0=不确定，1=N1，2=N2，5=REM。
fprintf('\n最后睡眠阶段计数：\n');
disp(groupsummary(inventory, 'LastSleepStage'));

fprintf('导入状态计数：\n');
disp(groupsummary(inventory, 'ImportStatus'));
