# AI 協作執行規則（Quick Rules）

本檔是日常執行摘要，由 ai-collab-kit 管理。完整規範以 `.ai-collab/kit/AI_COLLAB_GUIDE.md`（以下稱「守則」）為準，
PR 協作以 `.ai-collab/kit/REVIEW_PROTOCOL.md` 為準；專案設定在 `.ai-collab/project.yaml`。本檔與守則不一致時，
以守則為準，並回報差異。遇到本檔未涵蓋、規則衝突、Gate、例外或高風險情境時，必須先讀守則全文的對應章節。

本檔本身就是約束，不是參考資料：下列硬性邊界不因「詳見守則」而放寬。

## 1. 開工

- 先讀 `.ai-collab/project.yaml`，以及專案地圖中與任務相關的節點（先索引，再沿依賴展開）和最近的 HANDOFF／Mini-Handoff。
- 核對目前分支、`git status`、遠端分支與標籤、**仍開著的 PR**，以及相關節點上其他人的工作歸屬。遠端查不到時記錄此限制，不得聲稱沒有平行工作。
- 用一兩句記錄：目標、授權範圍、排除事項、可檢查的完成條件，以及任務 ID、負責人、分支、預計碰觸的節點。
- 確認自己在本任務的角色（建構者或審查者），並讀 `.ai-collab/kit/roles/` 下對應的角色檔。
- 與他人工作重疊（同檔案、同節點、同一控制流程）時，先協調再動重疊部分。
- 對話記憶與交接文字只是線索；以程式碼、測試結果與部署狀態核對現場。（守則 §1）

## 2. 硬性授權邊界

下列動作即使在已授權的任務中，也必須**就該動作本身**取得當下的明確授權，並先備妥可審查的結果：

- production 部署
- 合併共用或受保護分支（含 `main`），包括合併自己的 PR。專案啟用自動交付時，Policy Gate 放行的合併由 workflow 以 Merger App 執行（`REVIEW_PROTOCOL.md` §10），不是 AI 的動作；AI 仍不得自行合併或開啟 auto-merge
- 刪除資料或分支
- 強制覆蓋：force push、改寫已共享的歷史
- 權限邊界變更：IAM、存取控制、角色、祕密存取權、分支保護
- 建立或移動正式發布標籤。標籤一旦建立不得移動或重用；使用 annotated tag

修 bug 的授權不等於上述任何一項的授權。未取得授權前不得執行，也不得用其他指令繞過同一效果。（守則 §2）

## 3. Gate

- 涉及安全、授權、審批、計費或關鍵控制邏輯、production 資料、不可逆操作、沒有可靠復原途徑的操作、安全邊界變更，或核心前提與查證結果衝突者，都是 Gate。分類不確定時按 Gate 處理。
- Gate 未獲明確批准不得執行該部分。用守則 §3 的「Gate 授權請求卡片」提出：動作、對象、依據版本、影響、回退、選項與建議、決策人。
- 授權只對所列的動作、對象（分支／版本／環境／資料範圍）與附帶條件有效。commit、環境或對象任一改變，舊授權不可沿用，須重新取得。
- 決策（含對話中的口頭答覆）寫入追蹤紀錄：決策人、時間、動作與對象、依據 commit、條件。
- 真正的停點只有：Gate、資訊或外部依賴阻塞、環境或權限限制、需另行授權的動作、未協調的重疊工作。其他互不依賴且已授權的工作照常進行。（守則 §3）

## 4. 驗證

- 不得把「沒跑」「跑不到」「被跳過」寫成「通過」。跑不到的項目標「未驗證」或 `not_run`，並寫明原因與限制。
- 每次執行都記錄：指令、退出碼、環境、時間、commit（未提交時記錄基底 commit 與未提交變更摘要）。保存前遮蔽憑證、token、密碼、個資。
- 實作、單元、整合、staging、production 分層記錄。某層通過不代表其他層已驗證。
- 證據只對它實際執行的 commit 有效。宣稱「之後只有文件變更」時，必須用 `.ai-collab/kit/scripts/verify.sh pr --validated <sha>` 計算，不得憑印象填寫。
- 格式與靜態檢查依 `project.yaml` 的 `lint_baseline` 規則，區分既有問題與本次新增問題；不為了讓工具通過而大改範圍外的程式碼。
- 提交前執行 `project.yaml` 的必跑檢查。（守則 §6）

## 5. 失敗處理

- 以完全相同的指令與條件失敗一次後，不得無理由重跑；確有理由（例如疑似偶發的環境問題）時，先寫明理由再重跑。
- 同一方案連續失敗 3 次：停下該方案，記錄嘗試、錯誤證據與未排除的原因，重新檢查假設。
- 微調參數或改寫同一指令不算換方向，也不重置計數。只有提出新的原因假設、並說明下一次要驗證什麼，才算新方向。
- 未提交的改動先另存（stash 或備份分支）再換方向；刪除分支或捨棄改動仍需 §2 授權。提不出新假設時，列為阻塞停點並回報。（守則 §5）

