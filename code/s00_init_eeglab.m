%% s00_init_eeglab
% 【本脚本的任务】
% 在 MATLAB/MCP 会话中初始化 EEGLAB 和 BioSig。
% 这样后续脚本就可以调用 EEGLAB 的 pop_biosig、eeg_checkset、
% pop_epoch 和 pop_saveset 等函数，而不需要手动点击菜单。

clearvars;
clc;

eeglabRoot = 'E:\Application\Matlab\toolbox\eeglab2026.0.0';

if ~isfolder(eeglabRoot)
    error('找不到 EEGLAB 安装目录：%s', eeglabRoot);
end

%% 2. 把 EEGLAB 根目录加入 MATLAB 搜索路径
% MATLAB 只有在搜索路径中，才能找到 eeglab.m。
addpath(eeglabRoot);

%% 3. 以无图形界面方式启动 EEGLAB
eeglab('nogui');

%% 4. 检查关键函数是否已经可以调用
fprintf('EEGLAB 主函数：%s\n', which('eeglab'));
fprintf('BioSig 导入函数：%s\n', which('pop_biosig'));
fprintf('EEGLAB 数据检查函数：%s\n', which('eeg_checkset'));

fprintf('\nEEGLAB 初始化完成。\n');
