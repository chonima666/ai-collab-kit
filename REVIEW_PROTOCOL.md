# Review Protocol：建構者 × 審查者 × Policy Gate

本協議定義以 GitHub Pull Request 為正式溝通介面的 AI 協作方式：建構者 AI 完成修改，審查者 AI 獨立審查，
Policy Gate 放行的變更自動合併，只有例外才交給人（owner）。它補充 `AI_COLLAB_GUIDE.md`，不取代守則；
兩者衝突時以守則為準。

## 1. 角色與權限

| 角色 | GitHub 身分 | 責任 | 權限 | 不得擁有／不得做 |
| --- | --- | --- | --- | --- |
| 建構者（Builder AI） | owner 的帳號（`identities.builder`） | 實作、測試、開 PR、修正審查發現、請求審查 | push 到自己的工作分支 | 合併任何 PR、開啟 auto-merge、發布 `ai-collab/gate` 狀態、修改分支規則、以審查者身分發言 |
| 審查者（Reviewer AI） | Reviewer GitHub App（`identities.reviewer`） | 獨立審查需求、程式、證據與發布一致性，標示風險 | Contents: Read、Pull requests: Read and write | Contents: Write、merge、admin、workflows、secrets、commit statuses |
| Merger App | 另一個 GitHub App，只在交付 job 使用 | 發布 `ai-collab/gate` 狀態；Policy Gate 放行時合併（§10） | Contents、Pull requests、Commit statuses: Read and write | 審查、出現在 ruleset 的 bypass 名單 |
| 人（owner） | 與建構者同一個帳號 | 只處理 `HUMAN_GATE_REQUIRED` 的例外 | Admin | 不適用 |

同一項變更不得由同一方建構又擔任審查。建構者與 owner 共用帳號，GitHub 分不出兩者（§8.1），所以真正的邊界由
`main` 的 ruleset 落實，而不是靠 AI 自律（§10.4）：

- 禁止直接 push 與 force push；變更必須經過 PR。
- 合併前必須通過 CI 與 Merger App 發布的 `ai-collab/gate`。一般流程不要求人工 approval。
- bypass 名單保持空白，建構者因此無法繞過 Reviewer 與 Policy Gate 自行合併。

## 2. PR 是持久的協作狀態

PR 承載：建構者的 commit、審查發現、修正回應、驗證證據、人的決策。下一個 session（任何一方）應能只靠 PR 重建脈絡，
不需要對方的對話記憶。

### 2.1 四種 SHA

| 欄位 | 意義 |
| --- | --- |
| Current HEAD | PR 當下最新的 commit |
| Code under review | 審查者實際檢查的 commit 或範圍 |
| Validated commit | 測試、CI、staging 等證據實際對應的 commit |
| Deployed commit | 實際部署到 staging／production 的版本，沒有則填 N/A |

不得假設這四者相同。**「Validated commit 之後的變更類型」必須由 `verify.sh pr --validated <sha>` 計算**
（docs／tests／code／config），並把輸出貼進 PR 說明；不得憑印象填寫。

> 回歸案例 1：某專案宣稱已驗證 commit 之後「只有文件」，實際還多了一個測試檔。人工填寫會出錯，所以改為計算。

### 2.2 狀態的權威來源

PR 說明由建構者撰寫、可隨時修改，因此不能作為審查或決策狀態的權威來源：

- 審查狀態：以 Reviewer App 最新一則帶有 `Review-Status:` 與 `Reviewed-SHA:` 的 review 或留言為準（§8）。
- 交付狀態：以 Merger App 發布的 `ai-collab/gate` 狀態與合併紀錄為準（§10）。
- 建構者帳號寫的任何文字都不構成審查結論或人的授權，因為 GitHub 無法證明它出自人（§8.1）。
- PR 說明最多只能引用上述紀錄（附連結）。

## 3. 開 PR 之前

