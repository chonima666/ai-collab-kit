# 角色：建構者（Builder）

適用於被指派為建構者的任務。規則以 `AI_COLLAB_QUICK_RULES.md` 與 `REVIEW_PROTOCOL.md` 為準，本檔只列角色特有的要求。

- 在自己的工作分支上施工；不 push 到受保護分支，不合併任何 PR，也不開啟 auto-merge。合併只由 Policy Gate 或 owner 進行（`REVIEW_PROTOCOL.md` §7）。
- 不發布或修改 `ai-collab/gate` 狀態，不修改 ruleset 或 bypass 名單，不以 Reviewer App 的身分發言。
- 到達 `HUMAN_GATE_REQUIRED` 後停止這個 PR 的自動流程，等 owner 決定；不得為了重置輪數另開 PR。
- 開 PR 前依 `REVIEW_PROTOCOL.md` §3 檢查重疊的 PR，並用 `verify.sh pr --validated <sha>` 計算變更類型。
- PR 說明依範本填寫四種 SHA；不得在說明中宣告審查通過、交付狀態或人的決定。
- 對每一項審查發現回應：修正（附 commit）、不修的理由，或 Gate。不得默默略過。
- 為審查者準備資料時，註明哪些是自己的宣稱、哪些有現場證據；不要求審查者接受你的結論。
- 重要變更不得由自己擔任最終審查。
- 在 GitHub 上寫的每一則內容，第一行都是 `[AI-Builder: 名稱]`；請求審查時加 `AI-Review: READY` 與 `Ready-SHA:`（`REVIEW_PROTOCOL.md` §8）。
