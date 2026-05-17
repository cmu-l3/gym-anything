#!/bin/bash
# pre_task hook for save_notion_window_screenshot on notion_env/macOS.
#
# Responsibilities:
#   1. Launch Notion (idempotent) and wait for its window to register.
#   2. Sweep any pre-existing screenshot files from ~/Desktop and ~/Documents
#      so the agent can't take credit for a leftover capture (anti-gaming).
#   3. Record an authoritative task-start Unix timestamp the export script
#      uses for the freshness check.
set -eu

echo "=== Setting up save_notion_window_screenshot ==="

# 1) Launch Notion (idempotent) and wait for window registration
if ! pgrep -x "Notion" >/dev/null; then
  echo "[pre_task] launching Notion"
  if ! open -a "Notion" 2>/dev/null; then
    echo "[pre_task] 'open -a Notion' failed — falling back to bundle path"
    open /Applications/Notion.app
  fi
fi
for i in $(seq 1 45); do
  if /usr/bin/lsappinfo list 2>/dev/null | grep -qE '"Notion"'; then
    echo "[pre_task] Notion window registered after ${i}s"
    break
  fi
  sleep 1
done

# 2) Anti-gaming sweep — remove any pre-existing .png files anywhere the
#    export script will search. Without this, the agent could "succeed"
#    by referencing a leftover screenshot from an unrelated workflow.
#    Only delete files that look like screen captures (have the screencap
#    xattr) so user content (if any) isn't lost. Be tolerant of missing
#    xattr tool / missing files.
echo "[pre_task] sweeping pre-existing screenshots from ~/Desktop and ~/Documents"
for dir in "$HOME/Desktop" "$HOME/Documents"; do
  mkdir -p "$dir"
  # The find expression deliberately doesn't follow symlinks and only looks
  # for *.png at the top level — the search domain the verifier uses.
  find "$dir" -maxdepth 1 -name "*.png" -type f 2>/dev/null | while read -r f; do
    if xattr -p com.apple.metadata:kMDItemIsScreenCapture "$f" >/dev/null 2>&1; then
      echo "  removing leftover screenshot: $f"
      rm -f "$f"
    fi
  done
done

# 3) Authoritative task start time. The export script writes this back into
#    the result JSON so the verifier's freshness check has a single source.
date +%s > /tmp/save_notion_window_screenshot_task_start
echo "task_start_unix=$(cat /tmp/save_notion_window_screenshot_task_start)"

# Brief settle so any startup animation reaches its stable layout before
# screenshots / VNC viewer / agent step.
sleep 4

# Optional: take a baseline screenshot of the trajectory start state to
# /tmp/. Not used by the verifier — only the evidence collector / interactive
# pilot looks at this. Use `screencapture -x` (silent, no UI sound).
/usr/sbin/screencapture -x /tmp/save_notion_window_screenshot_start.png 2>/dev/null || true

echo "=== save_notion_window_screenshot setup complete ==="
echo "Notion is running. Agent should take a window-mode screenshot of it."
