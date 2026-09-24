# Review Protocol：建構者 × 審查者 × 人

本協議定義以 GitHub Pull Request 為正式溝通介面的 AI 協作方式。它補充 `AI_COLLAB_GUIDE.md`，不取代守則；
兩者衝突時以守則為準。

## 1. 三方角色與權限

| 角色 | 責任 | 建議 GitHub 權限 | 不得擁有／不得做 |
| --- | --- | --- | --- |
| 建構者（Builder AI） | 實作、修正審查發現、維護 PR 說明與證據 | 分支寫入（push 到自己的工作分支） | 合併自己的 PR、修改分支保護、自行宣告審查通過 |
| 審查者（Reviewer AI） | 獨立審查需求、程式、證據與發布一致性，提出修改要求 | Contents: Read、Pull requests: Read；要留言時加 Pull requests: Write | Contents: Write、push、merge、admin、secrets |
| 人（Human） | 需求、例外與風險決策、最終合併 | Merge 與 repo 治理 | 不適用 |

角色依任務指派，不依工具或模型固定。同一個 AI 在不同任務可以擔任不同角色，但**同一項變更不得由同一方建構又擔任最終審查**。

權限要由 GitHub 落實，不能只靠規則文字：

- `main`（或其他受保護分支）開啟分支保護：禁止直接 push、禁止 force push、合併前必須有 PR 且 CI 通過。
  三方各有獨立 GitHub 身分時，再要求至少一次核准；共用身分時無法核准自己的 PR，見 §8.1。
- 只有 Read 權限的審查者無法按 GitHub 的「Approve」。審查者的結論以帶 `Review-Status:` 的 review 或留言表達（§8.2）。
- 建構者使用的 GitHub 身分不得擁有 bypass 分支保護的權限。

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

- 審查狀態：以審查者最新一則帶有 `Review-Status:` 與 `Reviewed-SHA:` 的 review 或留言為準（§8）。
- 人的決定：以合併動作為準。三方各有獨立 GitHub 身分時，也可以用人的明確留言。
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

合併由人執行，前提是：

- 必跑檢查通過（附證據與對應 commit）
- 每一項審查發現都已結案
- 四種 SHA 與變更類型已確認
- 屬於需另行授權的動作時，已取得授權並寫入決策紀錄

## 8. 身分、簽章與喚醒

### 8.1 共用身分的問題

AI 常透過專案負責人連上的 GitHub 帳號操作，這時三方在 GitHub 上是**同一個身分**：

- 無法從作者欄位分辨誰寫了哪則留言，也就無法靠作者過濾自己的留言來避免喚醒迴圈。
- AI 的留言看起來和人的留言一樣，因此在身分分開之前，只有**合併動作**算是人的決定。
- GitHub 不允許 PR 作者核准自己的 PR；PR 若以負責人的身分開出，負責人本人也無法按 Approve。
  分支保護要求核准時，只能由負責人以管理員權限合併，或改為不要求核准，只要求 PR 與 CI 通過。

建議讓各 AI 使用獨立身分（例如專用帳號或 GitHub App），身分分開後才用作者來判斷來源與權威。

### 8.2 簽章（身分分開前一律遵守）

AI 在 GitHub 上寫的每一則 PR 說明、留言與 review，第一行都必須是角色標頭：

```text
[AI-Builder: <名稱>]      # 例如 [AI-Builder: Claude]
[AI-Reviewer: <名稱>]
```

另外依用途加上機器可讀的行：

| 用途 | 誰寫 | 必要欄位 |
| --- | --- | --- |
| 審查發現與每輪總結 | 審查者 | `Reviewed-SHA: <40 字元 commit>`；總結另加 `Review-Status: CHANGES_REQUESTED` 或 `VERIFIED`，以及 `Open-Findings: <編號, ...>`（沒有則填 `none`，§9.2） |
| 請求審查或複查 | 建構者 | `AI-Review: READY` 與 `Ready-SHA: <40 字元 commit>` |
| 回應某項發現 | 建構者 | 發現編號，修正時加 `Fixed-In: <commit>` |
| Loop Guard 例外 | 人 | `Human-Decision: ALLOW_EXTRA_ROUND` 與 `Reason: <理由>`（§9.4） |

沒有角色標頭的留言視為人所寫。AI 不得省略標頭，也不得冒用另一個角色的標頭。

