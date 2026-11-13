# Q&A：討論過程與已確定事項

以下整理設計討論中的問題與結論（討論日期：2026-11-13）。每條標明是「已確定」（團隊決定或已實測），還是「待決定／未驗證」。

## 架構與範圍

**Q：這個 repo 是什麼，不是什麼？**
A（已確定）：它負責「依清單組裝整個系統、跑系統層級驗證、打包 release」，不寫具體業務程式碼。sub-repo 只對外暴露乾淨的介面，彼此不感知。

**Q：system repo 為什麼不持有 sub-repo 的原始碼？**
A（已確定）：每個 sub-repo 的 CI 自己產生映像，system repo 只需要知道「用哪個版本的映像」。原始碼不需要出現在這裡。

**Q：sub-repo 要測到什麼程度？**
A（已確定）：單元測試與模組整合測試。系統層級的驗證只在 system repo 進行。

## 版本與發佈

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

## 部署

**Q：部署目標需要安裝什麼？**
A（已確定）：只有 `just`、`docker`、`git`，不裝其他依賴。（`docker compose` 是 docker 的外掛，通常隨 docker 一起安裝，但尚未在實際的目標環境驗證。）

**Q：部署流程是什麼？**
A（已確定並實測）：`git clone --branch <tag>` 之後 `just deploy <release> <目標>`。`deploy` 先把所有映像 pull 成功才 `up`。

**Q：部署中途失敗會怎樣？怎麼回滾？**
A：已實測：新版本有映像不存在時，`deploy` 失敗且現有容器沒有被重建。回滾就是 `just deploy <舊 release>`，已實測。斷網、中途中斷等其他情境**尚未驗證**。

**Q：每個部署目標的設定與機密怎麼處理？**
A：設定放 `configs/<目標>/`（非機密），已實作。機密不進 git，建議放在目標本機檔案或 docker secrets，**尚未決定**。

## 開發與 CI

**Q：跨模組開發要怎麼做？**
A（已確定並實測）：釘住多個映像，只針對自己負責的模組開發。在本機建置自己的映像，用 `override.env` 只替換那一項。

**Q：system repo 的 PR 要驗證什麼？**
A（已確定）：一律跑完整系統驗證：模組對接 → system → simulator。細節見 [Issue #3](https://github.com/ycpss91255-docker/system_repo_template/issues/3)。

**Q：sub-repo 更新後，怎麼反映到 system repo？**
A（已確定）：由 bot 開「升級版本」PR（修改 `dev.env`），PR 觸發完整系統驗證，通過後人工合併。討論中也提過由 bot 開 issue 通知，結論是以 PR 為主。實作與策略見 [Issue #1](https://github.com/ycpss91255-docker/system_repo_template/issues/1)、[Issue #2](https://github.com/ycpss91255-docker/system_repo_template/issues/2)，**尚未實作**。

## 工具評估

**Q：為什麼不用 west、repo 這類多 repo 管理工具？**
A（已確定）：這類工具的用途是把多個 repo 的**原始碼**抓到同一個工作區。本架構的部署物是映像，各模組自己建置；跨模組開發也是釘映像，不需要抓其他模組的原始碼。所以不需要。

**Q：如果日後真的需要原始碼工作區，選哪個？**
A：建議 `west`。實測它的清單用 YAML，tag / SHA / branch 可直接寫，可不依賴 Zephyr 獨立使用。使用時要注意三點：
1. `west manifest --freeze` 凍結的是 `manifest-rev`，不是目前 HEAD；
2. 專案的 submodule 若用相對 URL，需要把清單中的 remote 命名為 `origin`；
3. west 沒有「複製或連結檔案」與「跨 repo 開分支」的功能，可由 `just` 補上。

**Q：為什麼不選 Rust / Go 寫的現成工具？**
A（已查證）：`mani` 不支援 tag / commit 鎖定；`gitgrip` 的 Rust 版已進入維護模式，主力轉為 Python；`ripvcs` 最後 commit 是 2025-06，鎖定行為文件不明。詳見 [tool-evaluation.md](tool-evaluation.md)。

**Q：Google 的 `repo` 為什麼不選？**
A：它能用，且實測通過鎖版本流程。不選的原因是：清單為 XML；project 的 tag 必須寫 `refs/tags/` 前綴；2026-11-13 查閱其 issue tracker，開放中有 184 個 issue（其中 126 個是 bug，只讀標題、沒有逐一檢視內容），含數筆 sync 卡住的回報。

**Q：submodule 能不能用？**
A（已實測）：在本架構不受影響：sub-repo 的 CI 自己 `git clone --recurse-submodules` 即可。west 對相對 URL 的 submodule 的限制見 [tool-evaluation.md](tool-evaluation.md)。

## 其他

**Q：`just` 的角色是什麼？**
A（已確定）：統一的使用者介面。底下目前是 `docker compose` 與 shell；日後底層實作若要更換，使用者看到的指令不變。

## 尚未涵蓋 / 未驗證

- bot 自動升級 PR（[#1](https://github.com/ycpss91255-docker/system_repo_template/issues/1)、[#2](https://github.com/ycpss91255-docker/system_repo_template/issues/2)）、完整系統驗證 CI（[#3](https://github.com/ycpss91255-docker/system_repo_template/issues/3)）：尚未實作。
- 斷網、中途失敗的更多情境，只驗證了「映像不存在」這一種。
- 機密的管理方式尚未決定。
- 範例用本機 registry 與 `localhost:5555`；真實 registry 的認證流程未涵蓋。
- 示範只在 Linux + docker compose v5 + just 1.x 上跑過。
