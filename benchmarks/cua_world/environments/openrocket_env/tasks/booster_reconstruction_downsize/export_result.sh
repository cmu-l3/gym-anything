#!/bin/bash
# Export script for booster_reconstruction_downsize task
echo "=== Exporting booster_reconstruction_downsize result ==="

source /workspace/scripts/task_utils.sh || exit 1

# Take final screenshot
take_screenshot /tmp/reconstruction_final.png 2>/dev/null || true

# Find the modified ORK file (handling minor typos by checking timestamp if exact name is missing)
ORK_FILE="/home/ga/Documents/rockets/reconstructed_rocket.ork"
if [ ! -f "$ORK_FILE" ]; then
    # Fallback to the newest .ork file modified after setup
    NEWEST_ORK=$(find /home/ga/Documents/rockets -maxdepth 1 -type f -name "*.ork" -newer /tmp/reconstruction_gt.txt 2>/dev/null | head -1)
    if [ -n "$NEWEST_ORK" ]; then
        ORK_FILE="$NEWEST_ORK"
        echo "Using fallback .ork file: $ORK_FILE"
    fi
fi

# Find the memo file (handling minor typos)
MEMO_FILE="/home/ga/Documents/exports/reconstruction_memo.txt"
if [ ! -f "$MEMO_FILE" ]; then
    NEWEST_MEMO=$(find /home/ga/Documents/exports -maxdepth 1 -type f -name "*.txt" -newer /tmp/reconstruction_gt.txt 2>/dev/null | head -1)
    if [ -n "$NEWEST_MEMO" ]; then
        MEMO_FILE="$NEWEST_MEMO"
        echo "Using fallback memo file: $MEMO_FILE"
    fi
fi

# Gather metadata
ork_exists="false"
memo_exists="false"
[ -f "$ORK_FILE" ] && ork_exists="true"
[ -f "$MEMO_FILE" ] && memo_exists="true"

ork_mtime="0"
memo_size=0
[ -f "$ORK_FILE" ] && ork_mtime=$(stat -c %Y "$ORK_FILE" 2>/dev/null)
[ -f "$MEMO_FILE" ] && memo_size=$(stat -c %s "$MEMO_FILE" 2>/dev/null)

# Write result to JSON
write_result_json "{
  \"ork_exists\": $ork_exists,
  \"ork_path\": \"$ORK_FILE\",
  \"ork_mtime\": \"$ork_mtime\",
  \"memo_exists\": $memo_exists,
  \"memo_path\": \"$MEMO_FILE\",
  \"memo_size\": $memo_size
}" /tmp/reconstruction_result.json

echo "=== Export complete ==="