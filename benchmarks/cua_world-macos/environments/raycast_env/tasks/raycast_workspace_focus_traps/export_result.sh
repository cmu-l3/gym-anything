#!/bin/bash
# Export: raycast_workspace_focus_traps
# Records window state of every relevant app, plus the frontmost app.

set -euo pipefail
echo "=== Export: raycast_workspace_focus_traps ==="

RESULT_FILE="/tmp/raycast_workspace_focus_traps_result.json"
START_TS=$(cat /tmp/raycast_workspace_focus_traps_start_ts 2>/dev/null || echo "0")
LEASE_OLD_INITIAL=$(cat /tmp/raycast_workspace_focus_traps_lease_old_initial 2>/dev/null || echo "")
SCREEN_BOUNDS=$(cat /tmp/raycast_workspace_focus_traps_screen_bounds 2>/dev/null || echo "")

# Frontmost app
FRONT_APP=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null || echo "")

# Helper: get all window names + frames for a process
proc_windows() {
    local proc="$1"
    osascript << APPLEOF 2>/dev/null || echo ""
tell application "System Events"
    try
        if not (exists process "$proc") then
            return "PROCESS_MISSING"
        end if
        tell process "$proc"
            set out to ""
            set winList to every window
            repeat with w in winList
                set t to (name of w as text)
                set isMin to (value of attribute "AXMinimized" of w) as text
                try
                    set p to position of w
                    set s to size of w
                    set posX to (item 1 of p) as text
                    set posY to (item 2 of p) as text
                    set sizW to (item 1 of s) as text
                    set sizH to (item 2 of s) as text
                on error
                    set posX to "0"
                    set posY to "0"
                    set sizW to "0"
                    set sizH to "0"
                end try
                set out to out & t & "||" & posX & "||" & posY & "||" & sizW & "||" & sizH & "||" & isMin & linefeed
            end repeat
            return out
        end tell
    on error
        return ""
    end try
end tell
APPLEOF
}

SAFARI_WINS=$(proc_windows "Safari")
PREVIEW_WINS=$(proc_windows "Preview")
NOTES_WINS=$(proc_windows "Notes")
MAIL_WINS=$(proc_windows "Mail")
FINDER_WINS=$(proc_windows "Finder")
RAYCAST_WINS=$(proc_windows "Raycast")

# Best-effort: is Finder window visible on current Space?
FINDER_VISIBLE_CURRENT_SPACE=$(osascript << 'APPLEOF' 2>/dev/null || echo ""
tell application "System Events"
    try
        if exists process "Finder" then
            tell process "Finder"
                set vis to false
                repeat with w in every window
                    try
                        set posY to (item 2 of (position of w)) as integer
                        if posY > -10000 then set vis to true
                    end try
                end repeat
                return vis as text
            end tell
        end if
        return "false"
    on error
        return "unknown"
    end try
end tell
APPLEOF
)

# --- Assemble JSON ---
export SAFARI_WINS_ENV="$SAFARI_WINS"
export PREVIEW_WINS_ENV="$PREVIEW_WINS"
export NOTES_WINS_ENV="$NOTES_WINS"
export MAIL_WINS_ENV="$MAIL_WINS"
export FINDER_WINS_ENV="$FINDER_WINS"
export RAYCAST_WINS_ENV="$RAYCAST_WINS"

python3 - "$RESULT_FILE" "$START_TS" "$FRONT_APP" "$LEASE_OLD_INITIAL" "$SCREEN_BOUNDS" "$FINDER_VISIBLE_CURRENT_SPACE" << 'PYEOF'
import json, os, sys

result_file, start_ts, front_app, lease_old_initial, screen_bounds_raw, finder_vis = sys.argv[1:7]

def parse_windows(raw):
    wins = []
    for line in raw.splitlines():
        parts = line.split("||")
        if len(parts) >= 6:
            try:
                wins.append({
                    "title":     parts[0],
                    "x":         int(float(parts[1])),
                    "y":         int(float(parts[2])),
                    "w":         int(float(parts[3])),
                    "h":         int(float(parts[4])),
                    "minimized": parts[5].strip().lower() == "true",
                })
            except (ValueError, TypeError):
                pass
    return wins

def parse_bounds_str(s, n=4):
    if not s:
        return None
    parts = [p.strip() for p in s.replace(",", " ").split()]
    try:
        nums = [int(float(p)) for p in parts]
        if len(nums) == n:
            return nums
    except (ValueError, TypeError):
        pass
    return None

result = {
    "task_start":             int(start_ts),
    "frontmost_app":          front_app.strip(),
    "screen_bounds":          parse_bounds_str(screen_bounds_raw, 4),
    "lease_old_initial_frame": parse_bounds_str(lease_old_initial, 4),
    "safari_windows":         parse_windows(os.environ.get("SAFARI_WINS_ENV", "")),
    "preview_windows":        parse_windows(os.environ.get("PREVIEW_WINS_ENV", "")),
    "notes_windows":          parse_windows(os.environ.get("NOTES_WINS_ENV", "")),
    "mail_windows":           parse_windows(os.environ.get("MAIL_WINS_ENV", "")),
    "finder_windows":         parse_windows(os.environ.get("FINDER_WINS_ENV", "")),
    "raycast_windows":        parse_windows(os.environ.get("RAYCAST_WINS_ENV", "")),
    "finder_visible_current_space": finder_vis.strip().lower() in ("true", "yes"),
}

with open(result_file, "w") as f:
    json.dump(result, f, indent=2)

print(f"WROTE {result_file}: front={front_app} preview_wins={len(result['preview_windows'])}")
PYEOF

echo "=== Export complete ==="