### 8.3 喚醒（自動化為選配，v0.2 起提供）

審查者從 GitHub 狀態重建脈絡（`REVIEWER_BOOTSTRAP.md`），所以喚醒只是「何時開始一輪審查」，不承載狀態。

- 觸發事件：建構者的 `AI-Review: READY` 留言，或人手動啟動。其他留言只會重新判定狀態，不會單獨開始一輪。
- 審查者自己的留言與 review 一律不觸發審查。
- Current HEAD 等於最近一次的 `Reviewed-SHA` 時，不做完整的程式審查。
- 每次喚醒前先套用 Loop Guard（§9）；啟用自動喚醒的前提見 §9.5，實作見 §9.6。
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
| LG-06a | AI 不得修改、停用、繞過、重置或延長 Loop Guard 的限制。例如：自行修改 `project.yaml` 的限制值、宣稱「這次特殊」多跑一輪、自行批准額外輪次、用另一則留言重置計數。 |
| LG-06b | 自動化模式下，只有**可驗證**的 Human 授權能給予例外（§9.5）。 |

為了讓 LG-05 可以從 GitHub 重建，審查者每一輪的總結都必須帶 `Open-Findings:`（§8.2）。

### 9.3 判定工具

`verify.sh review-state` 依上面的規則，對呼叫者提供的狀態做判定。它**不連網、不讀 GitHub**；從 PR 取得狀態是呼叫者
（人、審查者，或未來的 orchestrator）的責任。

```bash
.ai-collab/kit/scripts/verify.sh review-state \
  --ready <Ready-SHA> \
  --reviewed <Reviewed-SHA>[:<未結案編號>,...]   # 每一則帶 Review-Status 的審查總結一筆，依時間順序，可重複
  [--human-extra-rounds <n>]                     # 已記錄的 ALLOW_EXTRA_ROUND 次數
```

- 輪數上限只從 `project.yaml` 讀取，沒有任何命令列參數可以改變它。
- SHA 必須是 40 字元的小寫十六進位。同一個 SHA 出現多次時，只算一輪，以最後一筆的未結案清單為準。
- 輸出為 `key=value` 行，第一行是 `decision=`，只會是下列三種之一：

| decision | exit code | 意義 |
| --- | --- | --- |
| `REVIEW` | 0 | 進行一輪審查；`scope=` 是審查範圍，`carry_findings=` 是需要一併複查的未結案發現 |
| `NO_ACTION` | 10 | Ready-SHA 已審查過，不審查 |
| `HUMAN_GATE_REQUIRED` | 20 | 停止 AI 迭代，交給人決定；`reason=` 只會是單一值 `max_review_rounds` 或 `repeated_unresolved_finding`，兩者同時成立時輸出 `repeated_unresolved_finding`；爭議時另有 `disputed_findings=` |
| （無） | 2 | 輸入不合法或設定錯誤，訊息在 stderr |

### 9.4 Human 例外

到達 `HUMAN_GATE_REQUIRED` 時，由人決定下一步，常見選項：

- `ALLOW_EXTRA_ROUND`：再審一輪
- `ACCEPT_RISK`：接受剩下的風險，由人決定是否合併
- `REQUIRE_FIX`：要求建構者修正後由人決定是否繼續
- `STOP`：停止這個 PR

`ALLOW_EXTRA_ROUND` 在 PR 上以下列格式記錄，沒有角色標頭：

```text
Human-Decision: ALLOW_EXTRA_ROUND
Reason: <理由>
```

每一次 `ALLOW_EXTRA_ROUND` 只多給 **1 輪**：不重置計數，不重新給 3 輪，不永久提高上限，也不修改 `project.yaml`。
實際上限是「`max_review_rounds` 與第一次發生爭議的輪次，取較小者」加上 `ALLOW_EXTRA_ROUND` 的次數。
所以在第一次觸發 Gate 之後，每多審一輪都需要一次新的授權。

**共用身分模式的限制**：三方共用同一個 GitHub 身分時（§8.1），`Human-Decision:` 留言只是聲明式紀錄，
無法由 GitHub 身分驗證作者是人，AI 也能寫出一模一樣的留言。因此在這個模式下：

