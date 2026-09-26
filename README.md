# ai-collab-kit

跨專案共用的 AI 協作治理工具包：**建構 AI → 獨立審查 AI → Policy Gate → 自動交付**，人只處理例外。
以 GitHub Pull Request 作為持久、可追溯的協作介面。
通用規則放在本 repo，每個專案只保留自己的設定（Project Profile）。

## 內容

| 檔案 | 用途 |
| --- | --- |
| `AI_COLLAB_GUIDE.md` | 權威守則（canonical）。其他文件與它衝突時，以它為準 |
| `REVIEW_PROTOCOL.md` | PR 協作協議：角色與權限、四種 SHA、發現格式、Loop Guard、Policy Gate 與自動交付 |
| `REVIEWER_BOOTSTRAP.md` | 審查者每一輪的啟動契約：只靠 repo 與 PR 重建狀態，不依賴 session 記憶 |
| `AI_COLLAB_QUICK_RULES.md` | 日常執行摘要，本身足以擋下最常見的危險操作 |
| `roles/BUILDER.md`、`roles/REVIEWER.md` | 角色特有要求。角色依任務指派，不依工具或模型固定 |
| `adapters/CLAUDE.md`、`adapters/AGENTS.md` | 入口檔骨架。依**工具**區分，不依角色區分 |
| `templates/project.yaml` | 專案設定範本 |
| `templates/pull_request_template.md` | PR 說明範本，強制四種 SHA 與計算出的變更類型 |
| `scripts/install.sh`、`scripts/verify.sh`、`scripts/lib.sh` | 安裝／升級、檢查、共用邏輯 |
| `scripts/pr-state.sh`、`scripts/ai-review.sh`、`scripts/orchestrate.sh`、`scripts/notify-discord.sh` | 自動審查：從 GitHub 重建狀態、呼叫模型審查、以 Reviewer App 回寫、Discord 通知 |
| `scripts/policy-gate.sh`、`scripts/deliver.sh` | 自動交付：以固定規則判定能否自動合併，由 Merger App 發布 `ai-collab/gate` 並合併 |
| `.github/workflows/ai-review.yml`、`docs/AUTOMATION.md` | 自動審查與自動交付的 workflow 與設定步驟 |
| `docs/E2E.md` | 在真實 GitHub、GitHub App 與 OpenAI 上的端對端驗收紀錄與證據 |
| `tests/run.sh` | 端對端測試 |
| `VERSION` | kit 的版本號（語意化版本） |

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
- **狀態不由建構者宣告**：審查狀態以 Reviewer App 的 review 為準，交付以 `ai-collab/gate` 與合併紀錄為準（`REVIEW_PROTOCOL.md` §2.2）。
- **不依賴 session 記憶**：審查者每一輪都依 `REVIEWER_BOOTSTRAP.md` 從 GitHub 重建狀態；自動喚醒只是選配，失效時由人工啟動。
- **Loop Guard**：建構者與審查者最多來回 `loop_guard.max_review_rounds` 輪（預設 3），同一個 SHA 不重複審查；
  到達上限或同一發現反覆未結案時，停在 `HUMAN_GATE_REQUIRED`，沒有任何留言能延長。`verify.sh review-state` 依規則判定，不連網（`REVIEW_PROTOCOL.md` §9）。
- **兩個身分**：建構者使用 owner 的帳號，審查者是另一個 GitHub App。建構者無法以 App 的身分發言，所以無法偽造 `VERIFIED`（`REVIEW_PROTOCOL.md` §8.1）。
- **Policy Gate**：CI 通過、Reviewer 在目前 head 上 `VERIFIED`、沒有風險旗標、沒有改動受保護路徑時才自動合併；
  `.github/`、kit 本身與專案列出的敏感路徑一律交給人（`REVIEW_PROTOCOL.md` §10）。
