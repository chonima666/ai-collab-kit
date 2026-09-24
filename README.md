# ai-collab-kit

跨專案共用的 AI 協作治理工具包：**建構 AI × 審查 AI × 人**，以 GitHub Pull Request 作為持久、可追溯的協作介面。
通用規則放在本 repo，每個專案只保留自己的設定（Project Profile）。

## 內容

| 檔案 | 用途 |
| --- | --- |
| `AI_COLLAB_GUIDE.md` | 權威守則（canonical）。其他文件與它衝突時，以它為準 |
| `REVIEW_PROTOCOL.md` | 建構者 ↔ 審查者 ↔ 人的 PR 協作協議：權限、四種 SHA、發現格式、回應義務 |
| `REVIEWER_BOOTSTRAP.md` | 審查者每一輪的啟動契約：只靠 repo 與 PR 重建狀態，不依賴 session 記憶 |
| `AI_COLLAB_QUICK_RULES.md` | 日常執行摘要，本身足以擋下最常見的危險操作 |
| `roles/BUILDER.md`、`roles/REVIEWER.md` | 角色特有要求。角色依任務指派，不依工具或模型固定 |
| `adapters/CLAUDE.md`、`adapters/AGENTS.md` | 入口檔骨架。依**工具**區分，不依角色區分 |
| `templates/project.yaml` | 專案設定範本 |
| `templates/pull_request_template.md` | PR 說明範本，強制四種 SHA 與計算出的變更類型 |
| `scripts/install.sh`、`scripts/verify.sh`、`scripts/lib.sh` | 安裝／升級、檢查、共用邏輯 |
| `tests/run.sh` | 端對端測試 |

## 安裝到專案

```bash
git clone https://github.com/chonima666/ai-collab-kit
ai-collab-kit/scripts/install.sh path/to/project
# 填寫 path/to/project/.ai-collab/project.yaml 的每個 REPLACE_ 值，然後再跑一次同步：
ai-collab-kit/scripts/install.sh path/to/project
path/to/project/.ai-collab/kit/scripts/verify.sh --root path/to/project
```

安裝後，專案內的結構：

```text
CLAUDE.md                       # 入口；標記內的區塊由 kit 管理，以 @匯入 載入精簡規則與專案設定
AGENTS.md                       # 入口；標記內的區塊由 kit 管理，逐字內嵌精簡規則與專案設定
.github/pull_request_template.md
.ai-collab/
  VERSION                       # 專案採用的 kit 版本
  MANIFEST                      # kit 檔案的 SHA-256，用來偵測本地修改
  project.yaml                  # 專案擁有，install.sh 永不覆蓋
  kit/                          # kit 管理的檔案，每次安裝都會更新
```

## 設計原則

- **單一來源**：規則只在本 repo 維護。專案內的 kit 檔案不得本地修改（`verify.sh` 會偵測），要改請回到本 repo 發新版。
- **入口檔要能獨立生效**：多數 agent 不會自動載入被引用的檔案，所以 `AGENTS.md` 逐字內嵌精簡規則；
  Claude Code 支援 `@匯入`，所以 `CLAUDE.md` 用匯入。兩者都由 `install.sh` 產生，並由 `verify.sh` 比對，不會漂移。
- **專案內容不被覆蓋**：`project.yaml`、入口檔標記外的內容，以及不是 kit 建立的 PR 範本，安裝時一律保留。
- **變更類型用算的**：`verify.sh pr --validated <sha>` 計算「已驗證 commit 之後」的變更，分為 code、config、tests、docs，
  不靠人工填寫。無法辨識的路徑一律算 code。
- **狀態不由建構者宣告**：審查與決策狀態以 GitHub 的 review、留言與合併紀錄為準（`REVIEW_PROTOCOL.md` §2.2）。
- **不依賴 session 記憶**：審查者每一輪都依 `REVIEWER_BOOTSTRAP.md` 從 GitHub 重建狀態；自動喚醒只是選配，失效時由人工啟動。
- **角色簽章**：AI 常共用負責人的 GitHub 帳號，所以每則 AI 留言都以角色標頭開頭，並帶機器可讀的 SHA 欄位（`REVIEW_PROTOCOL.md` §8）。
- **權限由 GitHub 落實**：分支保護、審查者只讀、建構者不能合併自己的 PR（`REVIEW_PROTOCOL.md` §1）。

## 版本

`VERSION` 採語意化版本。本 repo 本身也走 `REVIEW_PROTOCOL.md` 的流程：建構者開 PR，審查者審，人合併。

## 限制（v0.1.0）

- 測試與腳本以 bash、git、coreutils 為前提（Linux 與 macOS）；尚未支援 Windows 原生 shell。
- `project.yaml` 只檢查頂層 key 是否存在與占位符是否填完，不驗證值的格式。
- 變更分類規則目前固定，尚不能由專案自訂。
- 分支保護需要人手動在 GitHub 設定；本版只提供規範，不自動設定。
- 自動喚醒審查者（GitHub event → reviewer）尚未實作，規劃於 v0.2（`REVIEW_PROTOCOL.md` §8.3）。
