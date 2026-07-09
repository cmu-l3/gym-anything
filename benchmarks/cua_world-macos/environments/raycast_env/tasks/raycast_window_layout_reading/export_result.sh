#!/bin/bash
# Export: raycast_window_layout_reading
# Records the running state of Safari (URL + window frame) and Notes (window frame)
# plus screen dimensions for relative-position checks.

set -euo pipefail
echo "=== Export: raycast_window_layout_reading ==="

RESULT_FILE="/tmp/raycast_window_layout_reading_result.json"
START_TS=$(cat /tmp/raycast_window_layout_reading_start_ts 2>/dev/null || echo "0")

# Get screen bounds: returns "0, 0, width, height"
SCREEN_BOUNDS=$(osascript -e 'tell application "Finder" to get bounds of window of desktop' 2>/dev/null || echo "")

# Get Safari front tab URL
SAFARI_URL=$(osascript -e '
try
    tell application "Safari"
        if (count of windows) > 0 then
            return URL of current tab of front window
        else
            return ""
        end if
    end tell
on error
    return ""
end try
' 2>/dev/null || echo "")

# Helper AppleScript to get window frame for a process
get_frame() {
    local proc="$1"
    osascript -e "
try
    tell application \"System Events\"
        if exists process \"$proc\" then
            tell process \"$proc\"
                if (count of windows) > 0 then
                    set p to position of front window
                    set s to size of front window
                    return ((item 1 of p) as string) & \",\" & ((item 2 of p) as string) & \",\" & ((item 1 of s) as string) & \",\" & ((item 2 of s) as string)
                else
                    return \"\"
                end if
            end tell
        else
            return \"\"
        end if
    end tell
on error
    return \"\"
end try
" 2>/dev/null || echo ""
}

SAFARI_FRAME=$(get_frame "Safari")
NOTES_FRAME=$(get_frame "Notes")

# Is each app running?
SAFARI_RUNNING=$(pgrep -x "Safari" > /dev/null 2>&1 && echo "true" || echo "false")
NOTES_RUNNING=$(pgrep -x "Notes" > /dev/null 2>&1 && echo "true" || echo "false")

python3 - "$RESULT_FILE" "$START_TS" "$SCREEN_BOUNDS" "$SAFARI_URL" "$SAFARI_FRAME" "$NOTES_FRAME" "$SAFARI_RUNNING" "$NOTES_RUNNING" << 'PYEOF'
import json, sys

result_file, start_ts, screen_bounds, safari_url, safari_frame, notes_frame, safari_running, notes_running = sys.argv[1:9]

def parse_bounds(s, expected_len):
    """Parse a comma-separated string into a list of ints; return None on failure."""
    if not s:
        return None
    parts = [p.strip() for p in s.replace(",", " ").split()]
    try:
        nums = [int(float(p)) for p in parts]
        if len(nums) == expected_len:
            return nums
    except (ValueError, TypeError):
        pass
    return None

screen = parse_bounds(screen_bounds, 4)   # [x, y, width, height]
safari = parse_bounds(safari_frame, 4)    # [x, y, w, h]
notes  = parse_bounds(notes_frame, 4)

result = {
    "task_start": int(start_ts),
    "screen_bounds": screen,
    "safari_running": safari_running == "true",
    "notes_running": notes_running == "true",
    "safari_url": safari_url,
    "safari_frame": safari,
    "notes_frame": notes,
}

with open(result_file, "w") as f:
    json.dump(result, f, indent=2)

print(f"screen={screen} safari_url={safari_url[:60]} safari_frame={safari} notes_frame={notes}")
PYEOF

echo "Result written to: $RESULT_FILE"
echo "=== Export complete ==="
