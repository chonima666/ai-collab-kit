# 自動審查設定（v0.2）

自動審查的規則見 `REVIEW_PROTOCOL.md` §9.6。本檔只講設定：建構者 AI 貼出 `AI-Review: READY` 之後，
GitHub Actions 會重建狀態、套用 Loop Guard，判定為 `REVIEW` 時才呼叫 OpenAI API 審查，並以 Reviewer App 的身分貼回結果。

下列步驟都要由 owner 在 GitHub、OpenAI 與 Discord 上操作，AI 無法代做。**全部完成前不要打開 `AICK_AUTO_REVIEW`**。
即使打開了，只要缺任何一項，workflow 也會拒絕執行（fail closed）。

## 1. 身分：三個不同的 GitHub login

| 角色 | 建議 | 權限 |
| --- | --- | --- |
| human | owner 自己的帳號（例如 `chonima666`） | Admin；唯一會合併、寫 `Human-Decision:` 的帳號 |
| builder | 給建構者 AI 專用的另一個 GitHub 帳號（例如 `chonima666-builder`） | 以 collaborator 身分邀請，只給 **Write**，不給 Admin |
| reviewer | 第 2 步建立的 Reviewer App，login 是 `<app-slug>[bot]` | 見第 2 步 |

**為什麼 builder 需要另一個帳號**：Claude Code on the web 用的是你在 claude.ai 連結的 GitHub 帳號發言與 push。
如果連結的是 owner 帳號，建構者寫的每一則留言在 GitHub 上都會變成「owner 寫的」，就無法分辨 `Human-Decision:` 是誰給的。
做法是建立 builder 帳號、邀請它成為 repo collaborator（Write），再把 claude.ai 的 GitHub 連結改成這個帳號。

身分分開後，建議在 `main` 的分支保護加上「合併前需要 1 個 approval」：builder 開的 PR 必須由 human 核准，核准本身也可驗證。

## 2. 建立 Reviewer GitHub App

GitHub → Settings → Developer settings → GitHub Apps → **New GitHub App**：

- **GitHub App name**：例如 `chonima666-ai-reviewer`，bot login 會是 `chonima666-ai-reviewer[bot]`
- **Homepage URL**：任意，例如 repo 網址
- **Webhook**：取消勾選 Active（不需要）
- **Repository permissions**（其餘全部維持 No access）：

  | 權限 | 設定 |
  | --- | --- |
  | Contents | Read-only |
  | Pull requests | Read and write |
  | Metadata | Read-only（自動） |

  不要給 Contents write、Administration、Secrets、Workflows 或任何 merge／bypass 相關權限。
  workflow 產生 token 時也只要求 `contents: read`、`pull-requests: write`。
- **Where can this GitHub App be installed**：Only on this account

建立後：
1. 記下頁面上的 **App ID**。
2. 在頁面底部按 **Generate a private key**，下載 `.pem` 檔。這個檔案不要放進任何 repo。
3. 左側 **Install App**，安裝到你的帳號，選 **Only select repositories** → `ai-collab-kit`。

## 3. 建立 `ai-review` environment 與 secrets

Repo → Settings → Environments → **New environment**，名稱 `ai-review`：

- **Deployment branches and tags**：選 **Selected branches and tags**，只加入 `main`。
  這樣只有在預設分支上執行的 job 拿得到下列 secret。
  這個限制和 workflow 的 trigger 相容：`issue_comment` 的 `GITHUB_REF` 永遠是預設分支；
  `workflow_dispatch` 則是「Use workflow from」選的分支，所以手動執行時要選 `main`，選其他分支會被 environment 擋下（fail closed）。
  workflow 不使用 `pull_request` 系列 trigger，不會遇到 PR merge ref 被擋的情況。
- **Environment secrets**：

  | 名稱 | 內容 |
  | --- | --- |
  | `OPENAI_API_KEY` | OpenAI API key |
  | `AICK_REVIEWER_PRIVATE_KEY` | 第 2 步 `.pem` 檔的完整內容 |
  | `AICK_DISCORD_WEBHOOK` | 第 4 步的 webhook URL（選配） |

