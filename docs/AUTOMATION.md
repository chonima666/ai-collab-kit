# 自動審查與自動交付設定（v0.3）

規則見 `REVIEW_PROTOCOL.md` §9.6（自動審查）與 §10（Policy Gate 與自動交付）。本檔只講設定。流程是：

```text
建構者 AI（owner 的帳號）開 PR → 貼 AI-Review: READY
  → Reviewer App 審查（CHANGES_REQUESTED 時建構者修正，再 READY，最多 3 輪）
  → CI 通過 + Reviewer VERIFIED + Policy Gate 放行 → Merger App 自動合併
  → 否則停在 HUMAN_GATE_REQUIRED，通知 owner
```

下列步驟都要由 owner 在 GitHub、OpenAI 與 Discord 上操作，AI 無法代做。兩個開關（第 9 步）打開前，什麼都不會執行；
打開後只要缺任何一項，workflow 也會拒絕執行（fail closed）。

## 1. 身分

| 角色 | GitHub 身分 | 用途 |
| --- | --- | --- |
| 建構者（Builder AI） | owner 自己的帳號，也就是 claude.ai 連結的 GitHub 帳號（例如 `chonima666`） | 開 PR、push、貼 READY |
| 審查者（Reviewer AI） | Reviewer App，login 是 `<app-slug>[bot]`（第 2 步） | 貼出審查結果 |
| Merger App | 另一個 GitHub App（第 3 步） | 發布 `ai-collab/gate` 狀態、自動合併 |

不需要另外建立 builder 專用帳號。建構者與 owner 共用帳號，所以 GitHub 分不出哪些留言是人寫的；自動化因此不接受任何
「人的授權」留言，真正的邊界放在 `main` 的 ruleset（第 8 步）。

## 2. 建立 Reviewer App

GitHub → Settings → Developer settings → GitHub Apps → **New GitHub App**（https://github.com/settings/apps/new）：

- **GitHub App name**：例如 `chonima666-ai-reviewer`，bot login 會是 `chonima666-ai-reviewer[bot]`
- **Homepage URL**：任意，例如 repo 網址
- **Webhook**：取消勾選 Active
- **Repository permissions**（其餘全部維持 No access）：

  | 權限 | 設定 |
  | --- | --- |
  | Contents | Read-only |
  | Pull requests | Read and write |
  | Metadata | Read-only（自動） |

  不要給 Contents write、Commit statuses、Administration、Secrets、Workflows 或任何 merge／bypass 相關權限。
- **Where can this GitHub App be installed**：Only on this account

建立後：記下 **App ID** 與 bot login；按 **Generate a private key** 下載 `.pem`（不要放進任何 repo）；
左側 **Install App** → Only select repositories → `ai-collab-kit`。

## 3. 建立 Merger App

同樣在 **New GitHub App** 建立第二個 App，例如 `chonima666-ai-merger`：

- **Webhook**：取消勾選 Active
- **Repository permissions**（其餘全部維持 No access）：

  | 權限 | 設定 |
  | --- | --- |
  | Contents | Read and write（合併需要） |
  | Pull requests | Read and write |
  | Commit statuses | Read and write（發布 `ai-collab/gate`） |
  | Metadata | Read-only（自動） |

- **Where can this GitHub App be installed**：Only on this account

建立後：記下 **App ID**，下載 private key，安裝到 `ai-collab-kit`。

**為什麼要另一個 App**：Reviewer App 維持只讀程式碼、只寫 review，不能合併。狀態也不能用 workflow 內建的
GitHub Actions token 發布，因為 PR 可以加入自己的 workflow，以同樣的 GitHub Actions 身分發布同名狀態。
Merger App 的金鑰只在限定 `main` 的 environment 裡，PR 拿不到，所以 ruleset 可以指定「只認 Merger App 發布的狀態」。

## 4. OpenAI

1. 建立 API key：https://platform.openai.com/api-keys
2. 確認 API 額度或 billing：https://platform.openai.com/settings/organization/billing/overview
   ChatGPT 訂閱、API 額度與 API 可用的模型是三件分開的事。
3. 選模型。`ai-review.sh` 呼叫 `/v1/chat/completions`，帶 system 與 user 訊息；填入前先用同一把 key 確認：

   ```bash
   curl -sS https://api.openai.com/v1/chat/completions \
     -H "Authorization: Bearer $OPENAI_API_KEY" -H "Content-Type: application/json" \
     -d '{"model":"<模型 ID>","messages":[{"role":"system","content":"ping"},{"role":"user","content":"reply OK"}]}'
   ```

   回覆有 `choices[0].message.content` 才代表可用；401、429 通常是 key 或額度問題。

