# 多 repo 管理工具評估

評估日期：2026-11-13。當時的需求是「通用（不綁特定領域框架）、能鎖版本、能批次操作」，語言偏好 Rust/Go 但以功能優先。後來確認部署物是映像、跨模組開發也是釘映像，這類工具就用不到了；以下記錄當時的查證，供日後需求改變時參考。

## 候選工具

| 工具 | 語言 | 結論 |
|---|---|---|
| mani | Go | 文件中專案只有 `branch:` 欄位，沒有 tag / commit 鎖定，也沒有凍結指令 |
| gitgrip | Rust | Rust 版（gr1）已進入維護模式，主力轉為 Python 寫的 gr2（alpha）；一般 repo 的 revision 能否填 SHA 文件未說明 |
| ripvcs | Go | 最後 commit 為 2025-06；SHA 鎖定與 export 行為文件不明 |
| Google `repo` | Python | 實測通過（見下方實測） |
| west | Python | 實測通過（見下方實測） |

## `repo` 與 `west` 的實測（容器內，repo launcher 2.71、west 1.5.0）

兩者都通過：branch 追蹤、tag 鎖定、完整 SHA 鎖定、凍結成鎖定清單、上游前進後用鎖定清單還原、`forall`、有未提交變更時拒絕覆蓋並保留變更。

需要注意的差異：

- **`repo`**：清單是 XML；project 的 `revision` 寫裸 tag 名（`v1.0`）會失敗，必須寫 `refs/tags/v1.0`；縮短的 SHA 不支援（來自上游 issue 回報，未實測）。`repo manifest -r` 凍結的是**目前 HEAD**。
- **`west`**：清單是 YAML，tag / SHA / branch 直接寫。`west manifest --freeze` 凍結的是 **`manifest-rev`（遠端 revision 解析出的 SHA），不是目前 HEAD**，專案內有未推送的本地 commit 時兩者不同，用它之前要先確認 HEAD 等於 `manifest-rev` 且無髒檔。
- **`west` 與 submodule**：submodule 用絕對 URL 可正常運作；用**相對 URL** 時，`west update` 會失敗，因為 west 把遠端命名為清單中的名稱，而 git 解析相對路徑時固定找名為 `origin` 的遠端。把清單中的 remote 命名為 `origin` 即可繞過。上游 issue [west#545](https://github.com/zephyrproject-rtos/west/issues/545) 自 2021 年起仍開著，對應的修復 PR #546 已關閉未合併。