1. 取得遠端最新狀態，列出仍開著的 PR。若有 PR 與本次變更重疊（相同 commit、相同檔案、同一功能），先決定開法：疊在既有 PR 上、合併進同一個 PR，或等待；決策寫入 PR 說明。
2. 執行 `project.yaml` 的必跑檢查，以及 `verify.sh`。
3. 依範本填寫 PR 說明。

> 回歸案例 2：某專案原本打算開 PR 到 `main`，但已有兩個開著的 PR 包含相同 commit；直接開會重疊 93 個 commit。

## 4. 審查層級

| 層級 | 核心問題 | 典型檢查 |
| --- | --- | --- |
| 1. 需求 | 是否真的解決原始需求？ | 需求覆蓋、邊界條件、非預期副作用 |
| 2. 程式 | diff 本身是否正確？ | 邏輯、錯誤處理、資安、維護性、測試 |
| 3. 驗證 | 證據是否支持結論？ | 證據對應的 commit、CI、staging、測試輸出 |
| 4. 發布 | 被驗證的是否就是要部署的？ | 四種 SHA 對齊、部署來源、之後的 commit、設定差異 |

審查者可以參考建構者整理的資料（盤點、說明），但那是建構者的**宣稱**，不是獨立證據。涉及權限、資料庫角色或部署狀態時，
以當下的現場查詢為準；查詢無法由審查者直接執行時，列出唯讀查詢交給人執行。

## 5. 審查發現的格式

每一項發現包含：

- 編號（例如 `R1-03`）與嚴重度（高／中／低／資訊）
- 檔案與行號，以及審查時的 commit
- 問題描述
- 重現條件或推理路徑
- 影響
- 建議修法
- 信心程度：**已證實**（有重現或直接證據）或**推論**

沒有具體檔案、版本與重現或推理路徑的意見，不構成發現。

## 6. 建構者的回應義務

每一項發現都要在同一討論串得到回應，三選一：

1. **修正**：附修正的 commit，並說明修了什麼。
2. **不修**：說明理由（例如不重現、屬預期行為、已在其他地方處理）。
3. **Gate**：需要人決定時，用守則 §3 的授權請求卡片提出。

不得默默略過或自行關閉討論串。修正後由審查者複查；審查者接受後，討論串才算結案。

## 7. 合併

建構者 AI 不合併任何 PR。合併只有兩種途徑：

- **自動交付**（一般情況）：Merger App 在 Policy Gate 判定 `AUTO_MERGE_ALLOWED` 時合併（§10）。
- **人工處理**（例外）：判定為 `HUMAN_GATE_REQUIRED` 的 PR 由 owner 自行決定修正、合併或關閉（§10.5）。

## 8. 身分、簽章與喚醒

### 8.1 身分

`project.yaml` 的 `identities:` 列出兩個不同的 GitHub login：

| 欄位 | 內容 |
| --- | --- |
| `builder` | 建構者 AI 發言與 push 所用的帳號，通常就是 owner 的帳號 |
| `reviewer` | Reviewer GitHub App 的 bot login，格式是 `<app-slug>[bot]` |

兩者都必須設定、必須不同，而且 `reviewer` 必須是 GitHub App 的 bot login；否則自動化拒絕執行（fail closed）。

建構者與 owner 共用帳號，GitHub 無法分辨某則留言、某次操作是人還是 AI 做的。因此：

- 自動化只信任建構者帳號的 `AI-Review: READY`。這一行只能請求審查，不能給出任何授權。
- 審查結論只信任 Reviewer App 寫的紀錄。建構者無法以 App 的身分發言，所以無法偽造 `VERIFIED`。
- 沒有任何留言可以延長 Loop Guard、放行 Policy Gate 或代表人的決定。

### 8.2 簽章

AI 在 GitHub 上寫的每一則 PR 說明、留言與 review，第一行都必須是角色標頭：