## 6. 交接

- **Mini-Handoff**：短暫中斷，或同一負責人換對話接續時使用。每個任務一檔，存在 `project.yaml` 指定的目錄，只覆寫自己任務的檔案。
- **正式 HANDOFF（十二段）**：換負責人、停在真正的停點、重大里程碑，或可能長期擱置時使用。格式見守則 §7。
- **微型任務**：不中斷、同次完成的單一小變更，免建 Mini-Handoff，在 commit 或簡短回報記錄受影響節點與驗證結果。規模小不降低風險分級。
- 中斷前確認現場不在危險的半途（例如服務被縮到 0、部署做一半）；若是，Handoff 第一行寫明異常狀態與回退方法。（守則 §4.3、§5、§7）

## 7. PR 協作（建構者 → 審查者 → Policy Gate）

- GitHub PR 是正式的協作與決策紀錄。建構者開 PR、修正、逐項回應；審查者只回報，不修改被審查的內容；
  Policy Gate 放行的 PR 自動合併，其餘停在 `HUMAN_GATE_REQUIRED` 由 owner 處理。
- PR 說明依範本填寫四種 SHA：Current HEAD、Code under review、Validated commit、Deployed commit。
- 審查狀態以 Reviewer App 的 review 為準，交付狀態以 `ai-collab/gate` 與合併紀錄為準；PR 說明只能引用，不能自行宣告。
- 審查發現須附檔案、commit、重現或推理路徑、影響，並標「已證實」或「推論」。建構者對每一項都要回應：修正（附 commit）、不修的理由，或列為 Gate。
- AI 在 GitHub 上寫的每一則說明、留言與 review，第一行必須是角色標頭 `[AI-Builder: 名稱]` 或 `[AI-Reviewer: 名稱]`；審查者加 `Reviewed-SHA:`，建構者請求審查時加 `AI-Review: READY` 與 `Ready-SHA:`。
- 審查者每一輪都依 `REVIEWER_BOOTSTRAP.md` 從 GitHub 重建狀態，不依賴 session 記憶。
- 開 PR 前檢查仍開著的 PR 是否與本次變更重疊。（`REVIEW_PROTOCOL.md` §3、§8）
- Policy Gate：CI 通過、Reviewer 在目前 head 上 `VERIFIED`、`Risk-Flags: none`、沒有改動受保護路徑時，由 Merger App 自動合併。`.github/`、`.ai-collab/`、`CLAUDE.md`、`AGENTS.md` 與 `policy_gate.human_paths` 的變更，以及任何風險旗標，一律 `HUMAN_GATE_REQUIRED`。
- AI 不得發布或修改 `ai-collab/gate`、不得開啟 auto-merge、不得修改 ruleset 或 bypass 名單。（`REVIEW_PROTOCOL.md` §10）

## 8. Loop Guard（審查輪數上限）

- 一輪 = 一個新的 Ready-SHA 收到審查者一次正式的 `Review-Status:`。同一個 SHA 不重複審查，也不增加輪數；任何動作都不重置計數。
- 第一輪之後只審 `Last-Reviewed-SHA..Ready-SHA`，加上仍未結案的發現。審查者每輪總結都要附 `Open-Findings:`。
- 最多 `project.yaml` 的 `loop_guard.max_review_rounds` 輪（預設 3）。之後的新 Ready-SHA 一律 `HUMAN_GATE_REQUIRED`；同一個發現在 2 個不同 Ready-SHA 上都未結案時也是。輪數用完不等於通過。
- 喚醒審查者前，用 `.ai-collab/kit/scripts/verify.sh review-state` 判定；結果不是 `REVIEW` 就不審。
- 自動審查只在 `project.yaml` 的 `identities:` 設定建構者帳號與另一個 Reviewer App 時執行，否則拒絕執行。READY 只認建構者、審查結論只認 Reviewer App；PR 說明裡的宣稱不算。建構者 AI 不得以 Reviewer App 的身分發言。（`REVIEW_PROTOCOL.md` §8.1、§9.6）
- **AI 不得修改、停用、繞過、重置或延長 Loop Guard**，包括修改限制值、自行多跑一輪、用留言重置計數、為了重置輪數另開 PR。沒有任何留言能延長輪數；到達 `HUMAN_GATE_REQUIRED` 後這個 PR 的自動流程停止，由 owner 處理。（`REVIEW_PROTOCOL.md` §9）

## 9. 必須讀守則全文的情境

- Gate 或需另行授權的動作（§2、§3）
- 任何部署，含 staging（§8，以及 `project.yaml` 的環境說明）
- 回退、migration、資料修改（§8 回退計畫）
- Hotfix／緊急修復（§8）
- 刪除、覆蓋等破壞性操作（§2、§8）
- 衝突解決、分支整合（§8 整合與衝突處置）
- 新建或大幅調整專案地圖（§4）
- 本檔與守則不一致，或規則不確定
