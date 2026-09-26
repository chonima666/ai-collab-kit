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
| A6 | 同一個發現在 2 個不同 SHA 上都未結案（LG-05） | 下一個 READY 判定 `HUMAN_GATE_REQUIRED`（`repeated_unresolved_finding`），不呼叫模型、不建立 App token，由 owner 決定 | 2026-09-26 通過，證據 E4 |
| A7 | 審查者的可信資料（v0.3.1） | prompt 帶 repository 全名與 Ready-SHA 上 required checks 的狀態，審查內容引用得到 | 2026-09-26 通過，證據 E5 |
| A8 | READY 時 CI 仍在執行（v0.3.1） | 審查照常完成，不因 CI 未完成標 `insufficient-evidence` | 2026-09-26 通過，證據 E5 |
| A9 | CI 通過 + `VERIFIED` + `Risk-Flags: none` | Policy Gate 判定 `AUTO_MERGE_ALLOWED` | 2026-09-26 以真實資料離線執行 `policy-gate.sh` 通過，證據 E5；實際自動合併見 B1 |

## 第二階段：自動交付（ruleset 設好後開 `AICK_AUTO_MERGE`）

| # | 安全邊界 | 預期 | 結果 |
| --- | --- | --- | --- |
| B1 | Merger App 發出的 `ai-collab/gate` | ruleset 認定為正確來源，低風險 PR 自動合併 | 2026-09-26 通過，證據 E6 |
| B2 | 建構者或 GitHub Actions 發出同名 `ai-collab/gate` success | ruleset 仍拒絕合併 | 未驗證 |
| B3 | 建構者以 `chonima666` 的連結直接合併 Human Gate PR | GitHub 拒絕 | 未驗證 |
| B4 | 建構者直接 push `main` | GitHub 拒絕 | 未驗證 |
| B5 | 建構者的憑證能否修改 ruleset（唯讀檢查，不實際嘗試修改） | owner 在 GitHub → Settings → Applications → Installed GitHub Apps 查看 claude.ai 連結所用 App 的權限：Administration 不是 Read and write。若是，記錄為已知限制：ruleset 只能靠 owner 親自決定，不是技術邊界 | 未驗證 |
| B5a | ruleset 的 bypass 名單 | 空白；Human Gate 例外處理後已移除 | 未驗證 |
| B6 | Merger App 合併 | 只在 gate 允許且 head SHA 未改變時成功 | 部分通過：gate 未允許時不合併（證據 E6）；head SHA 改變的情況未驗證 |
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

