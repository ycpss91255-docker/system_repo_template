# system_repo_template

[![License](https://img.shields.io/badge/License-Apache--2.0-blue?style=flat-square)](./LICENSE)

多 repo 軟體系統的 **system repo 範本**：用「映像版本檔」管理整個系統的版本，用 [`just`](https://github.com/casey/just) 當統一入口。部署目標只需要 `just`、`docker`、`git`。

> 狀態：最小可運作範例。bot 自動升級與完整系統驗證 CI 尚未實作，見 [Issues](https://github.com/ycpss91255-docker/system_repo_template/issues)。

## 核心想法

```
sub-repo alpha ─┐
sub-repo beta  ─┼─ 各自 CI 產生 docker image ─→ registry
sub-repo gamma ─┘                                  ▲
                          system repo（本 repo）只記「用哪個版本的映像」
                          versions/ · compose.yaml · configs/ · justfile
```

- **sub-repo**：測到模組整合測試為止，產出映像，彼此不感知。
- **system repo**：把一組映像版本組成系統版本，跑完整系統驗證，打包成 release。不持有任何 sub-repo 的原始碼。

版本檔是純文字，`compose.yaml` 以 `image: ${REGISTRY}/alpha:${ALPHA_TAG}` 引用：

```
# versions/dev.env             # 追蹤最新，bot 持續更新
ALPHA_TAG=1.1.0
BETA_TAG=2.0.0
GAMMA_TAG=0.9.0
```

`versions/<x.y.z>.env` 是 release 版本檔，由 `just release` 從 `dev.env` 產生，**之後不再修改**。

## 快速開始

需求：`docker`（含 compose 外掛）、`just`、`git`、`curl`。

```
just                    # 列出所有指令
bash demo/run_demo.sh   # 端到端示範（本機 registry + 小映像），結束後自動清除
```

| 指令 | 作用 |
|---|---|
| `just up` / `just down` | 依 `versions/dev.env`（加上 `override.env`）啟動 / 停止整套 |
| `just bump <模組> <tag>` | 修改 `dev.env` 中某模組的版本（bot 使用） |
| `just release <x.y.z>` | 凍結 `dev.env` 為 release 版本檔並打 tag |
| `just deploy <release> [目標]` | 部署：先 pull 全部映像，成功才 `up` |
| `just version` | 顯示目前部署的 release 與實際映像 |

環境變數：`REGISTRY`（預設 `localhost:5555`，請改成你的 registry）、`TARGET`（預設 `target-01`）。

## 常用流程

**只改自己的模組**：在本機建置映像，建立 `override.env`（已被 `.gitignore` 忽略）：

```
ALPHA_TAG=dev-local     # 其他模組維持 dev.env 釘住的版本
```

**發版**：

```
just release 1.1.0      # 產生 versions/1.1.0.env、commit、打 tag v1.1.0
git push --tags
```

**部署與回滾**（部署目標上只做這兩步）：

```
git clone --branch v1.1.0 <system repo 網址>
just deploy 1.1.0 target-01      # 回滾：just deploy 1.0.0 target-01
```

## 已確定事項

| 項目 | 結論 |
|---|---|
| 版本鎖定 | release 釘 `x.y.z` tag（團隊規範：發布後不改）；測試可用以 commit SHA 為 tag 的映像 |
| 部署目標的依賴 | 只有 `just`、`docker`、`git`，不裝其他工具 |
| 跨模組開發 | 釘住多個映像，只改自己負責的模組 |
| system repo 的 PR | 一律跑完整系統驗證：模組對接 → system → simulator |
| 自動升級 | sub-repo 發布新映像後，由 bot 開升級 PR（[#1](https://github.com/ycpss91255-docker/system_repo_template/issues/1)、[#2](https://github.com/ycpss91255-docker/system_repo_template/issues/2)） |
| 多 repo 工作區工具 | 不使用（west、repo 等），原因見 Q&A |

## 文件

- [docs/qa.md](docs/qa.md)：討論過程的 Q&A，每條標明「已確定 / 已實測 / 待決定」，以及尚未涵蓋的事項
- [docs/tool-evaluation.md](docs/tool-evaluation.md)：多 repo 管理工具（mani、gitgrip、ripvcs、repo、west）的評估與實測

## 目錄結構

```
.
├── compose.yaml              各模組如何啟動
├── justfile                  統一入口
├── versions/dev.env          最新版本（release 檔由 just release 產生）
├── configs/<目標>/target.env  每個部署目標的設定（非機密）
├── demo/                     端到端示範與驗證
├── docs/                     Q&A、工具評估
└── LICENSE
```

## 授權

[Apache-2.0](./LICENSE)
