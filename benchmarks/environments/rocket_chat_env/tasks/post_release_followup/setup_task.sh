#!/bin/bash
set -euo pipefail

echo "=== Setting up post_release_followup task ==="

source /workspace/scripts/task_utils.sh

rm -f /tmp/task_start.png 2>/dev/null || true
date +%s > /tmp/task_start_timestamp

if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 600; then
  echo "ERROR: Rocket.Chat API is not reachable at ${ROCKETCHAT_BASE_URL}"
  exit 1
fi

for _ in $(seq 1 60); do
  if api_login "$ROCKETCHAT_TASK_USERNAME" "$ROCKETCHAT_TASK_PASSWORD"; then
    break
  fi
  sleep 2
done

if ! api_login "$ROCKETCHAT_TASK_USERNAME" "$ROCKETCHAT_TASK_PASSWORD"; then
  echo "ERROR: Task login credentials are not valid yet"
  exit 1
fi

if [ ! -f "$SEED_MANIFEST_FILE" ] && [ -f "/home/ga/rocket_chat_seed_manifest.json" ]; then
  cp "/home/ga/rocket_chat_seed_manifest.json" "$SEED_MANIFEST_FILE"
fi

if [ -f "$SEED_MANIFEST_FILE" ]; then
  target_tag=$(jq -r '.target_release.tag_name // empty' "$SEED_MANIFEST_FILE" 2>/dev/null || true)
  if [ -n "$target_tag" ]; then
    echo "Target release for task: $target_tag"
  fi
fi

if ! restart_firefox "$ROCKETCHAT_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start cleanly"
  DISPLAY=:1 wmctrl -l 2>/dev/null || true
  exit 1
fi

# Deterministic start state: keep Rocket.Chat at login page.
focus_firefox || true
navigate_to_url "$ROCKETCHAT_LOGIN_URL"
sleep 2
focus_firefox || true

take_screenshot /tmp/task_start.png

echo "Task start screenshot: /tmp/task_start.png"
echo "=== Task setup complete ==="