**E4（A6）**：PR #6 的 R1-01 在 `dc0af6d`（review 5325622377）與 `109ead8`（review 5325626897）兩個 SHA 上都未結案。
對 `1069330` 的 READY 觸發 [run 36236331688](https://github.com/chonima666/ai-collab-kit/actions/runs/36236331688)，`act` job 印出：

```text
limit=2
ready=1069330ce4ccc9765af20b26685170cd6be2e132
last_reviewed=109ead810453f9a644ba1bd4f09d36fc48ecd0b8
disputed_findings=R1-01
HUMAN_GATE_REQUIRED: no model call
```

建立 Reviewer App token 的步驟是 skipped（只在 `REVIEW` 時執行），`deliver` job 也是 skipped。

**這不是審查失敗**：Loop Guard 依設計停止 AI 之間的自動迭代，把決策交給 owner。之後沒有再請求第 3 輪審查，也沒有為了取得
`VERIFIED` 而延長輪數或另開管道（LG-06a、LG-06b）。PR #6 是否合併由 owner 在 Human Gate 決定。

**E5（A7～A9）**：PR #8（只改 `README.md`）的 READY 觸發 [run 36238402253](https://github.com/chonima666/ai-collab-kit/actions/runs/36238402253)，
`act` job 印出 `decision=REVIEW`、`ready=a3ff704aba25dd94d3f5e98fa3d51e5853933606`，最後 `posted: VERIFIED, Open-Findings: none`。
- Reviewer App 的 review 5325744613 在 11:18:47 貼出，開頭寫「儲存庫 `chonima666/ai-collab-kit`，PR #8」，並寫「可信資料顯示兩項必要 CI 檢查仍在執行，不能視為已通過」，
  結尾是 `Review-Status: VERIFIED`、`Risk-Flags: none`。
- 同一個 head 的 CI（[run 36238398580](https://github.com/chonima666/ai-collab-kit/actions/runs/36238398580)）在 11:19:19 才全部完成，所以審查時 CI 確實還在執行。
- 以 GitHub API 取得 PR #8 的 pull request、留言、review 與 `a3ff704` 的 check-runs（兩項都是 `github-actions` 的 `completed`/`success`），
  以及當時 `main` 的 tip `9b6439f`，依序執行 `pr-state.sh`（檔案模式）與 `policy-gate.sh`，輸出 `decision=AUTO_MERGE_ALLOWED`、`reason=all_conditions_met`。
  當時 `AICK_AUTO_MERGE` 未開啟，`deliver` job 是 skipped，PR #8 由 owner 手動合併。

重現 A9 的指令（公開 repo 的唯讀 API，不需要 token；在本 repo 的 checkout 中執行；`$main_wt` 是 repo 外的暫存目錄，放 `base_tip` 的 worktree，
所以 `scripts/` 與 `.ai-collab/project.yaml` 都取自當時的 `main`）：

```bash
A=https://api.github.com/repos/chonima666/ai-collab-kit
head=a3ff704aba25dd94d3f5e98fa3d51e5853933606 base_tip=9b6439fe647f2bab58fea3fbe3eaa1abab7fa02d
# PR #8 之後已合併；還原成 A9 當下的狀態（open、未合併），其餘欄位照 API 原樣
curl -sS "$A/pulls/8" | jq '.state = "open" | .merged = false | .merged_at = null' > pr.json
curl -sS "$A/issues/8/comments?per_page=100" > comments.json
curl -sS "$A/pulls/8/reviews?per_page=100" > reviews.json
curl -sS "$A/commits/$head/check-runs?per_page=100" > checks.json
git fetch origin "$head" && git worktree add --detach "$main_wt" "$base_tip"
"$main_wt"/scripts/pr-state.sh --pr-file pr.json --comments-file comments.json --reviews-file reviews.json --root "$main_wt" > state
git diff --no-renames --name-only -z "$base_tip...$head" > paths
"$main_wt"/scripts/policy-gate.sh --state state --paths paths --checks checks.json --base-tip "$base_tip" --root "$main_wt"
```

PR #8 已合併，不還原 `state` 時 Policy Gate 在第一關停在 `NOT_READY`（`pr_not_open`），這也是預期行為。
還原後，`pr-state.sh` 以 exit 10 結束（`decision=NO_ACTION`，因為這個 Ready-SHA 已經審查過），輸出 `pr_head=$head`、`same_repo=true`、
`head_review=VERIFIED`、`head_risk_flags=` 空白；`paths` 只有 `README.md`；`checks.json` 中兩項 required checks 都是
`app.slug=github-actions`、`head_sha=$head`、`completed`/`success`。`policy-gate.sh` 以 exit 0 結束：

```text
decision=AUTO_MERGE_ALLOWED
reason=all_conditions_met
head=a3ff704aba25dd94d3f5e98fa3d51e5853933606
```

之後 `main` 的 tip 會前進，但上面的指令固定使用當時的 `base_tip`，所以結果可以重現。2026-09-26 已照這段指令重跑，得到相同輸出。

**E6（B1、B6）**：ruleset `main`（id 24040024）的 required status checks 是 `test (ubuntu-latest)`、`test (macos-latest)`
（integration 15368，GitHub Actions）與 `ai-collab/gate`（integration 5085385，Merger App），`strict_required_status_checks_policy: true`；
可用 `GET /repos/chonima666/ai-collab-kit/rules/branches/main` 核對。
- 在 ruleset 加入 `ai-collab/gate` 之前，owner 對 PR #10 手動執行 ai-review（[run 36243689759](https://github.com/chonima666/ai-collab-kit/actions/runs/36243689759)），
  Merger App 發出 `ai-collab/gate` = pending（`NOT_READY: not_reviewed`），PR 沒有被合併。
  前一次執行（[run 36241330416](https://github.com/chonima666/ai-collab-kit/actions/runs/36241330416)）的 `AICK_MERGER_APP_ID` 填錯，
  token 建立失敗，`deliver.sh` 印出 `AUTO_MERGE_FAILED: the Merger App token is not available`，沒有發布狀態也沒有合併。
- PR #10 的第 1 輪審查是 `CHANGES_REQUESTED`，Merger App 隨即發出 `ai-collab/gate` = pending（`NOT_READY: changes_requested`），沒有合併。
- PR #11（只改 `README.md`）：READY 後，Reviewer App 貼出 `VERIFIED`、`Risk-Flags: none`。13:29:29 macOS CI 還在執行，
  Merger App 發出 pending（`NOT_READY: ci_pending pending_checks=test (macos-latest)`）。CI 完成後的
  [run 36245358191](https://github.com/chonima666/ai-collab-kit/actions/runs/36245358191)（`workflow_run`）在 13:30:06 發出
  success（`AUTO_MERGE_ALLOWED: all_conditions_met`），13:30:08 PR #11 由 `chonima666-ai-merger[bot]` 合併，merge commit `1a92eb8`。
  可用 `GET /repos/chonima666/ai-collab-kit/pulls/11` 與 `GET /repos/chonima666/ai-collab-kit/commits/ec074e2ae871a3884dc1b244d72d7bdcba6a2a7a/statuses` 核對。
