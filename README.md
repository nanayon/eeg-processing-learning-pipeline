# EEG Processing Learning Pipeline

一个基于 MATLAB + EEGLAB 的 EEG 处理学习仓库，当前以 DREAM 数据库中的 `TWC_USA` 数据包为学习对象。

> **用途声明**
>
> 这是一个面向 EEG 处理初学者的个人学习项目，目标是理解 EEG processing pipeline、相关概念和工具的基本用法。它不是正式研究项目、临床工具、生产系统或可直接用于实际结论的分析流程。
>
> 本仓库中的代码、数据说明和论文链接均用于个人学习。数据和论文不是我的原创数据或论文，也不代表我开展了相关原始研究；相关论文仅作为学习来源和背景阅读材料。

## 仓库目的

- 练习从 EDF 导入到 EEG 检查、事件整理、滤波、分段、特征提取和质量控制的基本流程。
- 熟悉 MATLAB、EEGLAB、BioSig 以及连续 EEG 与 epoch 数据之间的关系。
- 通过多个小脚本比较“看懂数据”“画出数据”和“做基础分析”之间的区别。
- 保持一个可以继续扩充其他公开数据集的学习型小项目。

## 当前包含的学习项目

当前 `s03`–`s06` 主要以 `case07_sub106` 为示例；`s01` 和 `s02` 面向整个 `TWC_USA` 数据包。

| 文件 | 学习项目 / pipeline | 重点 |
| --- | --- | --- |
| `code/s00_init_eeglab.m` | EEGLAB 环境初始化 | 加载 EEGLAB 与 BioSig，检查关键函数是否可用 |
| `code/s01_eeglab_inventory_TWC_USA.m` | 批量数据清点 | 导入 EDF，读取通道/采样率/时长/事件，并与 `Records.csv` 元数据合并 |
| `code/s02_eeglab_events_TWC_USA.m` | 事件提取与解释 | 读取 `EEG.event`，规范化事件编码、时间单位和事件含义 |
| `code/s03_eeglab_case07_analysis.m` | 单案例基础分析 | 以 code 32 为参考事件，做 `[-10, 10]` 秒 epoch、EOG/EMG 特征和 Cz 频谱分析 |
| `code/s04_eeglab_case07_full_overview.m` | 连续记录总览 | 在不分段的情况下查看整段信号、事件位置和不同类型通道 |
| `code/s05_matlab_plot_compare_case07.m` | 绘图工具比较 | 比较 EEGLAB `eegplot` 与 MATLAB 原生绘图；主要用于理解显示方式，不是统计分析 |
| `code/s06_eeglab_artifact_preprocessing.m` | 伪迹与 ICA 预处理 | 检测高幅值、跳变、平直区间，使用 ICA 辅助识别 EOG/EMG 成分，并进行人工复核后再 epoch |
| `code/twcUSA_event_meaning.m` | 事件字典辅助函数 | 将 TWC_USA 的数字事件编码映射为可读含义 |

概念上的学习路径如下：

```text
s00 环境初始化
   ├─ s01 批量清点 ── s02 事件整理
   └─ case07 学习分支：
         s03 基础特征/频谱
         s04 连续数据总览
         s05 EEGLAB 与 MATLAB 绘图比较
         s06 伪迹检测、ICA、清理后 epoch
```

这些脚本是互相补充的学习练习，不构成经过验证的通用分析 pipeline。

## 学习目标

完成这一小项目后，希望能够：

- 看懂 EEGLAB 的 `EEG` 数据结构、通道信息、事件信息和 `.set/.fdt` 文件关系。
- 理解连续数据、事件（event）和以事件为中心的 epoch 之间的转换。
- 理解不同信号类型为什么需要不同滤波范围：EEG、EOG 和 EMG 的关注频段不同。
- 理解事件 latency、采样点、秒、事件编码和外部元数据之间的对应关系。
- 理解功率谱密度（PSD）、dB 与线性功率、频带积分，以及“可视化”与“数值分析”的区别。
- 理解伪迹检测、坏区间、ICA、成分相关性和人工复核各自能解决什么问题、不能解决什么问题。
- 熟悉数据来源、协议、目录结构、输出隔离和不把数据提交到 Git 的基本习惯。

## 涉及的知识点

### 1. MATLAB 与 EEGLAB 基础

- MATLAB 脚本与函数、`fullfile`、批处理循环、异常处理和结果保存。
- EEGLAB 初始化、`EEG` 结构、`eeg_checkset`、通道标签和事件结构。
- `pop_biosig`、`pop_epoch`、`pop_resample`、`pop_runica`、`pop_subcomp`、`eegplot`、`spectopo` 等常用工具。

### 2. 数据导入与事件

- EDF/PSG 数据导入以及 BioSig 对 `Status` 通道事件的读取。
- 事件编码到事件含义的映射，例如 TLR cue、new script、音量变化和 math task。
- 采样点 latency 转换为秒、批量事件表整理，以及与 `Records.csv` 的元数据连接。

### 3. 信号处理

- 连续 EEG 与 epoch 的区别，以及“先在连续数据上滤波，再按事件分段”的流程。
- EEG `0.5–35 Hz`、EOG `0.1–15 Hz`、EMG `10–100 Hz` 这类按信号类型设置参数的思路。
- 以参考事件建立 `[-10, 10]` 秒窗口、基线区间和时间对齐。
- EOG 的峰峰值、阈值候选活动，EMG 的 RMS，以及这些指标的解释边界。
- `spectopo` 频谱、delta/theta/alpha/sigma/beta 频带和 PSD 积分；区分平均 dB PSD 与线性功率。

