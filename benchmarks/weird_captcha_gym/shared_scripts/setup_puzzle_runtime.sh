#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${WEIRD_CAPTCHA_STATE_DIR:-/tmp/weird_captcha_gym}"
APP_DIR="${WEIRD_CAPTCHA_APP_DIR:-/workspace/shared_runtime/app}"
SERVER="${WEIRD_CAPTCHA_SERVER:-/workspace/shared_runtime/server/weird_captcha_server.py}"
PORT="${WEIRD_CAPTCHA_PORT:-8787}"
URL="http://127.0.0.1:${PORT}/"

echo "=== Weird CAPTCHA Gym: setup shared runtime ==="
mkdir -p "$STATE_DIR"
rm -f "$STATE_DIR/result.json" /tmp/task_result.json

if [ -f "$STATE_DIR/server.pid" ]; then
  old_pid="$(cat "$STATE_DIR/server.pid" 2>/dev/null || true)"
  if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
    kill "$old_pid" 2>/dev/null || true
  fi
fi
pkill -f "weird_captcha_server.py.*--port ${PORT}" 2>/dev/null || true

nohup python3 "$SERVER" --host 127.0.0.1 --port "$PORT" --app-dir "$APP_DIR" --state-dir "$STATE_DIR" \
  > /tmp/weird_captcha_server.log 2>&1 &
echo "$!" > "$STATE_DIR/server.pid"

python3 - <<PY
import sys, time, urllib.request
url = "http://127.0.0.1:${PORT}/health"
for _ in range(50):
    try:
        with urllib.request.urlopen(url, timeout=1) as resp:
            if resp.status == 200:
                sys.exit(0)
    except Exception:
        time.sleep(0.2)
raise SystemExit("server did not become healthy")
PY

browser_cmd=""
for candidate in google-chrome-stable google-chrome chromium chromium-browser firefox; do
  if command -v "$candidate" >/dev/null 2>&1; then
    browser_cmd="$candidate"
    break
  fi
done

echo "Puzzle server ready at $URL"
