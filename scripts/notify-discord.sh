#!/usr/bin/env bash
# Send one review or delivery event to Discord. Notification only: nothing sent back is read.
#   notify-discord.sh <event> <repo> <pr> <sha> [detail]
# event: REVIEW_STARTED, REVIEW_VERIFIED, CHANGES_REQUESTED, HUMAN_GATE_REQUIRED, REVIEW_FAILED,
# AUTO_MERGED, AUTO_MERGE_FAILED.
# The webhook URL comes only from $AICK_DISCORD_WEBHOOK and is never printed. Without it the
# script says so and exits 0; exit 1 means Discord rejected or could not be reached.
set -uo pipefail

[ $# -ge 4 ] || { echo "usage: $0 <event> <repo> <pr> <sha> [detail]" >&2; exit 2; }
event="$1" repo="$2" pr="$3" sha="$4" detail="${5:-}"
case "$event" in
  REVIEW_STARTED|REVIEW_VERIFIED|CHANGES_REQUESTED|HUMAN_GATE_REQUIRED|REVIEW_FAILED|AUTO_MERGED|AUTO_MERGE_FAILED) ;;
  *) echo "unknown event: $event" >&2; exit 2 ;;
esac
if [ -z "${AICK_DISCORD_WEBHOOK:-}" ]; then
  echo "discord: AICK_DISCORD_WEBHOOK not set; $event not sent"
  exit 0
fi

short="${sha:0:7}"
url="${GITHUB_SERVER_URL:-https://github.com}/$repo/pull/$pr"
text="**$event** · $repo#$pr · SHA \`${short:-none}\`
${detail:+$(printf '%s' "$detail" | head -c 1500)
}$url"
[ "$event" = HUMAN_GATE_REQUIRED ] && text="$text
Automation stopped for this pull request. The owner decides: fix it, merge it by hand, or close it."

# allowed_mentions stops PR text from pinging anyone.
payload="$(jq -n --arg content "$text" '{content: $content, allowed_mentions: {parse: []}}')"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
(umask 077; printf 'url = "%s"\n' "$AICK_DISCORD_WEBHOOK" > "$work/curlrc")
code="$(printf '%s' "$payload" | curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 30 \
  -K "$work/curlrc" -H "Content-Type: application/json" --data-binary @- 2>/dev/null)" || code=000
case "$code" in
  2??) echo "discord: $event sent" ;;
  *) echo "discord: $event failed (HTTP $code)" >&2; exit 1 ;;
esac