### 4. 可视化与质量控制

- 使用事件叠加、通道选择、归一化显示和显示用重采样浏览长时间连续记录。
- 比较 EEGLAB 交互式 `eegplot` 和 MATLAB 原生绘图。
- 高幅值、跳变、平直区间、疑似 EDF 转换尾部和 epoch 质量控制。
- ICA 分解、EOG/EMG 与独立成分的相关性、候选成分与人工判断的关系。
- 记录阈值、保留 event latency、保存 QC 日志，以及让处理结果可追溯。

## 运行环境与工具

- Windows（当前脚本中的路径写法以 Windows 为主）。
- MATLAB；建议使用与本机 EEGLAB 兼容的版本。
- EEGLAB；当前脚本示例使用本机的 `eeglab2026.0.0` 安装。
- BioSig，用于 `pop_biosig` EDF 导入。
- EEGLAB 自带的滤波、epoch、ICA、绘图和频谱相关函数；部分功能可能依赖 EEGLAB 的对应插件或 MATLAB 工具箱。

运行前请打开 `s00`–`s06` 中的 `eeglabRoot`，把示例中的本地路径改成自己的 EEGLAB 安装路径。当前代码里保留了开发机路径，因此不能保证克隆后直接运行。

## 如何运行

1. 从官方 DREAM 数据页面获取你有权使用的 `TWC_USA` 数据包，并阅读数据包中的 `README.txt` 与 `ExperimentalDescription.txt`。
2. 将数据放在本地项目目录的 `raw/TWC_USA/` 下；代码期望 EDF 位于 `raw/TWC_USA/Data/PSG/`，并读取 `raw/TWC_USA/Records.csv`。
3. 修改脚本中的 `eeglabRoot`，将 MATLAB 当前文件夹设为仓库根目录。
4. 建议按下面顺序学习运行：

```matlab
run(fullfile('code', 's00_init_eeglab.m'));
run(fullfile('code', 's01_eeglab_inventory_TWC_USA.m'));
run(fullfile('code', 's02_eeglab_events_TWC_USA.m'));
run(fullfile('code', 's03_eeglab_case07_analysis.m'));
run(fullfile('code', 's04_eeglab_case07_full_overview.m'));
run(fullfile('code', 's05_matlab_plot_compare_case07.m'));
s06_eeglab_artifact_preprocessing;
```

`s06` 默认将 ICA 成分作为候选结果交给人工检查，不会自动删除建议成分；请先理解脚本参数和输出，再决定是否修改。

## 数据集与协议

当前数据来源是 Monash University DREAM（Dream EEG and Mentation）数据库中的 `TWC_USA` 数据集。请在官方数据库的最新版本中查找该数据集及其 `Data URL`：

- [DREAM database（官方数据记录）](https://bridges.monash.edu/articles/dataset/The_DREAM_database/22133105)
- [DREAM database 论文](https://doi.org/10.1038/s41467-025-61945-1)

本仓库**不上传原始数据、报告、个人/实验元数据、处理结果或由数据生成的图表**。数据只应保存在本地被 `.gitignore` 排除的目录中。

随数据包提供的 `README.txt` 说明 DREAM 数据通常采用 CC BY 4.0，除非实验说明另有规定；实际使用时必须同时阅读并遵守数据包中的 `README.txt`、`ExperimentalDescription.txt`、官方数据页面及其最新条款。`data/README.md` 只提供获取和放置数据的简要说明，不替代原始协议。

## 论文与外部学习来源

以下内容是外部学习材料，不是我的论文，也不是本仓库的研究来源；本项目不声称复现这些论文的研究结论：

1. Konkoly et al. (2021), *Real-time dialogue between experimenters and dreamers during REM sleep*, Current Biology. [DOI](https://doi.org/10.1016/j.cub.2021.01.026)
2. Wong et al. (2025), *A dream EEG and mentation database*, Nature Communications. [DOI](https://doi.org/10.1038/s41467-025-61945-1)
3. Delorme & Makeig (2004), *EEGLAB: an open source toolbox for analysis of single-trial EEG dynamics*, Journal of Neuroscience Methods. [DOI](https://doi.org/10.1016/j.jneumeth.2003.10.009)

## 目录建议

```text
TWC_USA/
├─ code/                         # 需要上传的 MATLAB 学习代码
├─ data/README.md                # 数据来源与本地放置说明，不含数据
├─ TWC_USA.prj                  # MATLAB Project 入口文件
├─ README.md
├─ raw/                          # 本地原始数据，忽略，不上传
├─ results/                      # 本地处理结果，忽略，不上传
├─ figures/                      # 本地图表，忽略，不上传
├─ logs/                         # 本地日志，忽略，不上传
├─ report/                       # 可选的个人学习笔记
└─ resources/                    # MATLAB 项目生成元数据，忽略
```

## 当前边界与后续扩展

目前项目聚焦于单个示例案例和基础处理概念，没有组水平统计、机器学习训练、严谨的交叉验证、临床判断或生产级参数管理。脚本中的阈值和频带是学习用途的示例，需要结合数据说明、实验问题和正式方法学重新评估。

后续可以在保持“数据不入库”的前提下扩展：统一配置文件、增加其他 DREAM 数据集适配器、补充自动化 QC/测试、增加组水平分析，并记录每个数据集自己的协议与引用信息。
