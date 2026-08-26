# 数据获取说明

本目录只保留说明，不存放 EEG、报告或元数据文件。

当前学习数据：DREAM 数据库的 `TWC_USA` 数据集。请从[官方数据记录](https://bridges.monash.edu/articles/dataset/The_DREAM_database/22133105)进入最新版本，并按其中的 `Data URL` 和数据包协议获取。

本地建议结构：

```text
raw/TWC_USA/
├─ Data/PSG/*.edf
├─ Records.csv
├─ README.txt
└─ ExperimentalDescription.txt
```

数据包中的 `README.txt` 和 `ExperimentalDescription.txt` 必须先阅读；使用时以官方最新记录和原始协议为准。`raw/` 已被 `.gitignore` 排除，数据不得上传到本仓库。
