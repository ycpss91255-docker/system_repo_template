# system_repo_template

多 repo 軟體系統的 **system repo 範本**：用「映像版本檔」管理整個系統的版本，用 [`just`](https://github.com/casey/just) 當統一入口。部署目標只需要 `just`、`docker`、`git`。

> 狀態：最小可運作範例（第一版）。bot 自動化與完整系統驗證 CI 尚未實作，見 [Issues](../../issues)。

---

## 目錄

1. [決策摘要](#1-決策摘要)
2. [角色分工](#2-角色分工)
3. [版本模型](#3-版本模型)
4. [日常流程](#4-日常流程)
5. [快速開始](#5-快速開始)
6. [目錄結構](#6-目錄結構)
7. [示範驗證了什麼](#7-示範驗證了什麼)
8. [Q&A：討論過程與已確定事項](#8-qa討論過程與已確定事項)
9. [尚未涵蓋 / 未驗證](#9-尚未涵蓋--未驗證)
10. [附錄 A：多 repo 管理工具評估](#附錄-a多-repo-管理工具評估)

---

## 1. 決策摘要

| 項目 | 決策 |
|---|---|
| 模組切分 | 每個功能模組一個 repo，各自的 CI 產生自己的 docker image |
| system repo 持有什麼 | **版本檔**（各模組映像的 tag）、`compose.yaml`、各部署目標的設定、`justfile`。不持有任何 sub-repo 的原始碼 |
| 部署物 | docker image / container |
| 版本鎖定 | release 釘 **`x.y.z` tag**（團隊規範：tag 發布後不再改動）；測試階段可用「以 commit SHA 為 tag」的映像 |
| 部署目標的依賴 | 只有 `just`、`docker`（含 compose 外掛）、`git`，不裝 Python、west 等其他工具 |
| 跨模組開發 | 釘住多個映像，只針對自己負責的模組開發（見 §4.2） |
| system repo 的 PR | 一律跑**完整系統驗證**：模組對接 → system → simulator |
| 自動升級 | sub-repo 發布新映像後，由 bot 在 system repo 開「升級版本」PR（見 Issues） |
| 多 repo 工作區工具 | **不使用**（west、repo 等）。評估過程見 [Q&A](#工具評估) 與 [附錄 A](#附錄-a多-repo-管理工具評估) |

## 2. 角色分工

```
                       ┌─────────────────────────────────────────┐
                       │ system repo（本 repo）                  │
                       │  versions/dev.env     ← 最新版本，bot 持續更新
                       │  versions/<x.y.z>.env ← release，凍結後不改
                       │  compose.yaml / configs/<目標>/ / justfile
                       └───────────────▲─────────────────────────┘
                                       │ 只引用「映像 tag」，不認識原始碼
        ┌──────────────┬───────────────┴──────┬───────────────┐
   sub-repo alpha   sub-repo beta        sub-repo gamma      ...
   單元 / 整合測試   單元 / 整合測試       單元 / 整合測試
   → 推送映像        → 推送映像            → 推送映像
```

- **sub-repo**：只負責自己的功能，測到「模組整合測試」為止，產出 image，彼此不感知。
- **system repo**：把一組映像版本組成「系統版本」，跑系統層級驗證，打包成 release。

## 3. 版本模型

`versions/*.env` 是純文字，一行一個模組：

```
ALPHA_TAG=1.1.0
BETA_TAG=2.0.0
GAMMA_TAG=0.9.0
```

`compose.yaml` 以 `image: ${REGISTRY}/alpha:${ALPHA_TAG}` 引用。換版本只需要換檔案。

| 檔案 | 用途 | 可否修改 |
|---|---|---|
| `versions/dev.env` | 開發與 CI 用，追蹤最新；bot 會持續更新 | 可 |
| `versions/<x.y.z>.env` | release 版本，由 `just release` 從 `dev.env` 複製而來 | **不可**（`just release` 會拒絕覆蓋） |

`just release` 另有保護：`dev.env` 內只要有一個 tag 不是 `x.y.z`（例如 `dev-local` 或 SHA tag）就拒絕發版。

## 4. 日常流程

### 4.1 bot 自動升級（尚未實作，見 Issues）

1. 某個 sub-repo 發布新映像（例如 `alpha:1.4.0`）。
2. bot 在 system repo 開 PR，內容是 `just bump alpha 1.4.0`（修改 `versions/dev.env`）。
3. PR 觸發完整系統驗證（模組對接 → system → simulator）。
4. 通過後人工合併。

### 4.2 開發者只改自己的模組

在本機建置自己的映像，建立 `override.env`（已列入 `.gitignore`），只寫要替換的那一項：

```
ALPHA_TAG=dev-local
```

`just up` 會用 `dev.env` 加上 `override.env`：其他模組維持釘住的版本，只有 alpha 是你剛建的版本。

### 4.3 發版

```
just release 1.1.0     # 把 dev.env 複製成 versions/1.1.0.env、commit、打 tag v1.1.0
git push --tags
```

### 4.4 部署與回滾

部署目標上只做兩件事：

```
git clone --branch v1.1.0 <system repo 網址>
just deploy 1.1.0 target-01
```

- `deploy` 會**先把所有映像 pull 成功**才 `up`；任何一個映像拉不到，就不會動到正在跑的容器。
- 回滾：`just deploy 1.0.0 target-01`（舊 release 的版本檔仍在 repo 內）。
- `just version` 顯示目前部署的 release、目標名稱與實際映像。

## 5. 快速開始

需求：`docker`（含 compose 外掛）、`just`、`git`、`curl`。

```
just                    # 列出所有指令
bash demo/run_demo.sh   # 端到端示範（本機 registry + 小映像），結束後自動清除
```

| 指令 | 作用 |
|---|---|
| `just up` / `just down` | 本機依 `versions/dev.env`（加上 `override.env`）啟動 / 停止整套 |
| `just bump <模組> <tag>` | 修改 `dev.env` 中某模組的版本（bot 使用） |
| `just release <x.y.z>` | 凍結 `dev.env` 為 release 版本檔並打 tag |
| `just deploy <release> [目標]` | 部署（先 pull 再 up） |
| `just version` | 顯示目前部署的版本 |

環境變數：`REGISTRY`（預設 `localhost:5555`，實際使用請改成你的 registry）、`TARGET`（預設 `target-01`）。

## 6. 目錄結構

```
.
├── compose.yaml             各模組如何啟動
├── justfile                 統一入口
├── versions/
│   └── dev.env              最新版本（release 檔由 just release 產生）
├── configs/
│   ├── target-01/target.env 每個部署目標的設定（非機密）
│   └── target-02/target.env
├── demo/
│   ├── Dockerfile           示範用的小映像
│   └── run_demo.sh          端到端示範與驗證
└── .gitignore               忽略 override.env、.deployed-release
```

## 7. 示範驗證了什麼

`demo/run_demo.sh` 用 docker 啟動本機 registry 並建置小映像，模擬整個流程，全部項目通過：

- `just up` 依 `dev.env` 啟動；`just bump` 只改指定模組。
- `override.env` 只替換一個模組，其他維持 `dev.env`。
- `just release`：含非 `x.y.z` tag 時拒絕、成功時產生版本檔與 tag、重複發同版本被拒。
- 部署目標只用 `git clone`（到 tag）加 `just deploy`，且本機沒有映像時會從 registry 拉取。
- 升級與回滾；`just version` 顯示實際映像。
- **失敗保護**：新版本有映像不存在時，`deploy` 失敗且現有容器沒有被重建。
- 不同部署目標載入各自的設定。

---

## 8. Q&A：討論過程與已確定事項

以下整理設計討論中的問題與結論（討論日期：2026-11-13）。每條標明是「已確定」（團隊決定或已實測），還是「待決定／未驗證」。

### 架構與範圍

**Q：這個 repo 是什麼，不是什麼？**
A（已確定）：它負責「依清單組裝整個系統、跑系統層級驗證、打包 release」，不寫具體業務程式碼。sub-repo 只對外暴露乾淨的介面，彼此不感知。

**Q：system repo 為什麼不持有 sub-repo 的原始碼？**
A（已確定）：每個 sub-repo 的 CI 自己產生映像，system repo 只需要知道「用哪個版本的映像」。原始碼不需要出現在這裡。

**Q：sub-repo 要測到什麼程度？**
A（已確定）：單元測試與模組整合測試。系統層級的驗證只在 system repo 進行。

### 版本與發佈

**Q：版本要用 tag 還是 SHA？**
A（已確定）：release 一律釘 `x.y.z` tag，這是團隊規範，發布後不修改。SHA 主要用在測試階段（以 commit SHA 為 tag 的映像）。`just release` 會拒絕含非 `x.y.z` tag 的 `dev.env`。

**Q：release 版本檔發布後可以修改嗎？**
A（已確定）：不可以。`just release` 不會覆蓋既有版本檔；要修正就發新版本。

**Q：為什麼不用映像 digest 來鎖定？**
A（已確定）：團隊規範 tag 不可變，所以直接用 tag 即可。若日後 registry 無法保證 tag 不可覆寫，再重新評估。

**Q：system repo 的 release 下載時，會連同其他 repo 一起帶下來嗎？**
A（已確定）：不會。git tag 或 release 的原始碼壓縮檔只含 system repo 自己的檔案；各模組由 registry 以映像提供。討論初期曾評估過「離線部署包」（把各 repo 打包成 tarball），改為映像部署後就不需要了。

**Q：要怎麼追溯目前部署的是什麼版本？**
A（已確定）：system repo 的 tag 加上各模組的映像 tag。`just version` 會顯示目前部署的 release 與實際映像。

### 部署

**Q：部署目標需要安裝什麼？**
A（已確定）：只有 `just`、`docker`、`git`，不裝其他依賴。（`docker compose` 是 docker 的外掛，通常隨 docker 一起安裝，但尚未在實際的目標環境驗證。）

**Q：部署流程是什麼？**
A（已確定並實測）：`git clone --branch <tag>` 之後 `just deploy <release> <目標>`。`deploy` 先把所有映像 pull 成功才 `up`。

**Q：部署中途失敗會怎樣？怎麼回滾？**
A：已實測：新版本有映像不存在時，`deploy` 失敗且現有容器沒有被重建。回滾就是 `just deploy <舊 release>`，已實測。斷網、中途中斷等其他情境**尚未驗證**。

**Q：每個部署目標的設定與機密怎麼處理？**
A：設定放 `configs/<目標>/`（非機密），已實作。機密不進 git，建議放在目標本機檔案或 docker secrets，**尚未決定**。

### 開發與 CI

**Q：跨模組開發要怎麼做？**
A（已確定並實測）：釘住多個映像，只針對自己負責的模組開發。在本機建置自己的映像，用 `override.env` 只替換那一項。

**Q：system repo 的 PR 要驗證什麼？**
A（已確定）：一律跑完整系統驗證：模組對接 → system → simulator。細節見 [Issue #3](../../issues/3)。

**Q：sub-repo 更新後，怎麼反映到 system repo？**
A（已確定）：由 bot 開「升級版本」PR（修改 `dev.env`），PR 觸發完整系統驗證，通過後人工合併。討論中也提過由 bot 開 issue 通知，結論是以 PR 為主。實作與策略見 [Issue #1](../../issues/1)、[Issue #2](../../issues/2)，**尚未實作**。

### 工具評估

**Q：為什麼不用 west、repo 這類多 repo 管理工具？**
A（已確定）：這類工具的用途是把多個 repo 的**原始碼**抓到同一個工作區。本架構的部署物是映像，各模組自己建置；跨模組開發也是釘映像，不需要抓其他模組的原始碼。所以不需要。

**Q：如果日後真的需要原始碼工作區，選哪個？**
A：建議 `west`。實測它的清單用 YAML，tag / SHA / branch 可直接寫，可不依賴 Zephyr 獨立使用。使用時要注意三點：
1. `west manifest --freeze` 凍結的是 `manifest-rev`，不是目前 HEAD；
2. 專案的 submodule 若用相對 URL，需要把清單中的 remote 命名為 `origin`；
3. west 沒有「複製或連結檔案」與「跨 repo 開分支」的功能，可由 `just` 補上。

**Q：為什麼不選 Rust / Go 寫的現成工具？**
A（已查證）：`mani` 不支援 tag / commit 鎖定；`gitgrip` 的 Rust 版已進入維護模式，主力轉為 Python；`ripvcs` 最後 commit 是 2025-06，鎖定行為文件不明。詳見附錄。

**Q：Google 的 `repo` 為什麼不選？**
A：它能用，且實測通過鎖版本流程。不選的原因是：清單為 XML；project 的 tag 必須寫 `refs/tags/` 前綴；2026-11-13 查閱其 issue tracker，開放中有 184 個 issue（其中 126 個是 bug，只讀標題、沒有逐一檢視內容），含數筆 sync 卡住的回報。

**Q：submodule 能不能用？**
A（已實測）：在本架構不受影響：sub-repo 的 CI 自己 `git clone --recurse-submodules` 即可。west 對相對 URL 的 submodule 的限制見附錄。

### 其他

**Q：`just` 的角色是什麼？**
A（已確定）：統一的使用者介面。底下目前是 `docker compose` 與 shell；日後底層實作若要更換，使用者看到的指令不變。

---

## 9. 尚未涵蓋 / 未驗證

- bot 自動升級 PR（[#1](../../issues/1)、[#2](../../issues/2)）、完整系統驗證 CI（[#3](../../issues/3)）：尚未實作。
- 斷網、中途失敗的更多情境，只驗證了「映像不存在」這一種。
- 機密的管理方式尚未決定。
- 範例用本機 registry 與 `localhost:5555`；真實 registry 的認證流程未涵蓋。
- 示範只在 Linux + docker compose v5 + just 1.x 上跑過。
- 尚未指定授權條款。

---

## 附錄 A：多 repo 管理工具評估

評估日期：2026-11-13。當時的需求是「通用（不綁特定領域框架）、能鎖版本、能批次操作」，語言偏好 Rust/Go 但以功能優先。後來確認部署物是映像、跨模組開發也是釘映像，這類工具就用不到了；以下記錄當時的查證，供日後需求改變時參考。

### A.1 候選工具

| 工具 | 語言 | 結論 |
|---|---|---|
| mani | Go | 文件中專案只有 `branch:` 欄位，沒有 tag / commit 鎖定，也沒有凍結指令 |
| gitgrip | Rust | Rust 版（gr1）已進入維護模式，主力轉為 Python 寫的 gr2（alpha）；一般 repo 的 revision 能否填 SHA 文件未說明 |
| ripvcs | Go | 最後 commit 為 2025-06；SHA 鎖定與 export 行為文件不明 |
| Google `repo` | Python | 實測通過（見 A.2） |
| west | Python | 實測通過（見 A.2） |

### A.2 `repo` 與 `west` 的實測（容器內，repo launcher 2.71、west 1.5.0）

兩者都通過：branch 追蹤、tag 鎖定、完整 SHA 鎖定、凍結成鎖定清單、上游前進後用鎖定清單還原、`forall`、有未提交變更時拒絕覆蓋並保留變更。

需要注意的差異：

- **`repo`**：清單是 XML；project 的 `revision` 寫裸 tag 名（`v1.0`）會失敗，必須寫 `refs/tags/v1.0`；縮短的 SHA 不支援（來自上游 issue 回報，未實測）。`repo manifest -r` 凍結的是**目前 HEAD**。
- **`west`**：清單是 YAML，tag / SHA / branch 直接寫。`west manifest --freeze` 凍結的是 **`manifest-rev`（遠端 revision 解析出的 SHA），不是目前 HEAD**，專案內有未推送的本地 commit 時兩者不同，用它之前要先確認 HEAD 等於 `manifest-rev` 且無髒檔。
- **`west` 與 submodule**：submodule 用絕對 URL 可正常運作；用**相對 URL** 時，`west update` 會失敗，因為 west 把遠端命名為清單中的名稱，而 git 解析相對路徑時固定找名為 `origin` 的遠端。把清單中的 remote 命名為 `origin` 即可繞過。上游 issue [west#545](https://github.com/zephyrproject-rtos/west/issues/545) 自 2021 年起仍開著，對應的修復 PR #546 已關閉未合併。

---

## 授權

尚未指定。