```text
[AI-Builder: <名稱>]      # 例如 [AI-Builder: Claude]
[AI-Reviewer: <名稱>]
```

另外依用途加上機器可讀的行：

| 用途 | 誰寫 | 必要欄位 |
| --- | --- | --- |
| 審查發現與每輪總結 | 審查者 | `Reviewed-SHA: <40 字元 commit>`；總結另加 `Review-Status: CHANGES_REQUESTED` 或 `VERIFIED`、`Open-Findings: <編號, ...>`（沒有則填 `none`）與 `Risk-Flags: <旗標, ...>`（沒有則填 `none`，§10.2） |
| 請求審查或複查 | 建構者 | `AI-Review: READY` 與 `Ready-SHA: <40 字元 commit>` |
| 回應某項發現 | 建構者 | 發現編號，修正時加 `Fixed-In: <commit>` |

AI 不得省略標頭，也不得冒用另一個角色的標頭。

### 8.3 喚醒

審查者從 GitHub 狀態重建脈絡（`REVIEWER_BOOTSTRAP.md`），所以喚醒只是「何時開始一輪審查」，不承載狀態。

- 觸發事件：建構者的 `AI-Review: READY` 留言，或手動啟動 workflow。其他留言只會重新判定狀態，不會單獨開始一輪。
- 審查者自己的留言與 review 一律不觸發審查。
- Current HEAD 等於最近一次的 `Reviewed-SHA` 時，不做完整的程式審查。
- 每次喚醒前先套用 Loop Guard（§9）；實作見 §9.6。
- 自動化失效時，依 `REVIEWER_BOOTSTRAP.md` §8 由人工啟動；流程不得依賴自動化才能運作。

## 9. Loop Guard（審查輪數控制）

Loop Guard 限制建構者與審查者之間的來回次數，避免 AI 之間無限迭代。它不評估程式品質：輪數用完**永遠不等於通過**，
只代表必須交給人決定。

### 9.1 名詞

- **有效審查輪（round）**：一個**新的** Ready-SHA 收到審查者一次正式的 `Review-Status:` 判定。
  同一個 SHA 再審一次、重貼留言、測試留言，都不增加輪數。新的 session、對話或 commit 也不會重置計數。
- **未結案發現**：審查者在某一輪總結的 `Open-Findings:` 中列出的發現編號。

### 9.2 規則

| 編號 | 規則 |
| --- | --- |
| LG-01 | 沒有新的 Ready-SHA，就不複查。 |
| LG-02 | Ready-SHA 已經審查過（等於最近一次或更早的 `Reviewed-SHA`）時，結果是 `NO_ACTION`。 |
| LG-03 | 第一輪審查完整範圍；之後只審 `Last-Reviewed-SHA..Ready-SHA`，加上仍未結案的發現。§4 要求擴大範圍的情況照舊適用。 |
| LG-04 | 預設最多 3 輪（`project.yaml` 的 `loop_guard.max_review_rounds`）。第 1 到 3 輪都允許完成；第 3 輪結束後，下一個新的 Ready-SHA 一律是 `HUMAN_GATE_REQUIRED`，不論上一輪是否為 `VERIFIED`。 |
| LG-05 | 同一個發現編號在 2 個不同的 Ready-SHA 上都未結案時，下一個新的 Ready-SHA 是 `HUMAN_GATE_REQUIRED`（reason=`repeated_unresolved_finding`）。只看審查結果，不看建構者是否宣稱已修正，也不論第二個 SHA 有沒有碰到相關程式。 |
| LG-06a | AI 不得修改、停用、繞過、重置或延長 Loop Guard 的限制。例如：自行修改 `project.yaml` 的限制值、宣稱「這次特殊」多跑一輪、用另一則留言重置計數、為了重置輪數另開 PR。 |
| LG-06b | 沒有任何留言或命令列參數能延長輪數。到達 `HUMAN_GATE_REQUIRED` 後，這個 PR 的自動流程停止（§9.4）。 |