- **Environment variables**：

  | 名稱 | 內容 |
  | --- | --- |
  | `AICK_REVIEWER_APP_ID` | 第 2 步的 App ID |
  | `AICK_REVIEWER_MODEL` | 要用的 OpenAI 模型名稱 |

這些 secret 不要設在 repo 層級，只放在 `ai-review` environment。原因：`ci.yml` 在 `pull_request` 事件上執行的是
PR 分支上的 workflow 檔，有 Write 權限的 builder 可以在 PR 裡修改它。repo 層級的 secret 會被這種未經審查的 workflow 讀到；
限定 `main` 的 environment 只給已合併進預設分支的程式碼。
兩個 environment variables 不是機密，技術上放 repo 層級也能讀到（environment 的值優先），放在這裡只是讓 Reviewer 的設定集中。

`AICK_REVIEWER_MODEL` 必須支援 Chat Completions（`ai-review.sh` 呼叫 `/v1/chat/completions`，帶 system 與 user 訊息）。
ChatGPT 訂閱、API 額度與 API 可用的模型是分開的；填入前先用同一把 key 確認：

```bash
curl -sS https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer $OPENAI_API_KEY" -H "Content-Type: application/json" \
  -d '{"model":"<模型 ID>","messages":[{"role":"system","content":"ping"},{"role":"user","content":"reply OK"}]}'
```

回覆有 `choices[0].message.content` 才代表可用；401、429 通常是 key 或額度問題。

## 4. Discord webhook（選配）

Discord 頻道 → 編輯頻道 → 整合 → Webhook → **新 Webhook** → 複製 Webhook 網址 → 存成第 3 步的 `AICK_DISCORD_WEBHOOK`。
Discord 只收通知，不接受任何決定。

## 5. 填寫 `identities`，經 PR 合併

`.ai-collab/project.yaml`（安裝了 kit 的專案；kit repo 自己的也在同一個位置）：

```yaml
identities:
  human: "chonima666"
  builder: "chonima666-builder"
  reviewer: "chonima666-ai-reviewer[bot]"
```

這個檔案決定誰說的話算數，所以必須經過 PR，由 human 合併。

## 6. 開啟

Repo → Settings → Secrets and variables → Actions → **Variables** → 新增 **repository variable**
`AICK_AUTO_REVIEW` = `true`。這個變數必須設在 repo 層級，因為判定狀態的 job 不使用 environment。

測試：Actions → ai-review → **Run workflow**，分支選 `main`，輸入一個已由 builder 貼過 `AI-Review: READY` 的 PR 編號。
手動執行也只認 `identities.builder` 寫的 `Ready-SHA:`，沒有就判定為 `NO_ACTION`。

## 安裝到其他專案

把 kit repo 的 `.github/workflows/ai-review.yml` 複製到專案的 `.github/workflows/`，再在該專案重做第 2～6 步。
workflow 會自動使用 `.ai-collab/kit/scripts/` 下的腳本。

## 什麼情況會拒絕執行

| 情況 | 結果 |
| --- | --- |
| `AICK_AUTO_REVIEW` 不是 `true` | workflow 不執行 |
| `identities` 有空白、格式不對或兩個相同 | 判定 job 失敗，不呼叫模型 |
| PR 來自 fork | 不進入需要 secret 的 job；腳本也再擋一次 |
| 缺少 `OPENAI_API_KEY`、`AICK_REVIEWER_MODEL` 或 Reviewer App 金鑰 | `REVIEW_FAILED`，不呼叫模型、不貼文 |
| 模型 API 錯誤或逾時（`AICK_MODEL_TIMEOUT`，預設 600 秒） | `REVIEW_FAILED`，不貼文 |
| 模型輸出不符合格式 | `REVIEW_FAILED`，不貼文 |
| Reviewer App 貼文失敗，或貼文者不是 `identities.reviewer` | `REVIEW_FAILED`，workflow 失敗 |

## 剩下的風險

- human 帳號是 repo admin，技術上可以刪除 Reviewer App 的 review 來改變輪數。LG-06a 禁止任何人以此重設計數；
  所以 builder 帳號不能有 admin 權限。
- 模型看得到 PR 的內容，PR 內容可能試圖影響模型的結論（prompt injection）。模型只能決定一則 review 的內容，
  改不了輪數、身分或狀態欄位；結論仍由人決定是否採納。
