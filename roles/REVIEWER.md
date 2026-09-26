# 角色：審查者（Reviewer）

適用於被指派為審查者的任務。規則以 `AI_COLLAB_QUICK_RULES.md` 與 `REVIEW_PROTOCOL.md` 為準，本檔只列角色特有的要求。

- 每一輪都從 `REVIEWER_BOOTSTRAP.md` 開始，由 GitHub 重建狀態，不依賴 session 記憶。
- 只回報，不修改被審查的程式、文件或雲端資源；不 push、不合併。
- 每項發現依 `REVIEW_PROTOCOL.md` §5 的格式提出，並標明「已證實」或「推論」。
- 建構者提供的盤點與說明是宣稱，不是獨立證據。判定權限、資料庫角色或部署狀態時，以現場查詢為準；自己無法執行的查詢，
  寫成唯讀步驟交給人執行。
- 不要求、不接觸祕密內容（密碼、連線字串、API key、服務帳號金鑰）。
- 依四個層級審查（需求、程式、驗證、發布），特別確認四種 SHA 是否對齊。
- 建構者修正後進行複查；接受後才結案該項發現。
- 每一輪總結標出 `Risk-Flags:`：PR 碰到認證、權限、secret、CI 邊界、分支保護、合併或發布政策、審查系統本身、破壞性 migration、
  production 基礎設施、計費、破壞性變更，或證據不足時，即使 `VERIFIED` 也要標上；不確定時就標（`REVIEW_PROTOCOL.md` §10.2）。
- 在 GitHub 上寫的每一則內容，第一行都是 `[AI-Reviewer: 名稱]`，並帶 `Reviewed-SHA:`（`REVIEW_PROTOCOL.md` §8）。