為了讓 LG-05 可以從 GitHub 重建，審查者每一輪的總結都必須帶 `Open-Findings:`（§8.2）。

### 9.3 判定工具

`verify.sh review-state` 依上面的規則，對呼叫者提供的狀態做判定。它**不連網、不讀 GitHub**；從 PR 取得狀態是呼叫者
（人、審查者或 orchestrator）的責任。

```bash
.ai-collab/kit/scripts/verify.sh review-state \
  --ready <Ready-SHA> \
  --reviewed <Reviewed-SHA>[:<未結案編號>,...]   # 每一則帶 Review-Status 的審查總結一筆，依時間順序，可重複
```

- 輪數上限只從 `project.yaml` 讀取，沒有任何命令列參數可以改變它。
- 實際上限是 `max_review_rounds` 與第一次發生爭議（LG-05）的輪次，取較小者。
- SHA 必須是 40 字元的小寫十六進位。同一個 SHA 出現多次時，只算一輪，以最後一筆的未結案清單為準。
- 輸出為 `key=value` 行，第一行是 `decision=`，只會是下列三種之一：

| decision | exit code | 意義 |
| --- | --- | --- |
| `REVIEW` | 0 | 進行一輪審查；`scope=` 是審查範圍，`carry_findings=` 是需要一併複查的未結案發現 |
| `NO_ACTION` | 10 | Ready-SHA 已審查過，不審查 |
| `HUMAN_GATE_REQUIRED` | 20 | 停止 AI 迭代，交給人決定；`reason=` 只會是單一值 `max_review_rounds` 或 `repeated_unresolved_finding`，兩者同時成立時輸出 `repeated_unresolved_finding`；爭議時另有 `disputed_findings=` |
| （無） | 2 | 輸入不合法或設定錯誤，訊息在 stderr |

### 9.4 到達 Gate 之後

到達 `HUMAN_GATE_REQUIRED` 時，自動化對這個 PR 只做一件事：通知 owner。它不再呼叫模型，也不會自動合併。
之後的新 Ready-SHA 仍然是 `HUMAN_GATE_REQUIRED`。

owner 可以自行修正後合併、接受風險直接合併，或關閉這個 PR（§10.5）。是否另開一個 PR 重新開始，也由 owner 決定。

本協議不提供「多審一輪」的留言指令：建構者使用 owner 的帳號，這種留言無法證明出自人，不能作為自動授權。
將來若需要，必須另外設計可驗證的人為恢復流程。

### 9.5 自動化的前提

下列兩項都成立時，才能啟用自動審查：

1. Loop Guard 由 orchestrator 強制執行：每次喚醒前都經過 §9.3 的判定，`HUMAN_GATE_REQUIRED` 時不喚醒。
2. 審查結論來自建構者無法冒用的身分：Reviewer GitHub App（§8.1）。

### 9.6 自動審查

`.github/workflows/ai-review.yml` 把 §9.5 的前提寫成程式。流程：

1. 建構者貼出 `AI-Review: READY` 留言（或手動啟動 workflow）。
2. `scripts/pr-state.sh` 從 GitHub 實際的 PR 留言與 review 重建狀態，交給 `verify.sh review-state` 判定（§9.3）。
3. 依判定結果：
   - `NO_ACTION`：什麼都不做，不呼叫模型。
   - `HUMAN_GATE_REQUIRED`：不呼叫模型，只發 Discord 通知 owner。
   - `REVIEW`：`scripts/ai-review.sh` 以 `REVIEWER_BOOTSTRAP.md`、本協議與 repo／PR 的實際資料組成 prompt，呼叫模型，
     檢查輸出後由 `scripts/orchestrate.sh` 以 **Reviewer GitHub App** 的身分，把結果貼成一則針對 Ready-SHA 的 PR review（COMMENT）。