## 5. 建立 `ai-review` environment

Repo → Settings → Environments → **New environment**，名稱 `ai-review`：

- **Deployment branches and tags**：選 **Selected branches and tags**，只加入 `main`。
  這和 workflow 的 trigger 相容：`issue_comment` 與 `workflow_run` 的 `GITHUB_REF` 永遠是預設分支；
  `workflow_dispatch` 則是「Use workflow from」選的分支，手動執行時要選 `main`，選其他分支會被 environment 擋下。
- **Environment secrets**：

  | 名稱 | 內容 |
  | --- | --- |
  | `OPENAI_API_KEY` | 第 4 步的 API key |
  | `AICK_REVIEWER_PRIVATE_KEY` | Reviewer App `.pem` 的完整內容 |
  | `AICK_MERGER_PRIVATE_KEY` | Merger App `.pem` 的完整內容 |
  | `AICK_DISCORD_WEBHOOK` | 第 6 步的 webhook URL（選配） |

- **Environment variables**：

  | 名稱 | 內容 |
  | --- | --- |
  | `AICK_REVIEWER_APP_ID` | Reviewer App 的 App ID |
  | `AICK_REVIEWER_MODEL` | 第 4 步確認可用的模型 ID |
  | `AICK_MERGER_APP_ID` | Merger App 的 App ID |

secret 不要設在 repo 層級：`ci.yml` 在 `pull_request` 事件上執行的是 PR 分支上的 workflow 檔，建構者可以在 PR 裡修改它，
repo 層級的 secret 會被這種未經審查的 workflow 讀到。三個 variable 不是機密，放在這裡只是讓設定集中。

## 6. Discord webhook（選配）

Discord 頻道 → 編輯頻道 → 整合 → Webhook → **新 Webhook** → 複製網址 → 存成第 5 步的 `AICK_DISCORD_WEBHOOK`。
Discord 只收通知，不接受任何決定。

## 7. 填寫 `project.yaml`

`.ai-collab/project.yaml`（安裝了 kit 的專案；kit repo 自己的也在同一個位置）：

```yaml
identities:
  builder: "chonima666"
  reviewer: "chonima666-ai-reviewer[bot]"

policy_gate:
  human_paths:          # 內建的 .github/、.ai-collab/、CLAUDE.md、AGENTS.md 不必列
    - "src/auth/*"

auto_merge:
  required_checks:      # 必須在 PR head 上成功的 GitHub Actions check 名稱
    - "test"
```

這個檔案在 `.ai-collab/` 下，所以修改它的 PR 一律停在 Human Gate，由 owner 合併。

## 8. `main` 的 ruleset

Repo → Settings → Rules → Rulesets → **New ruleset** → New branch ruleset：

| 設定 | 值 |
| --- | --- |
| Enforcement status | Active |
| Bypass list | 空白 |
| Target branches | Include default branch |
| Restrict deletions | 開啟 |
| Block force pushes | 開啟 |
| Require a pull request before merging | 開啟；Required approvals 為 0 |
| Require status checks to pass | 開啟，加入 CI 的每個 check（kit repo 是 `test (ubuntu-latest)`、`test (macos-latest)`），以及 `ai-collab/gate`，來源選 Merger App |
| Require branches to be up to date before merging | 開啟 |

另外在 Settings → General → Pull Requests 確認 **Allow merge commits** 已開啟，自動合併使用 merge commit。

「Require branches to be up to date」必須開啟：否則兩個各自在舊 `main` 上通過的 PR 可以先後合併，而兩者合在一起的狀態從沒跑過 CI。
Policy Gate 也會檢查同一件事（`base_outdated`）。代價是 `main` 前進後，其他 PR 要先合併 `main`、重跑 CI 並重新審查
（`REVIEW_PROTOCOL.md` §10.4）。

ruleset 生效後，沒有 `ai-collab/gate` 成功狀態的 PR 誰都無法合併，包括 owner。Human Gate 的例外處理見
`REVIEW_PROTOCOL.md` §10.5。

## 9. 開關

Repo → Settings → Secrets and variables → Actions → **Variables** → **repository variables**：

| 名稱 | 值 | 作用 |
| --- | --- | --- |
| `AICK_AUTO_REVIEW` | `true` | 開啟自動審查 |
| `AICK_AUTO_MERGE` | `true` | 開啟自動交付；只在 `AICK_AUTO_REVIEW` 也是 `true` 時有效 |

兩者必須是 repo 層級，因為判定狀態的 job 不使用 environment。