- **權限由 GitHub 落實**：`main` 的 ruleset 要求 CI 與 Merger App 的 `ai-collab/gate`，bypass 名單空白，建構者因此無法繞過審查自行合併（`REVIEW_PROTOCOL.md` §10.4）。

## 版本

`VERSION` 採語意化版本。本 repo 本身也走 `REVIEW_PROTOCOL.md` 的流程：建構者開 PR，審查者審，Policy Gate 決定自動合併或交給人。
本 repo 的 `.ai-collab/project.yaml` 把 `scripts/`、協議與守則、角色、adapter、範本與 `docs/AUTOMATION.md` 列為受保護路徑，
所以改動它們的 PR 一律由人合併；文件與測試的一般修改可以自動合併。

## 從 v0.3.0 升級到 v0.3.1

不需要修改 `project.yaml`。審查者的 prompt 新增可信的 repository／CI 資料（`REVIEW_PROTOCOL.md` §9.6），
`ai-review.yml` 的審查 job 因此多了 `checks: read`；其他專案要同步更新複製過去的 workflow。

## 從 v0.2.0 升級到 v0.3.0

不相容的變更：
- `identities.human` 移除。`identities` 只剩 `builder` 與 `reviewer`，`reviewer` 必須是 `<app-slug>[bot]`，建構者可以使用 owner 的帳號。
- `Human-Decision: ALLOW_EXTRA_ROUND` 與 `verify.sh review-state --human-extra-rounds` 移除，沒有任何方式能延長 Loop Guard。
- 審查紀錄必須帶 `Risk-Flags:`，模型輸出的最後三行是 `Review-Status:`、`Open-Findings:`、`Risk-Flags:`。

新增：
- `policy_gate:` 與 `auto_merge:` 區塊（見 `templates/project.yaml`），只有使用自動交付時需要。
- 自動交付：Merger App、`ai-collab/gate`、`AICK_AUTO_MERGE` 與 `main` 的 ruleset，依 `docs/AUTOMATION.md` 設定。

## 從 v0.1.1 升級到 v0.2.0

`project.yaml` 可以新增 `identities:` 區塊（見 `templates/project.yaml`）。不使用自動審查就不需要，`verify.sh` 不要求它。
要使用自動審查，依 `docs/AUTOMATION.md` 設定。

## 從 v0.1.0 升級

`install.sh` 不會修改專案的 `project.yaml`。升級到 v0.1.1 後，請把 `templates/project.yaml` 最後的 `loop_guard:` 區塊
加進 `.ai-collab/project.yaml`，再跑一次 `install.sh` 同步 `AGENTS.md`；在此之前 `verify.sh` 會回報缺少 `loop_guard`。

## 限制（v0.3.1）

- 腳本需要 Bash 3.2 以上、git 與 POSIX 工具；CI 在 Ubuntu 與 macOS（系統內建 Bash 3.2）上執行。尚未支援 Windows 原生 shell。
- `project.yaml` 只檢查頂層 key 是否存在與占位符是否填完，不驗證值的格式。
- 變更分類規則目前固定，尚不能由專案自訂。
- 分支保護需要人手動在 GitHub 設定；本版只提供規範，不自動設定。
- 自動審查需要 Reviewer GitHub App、OpenAI API key 與 `ai-review` environment；自動交付另外需要 Merger App 與 `main` 的 ruleset（`docs/AUTOMATION.md`）；
  缺任何一項都會拒絕執行。來自 fork 的 PR 不做自動審查與自動交付。
- `install.sh` 不會安裝 workflow；要在其他專案使用自動審查，需手動複製 `.github/workflows/ai-review.yml`。
- Discord 只做通知；Human Gate 由 owner 在 GitHub 上處理（`REVIEW_PROTOCOL.md` §10.5）。
- Policy Gate 的固定規則只看路徑，不看檔案內容；敏感的程式碼要靠 `policy_gate.human_paths` 列出，其餘由 Reviewer 的風險旗標補足。
- 自動審查需要 `jq` 與 `curl`（GitHub 的 runner 已內建）。