4. 審查貼出後，交付 job 執行 Policy Gate（§10）。

**每一種紀錄只認它擁有者的發言**：

| 紀錄 | 只認誰寫的 |
| --- | --- |
| `AI-Review: READY`、`Ready-SHA:` | `identities.builder` |
| `Review-Status:`、`Reviewed-SHA:`、`Open-Findings:`、`Risk-Flags:` | `identities.reviewer` |

PR 說明裡宣稱的審查狀態一律不算。

審查者寫的每一則帶 `Review-Status:` 的紀錄都必須完整：
- `Reviewed-SHA:` 是 40 字元的 SHA，且一定要有 `Open-Findings:` 與 `Risk-Flags:`。
- `VERIFIED` 的 `Open-Findings` 必須是 `none`，`CHANGES_REQUESTED` 至少要有一個合法編號。
- `Risk-Flags` 是 `none` 或 §10.2 列出的旗標。

有任何一則不完整，就停止重建狀態（exit 2），不會把缺少的欄位當成 `none`。

**模型輸出的約束**：
- 角色標頭、`Reviewed-SHA:` 與輪次由腳本寫入，不由模型寫。
- 模型回覆的最後三個非空行必須依序是 `Review-Status:`、`Open-Findings:` 與 `Risk-Flags:`，這三個欄位在回覆中各只能出現一次。
  不符合、狀態與未結案發現矛盾，或出現未知的風險旗標，就不貼文，並通知 `REVIEW_FAILED`；腳本不會修補格式不對的輸出。
- diff 因過大而被截斷時，腳本一律加上 `insufficient-evidence`。
- 模型寫出的協議欄位與角色標頭會被刪除。
- API 逾時、錯誤、缺少 `OPENAI_API_KEY` 或 Reviewer App 金鑰時，一律失敗且不貼文。

**可信執行邊界**：
- workflow 只由 `issue_comment`、`workflow_dispatch` 與 `ci` 的 `workflow_run` 觸發，三者都執行預設分支上的 workflow 與腳本。
  預設分支只能經由合併的 PR 改變，而改動 `.github/` 與 kit 本身一律需要 owner（§10.1）。
- 不使用 `pull_request`、`pull_request_target` 或 `pull_request_review` 觸發。
- PR 的程式碼只以 git 物件取得，用來產生 diff 與變更清單，從不 checkout 成工作目錄或執行。
- 每一個 workflow（包括 `ci.yml`，它的結果是自動合併的條件）使用的 action 都固定在完整的 commit SHA，不用可以移動的 tag。
- 判定狀態的 job 沒有任何 secret。所有 secret 放在只限預設分支使用的 `ai-review` environment：
  審查 job 只拿到模型金鑰與 Reviewer App 金鑰，且只在 `REVIEW` 時交出；交付 job 只拿到 Merger App 金鑰。
- 來自 fork 的 PR 一律不自動審查、不自動交付。

**Discord** 只做通知，不接受決定：`REVIEW_STARTED`、`REVIEW_VERIFIED`、`CHANGES_REQUESTED`、`HUMAN_GATE_REQUIRED`、
`REVIEW_FAILED`、`AUTO_MERGED`、`AUTO_MERGE_FAILED`。

設定步驟見 `docs/AUTOMATION.md`。自動化失效時，仍可依 `REVIEWER_BOOTSTRAP.md` §8 由人手動啟動審查。

## 10. Policy Gate 與自動交付

Policy Gate 決定一個 PR 能否不經人工直接合併。它由固定規則判定，不交給模型自行判斷什麼算重要；模型的風險旗標只能
把 PR 送去給人，不能放行。

### 10.1 放行條件

下列條件**全部**成立時，判定為 `AUTO_MERGE_ALLOWED`：