## 10. 建議的啟用順序與端對端測試

1. 完成第 2～7 步（`project.yaml` 的 PR 由 owner 合併）。
2. 只打開 `AICK_AUTO_REVIEW`。開一個只改文件的測試 PR，建構者貼 `AI-Review: READY` 與 `Ready-SHA:`。
   預期：ai-review 的 `state` job 判定 `REVIEW`，`act` job 貼出一則由 Reviewer App 發出、帶 `Risk-Flags:` 的 review。
   審查者的 prompt 會帶有 repository、PR 與 Ready-SHA 上 required checks 的可信資料（`REVIEW_PROTOCOL.md` §9.6），
   這些資料由 workflow 內建的唯讀 token（`checks: read`）讀取，不需要額外設定。CI 還在跑不會讓審查標 `insufficient-evidence`。
3. 設定第 8 步的 ruleset，再打開 `AICK_AUTO_MERGE`。Actions → ai-review → **Run workflow**（分支選 `main`），
   輸入同一個 PR 的編號。預期：`deliver` job 發布 `ai-collab/gate` = success，Merger App 合併。
   之後的 PR 不需要手動執行：審查貼出後與 CI 成功後都會自動判定。
4. 開一個改動 `.github/` 的測試 PR，走完審查。預期：`ai-collab/gate` = failure，Discord 收到 `HUMAN_GATE_REQUIRED`。
5. **反向測試**：在建構者的 session 嘗試直接合併第 4 步的 PR。預期：GitHub 拒絕。
   這一步確認建構者使用的憑證無法繞過 ruleset；若沒有被拒絕，自動交付的邊界不成立，請先關閉 `AICK_AUTO_MERGE`。

## 安裝到其他專案

把 kit repo 的 `.github/workflows/ai-review.yml` 複製到專案的 `.github/workflows/`，再在該專案重做第 2～9 步。
workflow 會自動使用 `.ai-collab/kit/scripts/` 下的腳本。專案的 CI workflow 名稱不是 `ci` 時，要同步修改
`workflow_run.workflows`，並把 CI 的 check 名稱填入 `auto_merge.required_checks`。

## 什麼情況會拒絕執行

| 情況 | 結果 |
| --- | --- |
| `AICK_AUTO_REVIEW` 不是 `true` | workflow 不執行 |
| `AICK_AUTO_MERGE` 不是 `true` | 只審查，不發布 `ai-collab/gate`，不合併 |
| `identities` 有空白、兩者相同，或 `reviewer` 不是 `<app-slug>[bot]` | 判定 job 失敗，不呼叫模型 |
| PR 來自 fork | 不進入需要 secret 的步驟；腳本也再擋一次 |
| 缺少 `OPENAI_API_KEY`、`AICK_REVIEWER_MODEL` 或 Reviewer App 金鑰 | `REVIEW_FAILED`，不呼叫模型、不貼文 |
| 模型 API 錯誤、逾時（`AICK_MODEL_TIMEOUT`，預設 600 秒）或輸出不符合格式 | `REVIEW_FAILED`，不貼文 |
| Reviewer App 貼文失敗，或貼文者不是 `identities.reviewer` | `REVIEW_FAILED`，workflow 失敗 |
| `policy_gate` 或 `auto_merge.required_checks` 缺少、讀不懂或是空的 | 交付 job 失敗，不發布狀態、不合併 |
| 缺少 Merger App 金鑰、狀態貼不出去，或 GitHub 拒絕合併 | `AUTO_MERGE_FAILED`，不合併 |

## 剩下的風險

- **建構者與 owner 共用帳號**：owner 在 GitHub 上能做的事，建構者的憑證技術上也可能做得到，例如修改 ruleset。
  實際能力取決於 claude.ai 連結 GitHub 時授予的權限。第 10 步的反向測試用來確認這一點；ruleset 的 bypass 名單必須保持空白。
- **Prompt injection**：模型看得到 PR 的內容，PR 可能試圖讓模型回覆 `VERIFIED` 與 `Risk-Flags: none`。
  模型無法放行受保護的路徑，也改不了輪數、身分或 CI 結果；但一般路徑上的 PR 若同時騙過模型與 CI，就會自動合併。
  這是自動交付接受的風險，用 `policy_gate.human_paths` 把敏感目錄列全可以縮小它。
- **路徑規則只涵蓋列出的路徑**：專案必須把認證、migration、基礎設施、計費等目錄列進 `policy_gate.human_paths`。
- **Merger App 有 Contents write**：它的金鑰只在限定 `main` 的 environment 中，只由預設分支上的腳本使用。
