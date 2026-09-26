# 端對端驗收紀錄

`docs/AUTOMATION.md` §10 的啟用順序，逐項記錄實測結果。每一項都要在真實的 GitHub、GitHub App 與 OpenAI 上執行，
不能用 fake-curl 測試或文件推定代替。任一項不成立時，先關閉對應的開關（`AICK_AUTO_MERGE`，必要時連同
`AICK_AUTO_REVIEW`），修正後重測。

結果欄填：日期、PR 或 workflow run 的連結、實際觀察到的行為。未執行的項目保持「未驗證」。

建構者與 owner 共用同一個 GitHub 帳號（`REVIEW_PROTOCOL.md` §8.1），所以「建構者做不到」不能靠帳號本身證明。
會改動安全設定的操作（ruleset、bypass 名單）一律只做唯讀檢查，不讓建構者實際嘗試；owner 在設定頁面親自做的事，
不在技術邊界之內。

## 第一階段：自動審查（只開 `AICK_AUTO_REVIEW`）

| # | 項目 | 預期 | 結果 |
| --- | --- | --- | --- |
| A1 | 建構者貼 `AI-Review: READY` 觸發 workflow | `state` job 判定 `REVIEW` | 2026-09-26 通過，證據 E1 |
| A2 | Reviewer App 貼出審查 | review 作者是 `chonima666-ai-reviewer[bot]`，帶 `Review-Status`、`Reviewed-SHA`、`Open-Findings`、`Risk-Flags` | 2026-09-26 通過：PR #6 review 5325622377 與 5325626897，作者都是 `chonima666-ai-reviewer[bot]`，四個欄位齊全 |
| A3 | 同一個 SHA 再貼一次 READY | `NO_ACTION`，不呼叫模型 | 未驗證 |
| A4 | `AICK_AUTO_MERGE` 未開啟 | `deliver` job 不執行，沒有 `ai-collab/gate` 狀態 | 2026-09-26 通過，證據 E2 |
| A5 | Reviewer App 的金鑰無效 | 不呼叫模型、不貼文，`REVIEW_FAILED` | 2026-09-26 通過，證據 E3 |

## 第二階段：自動交付（ruleset 設好後開 `AICK_AUTO_MERGE`）

| # | 安全邊界 | 預期 | 結果 |
| --- | --- | --- | --- |
| B1 | Merger App 發出的 `ai-collab/gate` | ruleset 認定為正確來源，低風險 PR 自動合併 | 未驗證 |
| B2 | 建構者或 GitHub Actions 發出同名 `ai-collab/gate` success | ruleset 仍拒絕合併 | 未驗證 |
| B3 | 建構者以 `chonima666` 的連結直接合併 Human Gate PR | GitHub 拒絕 | 未驗證 |
| B4 | 建構者直接 push `main` | GitHub 拒絕 | 未驗證 |
| B5 | 建構者的憑證能否修改 ruleset（唯讀檢查，不實際嘗試修改） | owner 在 GitHub → Settings → Applications → Installed GitHub Apps 查看 claude.ai 連結所用 App 的權限：Administration 不是 Read and write。若是，記錄為已知限制：ruleset 只能靠 owner 親自決定，不是技術邊界 | 未驗證 |
| B5a | ruleset 的 bypass 名單 | 空白；Human Gate 例外處理後已移除 | 未驗證 |
| B6 | Merger App 合併 | 只在 gate 允許且 head SHA 未改變時成功 | 未驗證 |
| B7 | Reviewer App 寫入程式碼或合併 | 做不到 | 未驗證 |
| B8 | 建構者的 workflow 從非 `main` 分支取用 `ai-review` environment | 被 environment 的分支限制擋下 | 未驗證 |

## 證據

以下摘錄自 workflow 紀錄與 GitHub API，每一項都可以用連結或同樣的查詢重新核對。

**E1（A1）**：[run 36236073990](https://github.com/chonima666/ai-collab-kit/actions/runs/36236073990) 由 PR #6 的 READY 留言（`issue_comment`）觸發。`state` job 成功；`act` job 印出的狀態：

```text
decision=REVIEW
reason=new_ready_sha
rounds=0
limit=3
ready=dc0af6d0a8065bdf62cbb70e552c0c2f351a5c74
review_round=1
scope=full
```

同一個 job 最後印出 `posted: CHANGES_REQUESTED, Open-Findings: R1-01`。

**E2（A4）**：
- [run 36236073990](https://github.com/chonima666/ai-collab-kit/actions/runs/36236073990)：三個 job 的結論是 `state` success、`act` success、`deliver` skipped。
- CI 完成後觸發的 [run 36236221338](https://github.com/chonima666/ai-collab-kit/actions/runs/36236221338)（`workflow_run`）整個是 skipped。
- 2026-09-26 查詢 PR #6 head `109ead8` 的 commit statuses：`total_count: 0`，沒有 `ai-collab/gate`。

**E3（A5）**：[run 36228655865](https://github.com/chonima666/ai-collab-kit/actions/runs/36228655865) 的 `act` job：
- `create-github-app-token` 步驟失敗：`Failed to create token … Invalid keyData`，重試 4 次；該步驟設有 `continue-on-error`，所以 token 為空。
- `orchestrate.sh` 印出 `REVIEW_FAILED: the Reviewer App token is not available` 後以 exit 2 結束。
- 紀錄裡沒有 `REVIEW_STARTED`，也沒有 `posted:` 這一行。
- `scripts/orchestrate.sh` 在第 84 行檢查 token，第 93、94 行之後才通知 `REVIEW_STARTED` 並呼叫 `ai-review.sh`（模型呼叫在其中）。所以 token 為空時不會呼叫模型。
- 該次 PR #6 上沒有出現任何審查。