1. PR 開著、不是草稿、來自同一個 repository，目標是預設分支。
2. Loop Guard 沒有判定 `HUMAN_GATE_REQUIRED`。
3. Reviewer App 在**目前 head** 上最新一則紀錄是 `VERIFIED`。較舊 commit 的 `VERIFIED` 不算。
4. 這個紀錄的 `Risk-Flags` 是 `none`。
5. PR 沒有改動受保護的路徑：
   - 內建、無法移除：`.github/`、`.ai-collab/`、`CLAUDE.md`、`AGENTS.md`（CI 與 workflow、kit 本身與設定、agent 入口）；
   - 加上 `project.yaml` 的 `policy_gate.human_paths`，例如認證、migration、基礎設施、計費的目錄。
   路徑比對不分大小寫，`*` 也會跨目錄。搬移檔案視為「刪除舊路徑＋新增新路徑」，把受保護的檔案移走也算改動它。
6. head 已經包含預設分支目前的 tip。tip 在判定當下從 GitHub 讀取，不沿用 PR 建立時的紀錄（§10.4）。
7. `project.yaml` 的 `auto_merge.required_checks` 中每一個 check，在目前 head 上都有由 GitHub Actions 產生、最新一次結論為
   `success` 的執行。其他 app 產生的同名 check、其他 commit 的 check 都不算。

不成立時的結果：

| 情況 | 判定 | reason |
| --- | --- | --- |
| 第 5 項不成立 | `HUMAN_GATE_REQUIRED` | `protected_path` |
| 第 4 項不成立 | `HUMAN_GATE_REQUIRED` | `reviewer_risk_flags` |
| 第 2 項不成立 | `HUMAN_GATE_REQUIRED` | `loop_guard` |
| 還沒審查、`CHANGES_REQUESTED`、head 不包含最新的預設分支、CI 還沒跑完或失敗、草稿、目標不是預設分支 | `NOT_READY` | `not_reviewed`、`changes_requested`、`base_outdated`、`ci_pending`、`ci_failed`、`draft`、`not_default_branch` |

`NOT_READY` 是建構者還有事要做或正在等待；`HUMAN_GATE_REQUIRED` 則表示自動化永遠不會合併這個 PR。
任一條件無法確認，例如設定讀不懂或 `required_checks` 是空的，就是錯誤（exit 2），不會放行。

### 10.2 風險旗標

審查者在每一輪總結的 `Risk-Flags:` 標出 PR 碰到的範圍，不論審查結果是否為 `VERIFIED`。旗標描述「碰到什麼」，
不是「對不對」；不確定是否適用時就標上。

| 旗標 | 範圍 |
| --- | --- |
| `auth` | 認證、授權邏輯 |
| `permissions` | 身分與權限模型、角色、存取控制 |
| `secrets` | secret、API key、token、憑證、GitHub App 權限 |
| `ci-boundary` | CI／GitHub Actions 的可信執行邊界、workflow 權限、secret 暴露範圍 |
| `branch-protection` | 分支保護或 ruleset |
| `merge-policy` | 合併或自動合併政策 |
| `release` | 發布或部署政策 |
| `review-system` | 審查者、orchestrator、Policy Gate 或 Loop Guard 本身 |
| `data-migration` | 破壞性的資料庫或資料 migration |
| `infrastructure` | production 基礎設施 |
| `billing` | 計費或金流 |
| `breaking-change` | 對使用者或呼叫端的破壞性變更 |
| `insufficient-evidence` | 看不到或無法驗證足夠的內容，無法建立信心 |

### 10.3 判定工具

`scripts/policy-gate.sh` 只讀本機資料：`pr-state.sh` 的輸出、PR 的變更清單（`git diff --no-renames --name-only -z`）、
head 的 check-runs，以及交付腳本剛讀到的預設分支 tip；head 是否包含這個 tip 用本機的 git 物件判斷。
它不連網，也不執行 PR 的任何內容。