- 真正的控制是**人手動決定並手動喚醒審查者**，不是 AI 解析這則留言後自行取得額外輪次。
- AI 不得自行寫出 `Human-Decision:` 留言，也不得替人轉貼。轉錄人的決定時，必須放在 AI 自己的角色標頭之下，並註明是轉錄。

### 9.5 自動喚醒的前提

自動喚醒（§8.3）啟用前，下列兩項都必須先完成：

1. Loop Guard 由 orchestrator 強制執行：每次喚醒前都經過 §9.3 的判定，`HUMAN_GATE_REQUIRED` 時不喚醒。
2. Human 的身分可以和建構者、審查者區分，至少做到下列其中一項：人使用個人 GitHub 身分，且建構者與審查者改用專用
   GitHub App 或 bot；或有可驗證的外部 Human 授權管道。

未滿足前，只能由人手動喚醒審查者。

### 9.6 自動審查（v0.2）

`.github/workflows/ai-review.yml` 把 §9.5 的前提寫成程式。流程：

1. 建構者貼出 `AI-Review: READY` 留言（或人手動啟動 workflow）。
2. `scripts/pr-state.sh` 從 GitHub 實際的 PR 留言與 review 重建狀態，交給 `verify.sh review-state` 判定（§9.3）。
3. 依判定結果：
   - `NO_ACTION`：什麼都不做，不呼叫模型。
   - `HUMAN_GATE_REQUIRED`：不呼叫模型，只發 Discord 通知人。
   - `REVIEW`：`scripts/ai-review.sh` 以 `REVIEWER_BOOTSTRAP.md`、本協議與 repo／PR 的實際資料組成 prompt，呼叫模型，
     檢查輸出後由 `scripts/orchestrate.sh` 以 **Reviewer GitHub App** 的身分，把結果貼成一則針對 Ready-SHA 的 PR review（COMMENT）。

**身分決定權威**（身分分開後取代 §8.1 的限制）：`project.yaml` 的 `identities:` 列出人、建構者、審查者三個不同的 GitHub
login。重建狀態時，每一種紀錄只認它擁有者的發言：

| 紀錄 | 只認誰寫的 |
| --- | --- |
| `AI-Review: READY`、`Ready-SHA:` | `identities.builder` |
| `Review-Status:`、`Reviewed-SHA:`、`Open-Findings:` | `identities.reviewer` |
| `Human-Decision: ALLOW_EXTRA_ROUND` | `identities.human` |

PR 說明裡宣稱的審查狀態一律不算。三個身分有任一個未設定、或有兩個相同時，自動審查拒絕執行（fail closed），
不會退回共用帳號。

**模型輸出的約束**：
- 角色標頭、`Reviewed-SHA:` 與輪次由腳本寫入，不由模型寫。
- 模型必須以 `Review-Status:` 與 `Open-Findings:` 結尾；`VERIFIED` 必須是 `Open-Findings: none`，`CHANGES_REQUESTED` 至少要有一個編號。
  不符合就不貼文，並通知 `REVIEW_FAILED`。
- 模型寫出的協議欄位與角色標頭會被刪除。
- API 逾時、錯誤、缺少 `OPENAI_API_KEY` 或 Reviewer App 金鑰時，一律失敗且不貼文。

**可信執行邊界**：
- workflow 只由 `issue_comment` 與 `workflow_dispatch` 觸發，兩者都執行預設分支上、經人合併的 workflow 與腳本。
- 不使用 `pull_request`、`pull_request_target` 或 `pull_request_review` 觸發。
- PR 的程式碼只以 git 物件取得，用來產生 diff，從不 checkout 成工作目錄或執行。
- 判定狀態的 job 沒有任何 secret。需要 secret 的 job 只在同 repo 的 PR、判定為 `REVIEW` 或 `HUMAN_GATE_REQUIRED` 時執行，
  secret 放在只限預設分支使用的 `ai-review` environment。模型金鑰與 Reviewer App 金鑰只在 `REVIEW` 時交出。
- 來自 fork 的 PR 一律不自動審查。

**Discord** 只做通知，不接受決定：`REVIEW_STARTED`、`REVIEW_VERIFIED`、`CHANGES_REQUESTED`、`HUMAN_GATE_REQUIRED`、
`REVIEW_FAILED`。

設定步驟見 `docs/AUTOMATION.md`。自動化失效時，仍可依 `REVIEWER_BOOTSTRAP.md` §8 由人手動啟動審查。
