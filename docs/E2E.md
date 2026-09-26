# 端對端驗收紀錄

`docs/AUTOMATION.md` §10 的啟用順序，逐項記錄實測結果。每一項都要在真實的 GitHub、GitHub App 與 OpenAI 上執行，
不能用 fake-curl 測試或文件推定代替。任一項不成立時，先關閉對應的開關（`AICK_AUTO_MERGE`，必要時連同
`AICK_AUTO_REVIEW`），修正後重測。

結果欄填：日期、PR 或 workflow run 的連結、實際觀察到的行為。未執行的項目保持「未驗證」。

建構者與 owner 共用同一個 GitHub 帳號（`REVIEW_PROTOCOL.md` §8.1），所以「建構者做不到」只能用建構者實際使用的憑證去嘗試，
看 GitHub 是否拒絕；owner 在設定頁面親自做的事，不在技術邊界之內。

## 第一階段：自動審查（只開 `AICK_AUTO_REVIEW`）

| # | 項目 | 預期 | 結果 |
| --- | --- | --- | --- |
| A1 | 建構者貼 `AI-Review: READY` 觸發 workflow | `state` job 判定 `REVIEW` | 2026-09-26 通過：PR #6 的 READY 觸發 [run 36236073990](https://github.com/chonima666/ai-collab-kit/actions/runs/36236073990)，`state` 判定 `REVIEW`（`review_round=1`、`scope=full`） |
| A2 | Reviewer App 貼出審查 | review 作者是 `chonima666-ai-reviewer[bot]`，帶 `Review-Status`、`Reviewed-SHA`、`Open-Findings`、`Risk-Flags` | 2026-09-26 通過：PR #6 review 5325622377，作者 `chonima666-ai-reviewer[bot]`，模型 `gpt-6-sol`，四個欄位齊全（`CHANGES_REQUESTED`、`R1-01`） |
| A3 | 同一個 SHA 再貼一次 READY | `NO_ACTION`，不呼叫模型 | 未驗證 |
| A4 | `AICK_AUTO_MERGE` 未開啟 | `deliver` job 不執行，沒有 `ai-collab/gate` 狀態 | 2026-09-26 通過：[run 36236073990](https://github.com/chonima666/ai-collab-kit/actions/runs/36236073990) 的 `deliver` job 為 skipped |
| A5 | Reviewer App 的金鑰無效 | 不呼叫模型、不貼文，`REVIEW_FAILED` | 2026-09-26 通過：[run 36228655865](https://github.com/chonima666/ai-collab-kit/actions/runs/36228655865) 因 App ID 格式錯誤與 private key 無效取不到 token，`orchestrate.sh` 以 `REVIEW_FAILED` 結束（exit 2），PR 上沒有任何審查 |

## 第二階段：自動交付（ruleset 設好後開 `AICK_AUTO_MERGE`）

| # | 安全邊界 | 預期 | 結果 |
| --- | --- | --- | --- |
| B1 | Merger App 發出的 `ai-collab/gate` | ruleset 認定為正確來源，低風險 PR 自動合併 | 未驗證 |
| B2 | 建構者或 GitHub Actions 發出同名 `ai-collab/gate` success | ruleset 仍拒絕合併 | 未驗證 |
| B3 | 建構者以 `chonima666` 的連結直接合併 Human Gate PR | GitHub 拒絕 | 未驗證 |
| B4 | 建構者直接 push `main` | GitHub 拒絕 | 未驗證 |
| B5 | 建構者的 session（`chonima666` 的 claude.ai 連結）嘗試修改 ruleset 或 bypass 名單 | GitHub 拒絕；若沒有被拒絕，記錄為已知限制：建構者與 owner 共用帳號，ruleset 的變更只能靠 owner 親自決定，不能當作技術邊界 | 未驗證 |
| B5a | ruleset 的 bypass 名單 | 空白；Human Gate 例外處理後已移除 | 未驗證 |
| B6 | Merger App 合併 | 只在 gate 允許且 head SHA 未改變時成功 | 未驗證 |
| B7 | Reviewer App 寫入程式碼或合併 | 做不到 | 未驗證 |
| B8 | 建構者的 workflow 從非 `main` 分支取用 `ai-review` environment | 被 environment 的分支限制擋下 | 未驗證 |
