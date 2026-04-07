#!/bin/bash
set -euo pipefail

echo "=== Exporting customize_sidebar_layout result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png
echo "Final screenshot saved to /tmp/task_final.png"

# Fetch final API states
LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)

AUTH_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken // empty')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.data.userId // empty')

# Default empty JSON fallback
PREFS="{}"
REL_SUB="{}"
GEN_SUB="{}"

if [ -n "$AUTH_TOKEN" ] && [ -n "$USER_ID" ]; then
  # 1. Fetch user preferences
  ME_RESP=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" "${ROCKETCHAT_BASE_URL}/api/v1/me" 2>/dev/null || true)
  if [ -n "$ME_RESP" ]; then
    PREFS=$(echo "$ME_RESP" | jq -c '.settings.preferences // {}' 2>/dev/null || echo "{}")
  fi

  # 2. Fetch all subscriptions to check 'favorite' and 'open' statuses
  SUBS_RESP=$(curl -sS -H "X-Auth-Token: $AUTH_TOKEN" -H "X-User-Id: $USER_ID" "${ROCKETCHAT_BASE_URL}/api/v1/subscriptions.get" 2>/dev/null || true)
  if [ -n "$SUBS_RESP" ]; then
    REL_SUB=$(echo "$SUBS_RESP" | jq -c '.update[]? | select(.name == "release-updates") // {}' | head -1 2>/dev/null || echo "{}")
    GEN_SUB=$(echo "$SUBS_RESP" | jq -c '.update[]? | select(.name == "general") // {}' | head -1 2>/dev/null || echo "{}")
  fi
fi

# Make sure empty captures default to valid empty JSON
if [ -z "$REL_SUB" ]; then REL_SUB="{}"; fi
if [ -z "$GEN_SUB" ]; then GEN_SUB="{}"; fi
if [ -z "$PREFS" ]; then PREFS="{}"; fi

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "task_start_time": $TASK_START,
  "task_end_time": $TASK_END,
  "preferences": $PREFS,
  "release_updates_sub": $REL_SUB,
  "general_sub": $GEN_SUB
}
EOF

# Safely copy to standard output location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="