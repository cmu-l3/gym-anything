#!/bin/bash
echo "=== Exporting fragile_payload_kinematic_optimization result ==="
source /workspace/scripts/task_utils.sh || exit 1

# Take final screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || true

ORK_FILE="/home/ga/Documents/rockets/payload_ready.ork"
PLOT_FILE="/home/ga/Documents/exports/acceleration_plot.png"
MEMO_FILE="/home/ga/Documents/exports/payload_memo.txt"
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null | cut -d'=' -f2 || echo "0")

ork_exists="false"
plot_exists="false"
memo_exists="false"

[ -f "$ORK_FILE" ] && ork_exists="true"
[ -f "$PLOT_FILE" ] && plot_exists="true"
[ -f "$MEMO_FILE" ] && memo_exists="true"

ork_size=0
plot_size=0
memo_size=0

[ "$ork_exists" = "true" ] && ork_size=$(stat -c %s "$ORK_FILE" 2>/dev/null)
[ "$plot_exists" = "true" ] && plot_size=$(stat -c %s "$PLOT_FILE" 2>/dev/null)
[ "$memo_exists" = "true" ] && memo_size=$(stat -c %s "$MEMO_FILE" 2>/dev/null)

# Check creation time to ensure files were created during task (anti-gaming)
plot_created_during_task="false"
memo_created_during_task="false"

if [ "$plot_exists" = "true" ]; then
    plot_mtime=$(stat -c %Y "$PLOT_FILE" 2>/dev/null || echo "0")
    if [ "$plot_mtime" -ge "$START_TIME" ]; then
        plot_created_during_task="true"
    fi
fi

if [ "$memo_exists" = "true" ]; then
    memo_mtime=$(stat -c %Y "$MEMO_FILE" 2>/dev/null || echo "0")
    if [ "$memo_mtime" -ge "$START_TIME" ]; then
        memo_created_during_task="true"
    fi
fi

write_result_json "{
  \"ork_exists\": $ork_exists,
  \"ork_size\": $ork_size,
  \"plot_exists\": $plot_exists,
  \"plot_size\": $plot_size,
  \"plot_created_during_task\": $plot_created_during_task,
  \"memo_exists\": $memo_exists,
  \"memo_size\": $memo_size,
  \"memo_created_during_task\": $memo_created_during_task
}" /tmp/payload_kinematic_result.json

echo "=== Export complete ==="