| decision | exit code |
| --- | --- |
| `AUTO_MERGE_ALLOWED` | 0 |
| `NOT_READY` | 10 |
| `HUMAN_GATE_REQUIRED` | 20 |
| （無，輸入或設定錯誤） | 2 |

### 10.4 自動交付

`scripts/deliver.sh` 在三個時機執行：審查貼出之後、CI 在同 repo 的 PR 上成功結束之後，以及手動啟動 workflow 時。
每次都從 GitHub 重新判定，不沿用上一次執行的結果，所以重跑 workflow 不會繞過任何條件。步驟：

1. 以 `pr-state.sh` 重建狀態，並從 GitHub 讀取預設分支目前的 tip、變更清單與 head 的 check-runs。
2. 執行 Policy Gate。
3. 以 **Merger App** 的身分，在 head commit 發布 commit status `ai-collab/gate`：
   `AUTO_MERGE_ALLOWED` 為 `success`，`NOT_READY` 為 `pending`，`HUMAN_GATE_REQUIRED` 為 `failure`。
4. 只有 `AUTO_MERGE_ALLOWED` 時才合併，並把合併固定在被判定的 head SHA；判定後若有新的 push，GitHub 會拒絕這次合併。
5. 通知 `AUTO_MERGED`、`AUTO_MERGE_FAILED`，或在審查後的那次判定通知 `HUMAN_GATE_REQUIRED`。

Merger App 的金鑰不存在、狀態貼不出去或 GitHub 拒絕合併，一律失敗，不改用其他身分。

`main` 的 ruleset 讓上面的判定也擋住人工合併：

| 設定 | 值 |
| --- | --- |
| 必須經過 PR | 開啟，需要的 approval 數為 0 |
| 必須通過的 status checks | CI 的各個 check，以及 `ai-collab/gate`（來源限定 Merger App） |
| 合併前分支必須與預設分支同步（Require branches to be up to date） | 開啟 |
| 禁止 force push、禁止刪除分支 | 開啟 |
| bypass 名單 | 空白 |

**必須與預設分支同步**：兩個 PR 可能各自在同一個舊的 `main` 上通過 CI 與審查；其中一個合併後，另一個的 CI 結果並沒有測過
兩者合在一起的狀態。所以 Policy Gate 要求 head 已經包含預設分支目前的 tip（`base_outdated`），此時 head 的 tree 就是合併後
交付的 tree，CI 測的正是要交付的內容。ruleset 的「必須同步」再擋住判定之後 `main` 又前進的情況。

代價：`main` 前進後，其他開著的 PR 要先把 `main` 合併進自己的分支。這會產生新的 head，需要重新跑 CI 並重新審查，
也就是再用掉一輪 Loop Guard。

`ai-collab/gate` 的來源必須限定 Merger App。GitHub Actions 的身分不夠：PR 可以加入自己的 workflow，以 GitHub Actions
的身分發布同名狀態。Merger App 的金鑰只在限定預設分支的 environment 中，PR 裡的 workflow 拿不到。

合併使用 Merger App 的 token，所以之後 `main` 上的 `push` workflow（例如發布流程）會照常觸發。

### 10.5 Human Gate 的處理

判定為 `HUMAN_GATE_REQUIRED` 時，`ai-collab/gate` 是 `failure`，ruleset 因此擋住合併，包括 owner 自己。
owner 看過 PR 之後，可以：

- **要求修正**：請建構者修改。Gate 的原因是風險旗標時，修改後會在剩下的輪數內重新審查與判定；
  原因是 Loop Guard（`loop_guard`）時不會再審，修改後仍由 owner 合併或關閉。受保護的路徑無論怎麼修改都會停在 Human Gate。
- **合併**：在 ruleset 暫時把 Repository admin 角色加入 bypass 名單，合併後立即移除。
- **關閉** PR。

這些操作都要由 owner 在 GitHub 的設定畫面親自執行。建構者 AI 不得修改 ruleset、bypass 名單或 `ai-collab/gate`。
