#!/bin/bash
echo "=== Exporting configure_local_velocity_model results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
P_FILE="/home/ga/seiscomp/share/locsat/tables/GYM_LOCAL.P"
S_FILE="/home/ga/seiscomp/share/locsat/tables/GYM_LOCAL.S"

P_EXISTS="false"
S_EXISTS="false"
P_MTIME="0"
S_MTIME="0"

# Check P file
if [ -f "$P_FILE" ]; then
    P_EXISTS="true"
    P_MTIME=$(stat -c %Y "$P_FILE" 2>/dev/null || echo "0")
fi

# Check S file
if [ -f "$S_FILE" ]; then
    S_EXISTS="true"
    S_MTIME=$(stat -c %Y "$S_FILE" 2>/dev/null || echo "0")
fi

# Extract file contents safely
P_CONTENT=$(cat "$P_FILE" 2>/dev/null || echo "")
S_CONTENT=$(cat "$S_FILE" 2>/dev/null || echo "")

# Search SeisComP configurations for the expected modifications
CONFIG_DUMP=$(grep -riE "locator\.profiles|earthModelID|GYM_LOCAL" /home/ga/seiscomp/etc /home/ga/.seiscomp 2>/dev/null || echo "")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Construct JSON using jq for safety with newlines and quotes
jq -n \
  --arg ts "$TASK_START" \
  --arg p_ex "$P_EXISTS" \
  --arg s_ex "$S_EXISTS" \
  --arg p_mt "$P_MTIME" \
  --arg s_mt "$S_MTIME" \
  --arg p_con "$P_CONTENT" \
  --arg s_con "$S_CONTENT" \
  --arg conf "$CONFIG_DUMP" \
  '{
     task_start_time: $ts|tonumber,
     p_file_exists: ($p_ex == "true"),
     s_file_exists: ($s_ex == "true"),
     p_file_mtime: $p_mt|tonumber,
     s_file_mtime: $s_mt|tonumber,
     p_file_content: $p_con,
     s_file_content: $s_con,
     config_dump: $conf
   }' > /tmp/task_result.json

chmod 666 /tmp/task_result.json

echo "Result JSON written to /tmp/task_result.json:"
cat /tmp/task_result.json
echo "=== Export complete ==="