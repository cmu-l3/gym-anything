#!/bin/bash
echo "=== Exporting Compass Swing Task Results ==="

# Define paths
SCENARIO_DIR="/opt/bridgecommand/Scenarios/n) Solent Compass Swing"
DEVIATION_FILE="/home/ga/Documents/compass_deviation_card.txt"
GUIDE_FILE="/home/ga/Documents/compass_swing_instructor_guide.txt"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check existence and timestamps of files
check_file() {
    local f="$1"
    if [ -f "$f" ]; then
        local mtime=$(stat -c %Y "$f")
        if [ "$mtime" -ge "$TASK_START_TIME" ]; then
            echo "true"
        else
            echo "pre_existing"
        fi
    else
        echo "false"
    fi
}

SCENARIO_CREATED=$( [ -d "$SCENARIO_DIR" ] && echo "true" || echo "false" )
ENV_EXISTS=$(check_file "$SCENARIO_DIR/environment.ini")
OWN_EXISTS=$(check_file "$SCENARIO_DIR/ownship.ini")
OTHER_EXISTS=$(check_file "$SCENARIO_DIR/othership.ini")
CARD_EXISTS=$(check_file "$DEVIATION_FILE")
GUIDE_EXISTS=$(check_file "$GUIDE_FILE")

# 3. Read content safely (max 10KB to prevent bloating)
read_content() {
    local f="$1"
    if [ -f "$f" ]; then
        cat "$f" | head -c 10000 | python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))'
    else
        echo '""'
    fi
}

ENV_CONTENT=$(read_content "$SCENARIO_DIR/environment.ini")
OWN_CONTENT=$(read_content "$SCENARIO_DIR/ownship.ini")
OTHER_CONTENT=$(read_content "$SCENARIO_DIR/othership.ini")
CARD_CONTENT=$(read_content "$DEVIATION_FILE")
GUIDE_CONTENT=$(read_content "$GUIDE_FILE")
GUIDE_LENGTH=$( [ -f "$GUIDE_FILE" ] && wc -c < "$GUIDE_FILE" || echo "0" )

# 4. Create JSON result
# We construct JSON manually to avoid dependencies, ensuring safe escaping via python one-liner above
cat > /tmp/task_result.json <<EOF
{
  "scenario_dir_exists": $SCENARIO_CREATED,
  "files": {
    "environment_ini": {
      "status": "$ENV_EXISTS",
      "content": $ENV_CONTENT
    },
    "ownship_ini": {
      "status": "$OWN_EXISTS",
      "content": $OWN_CONTENT
    },
    "othership_ini": {
      "status": "$OTHER_EXISTS",
      "content": $OTHER_CONTENT
    },
    "deviation_card": {
      "status": "$CARD_EXISTS",
      "content": $CARD_CONTENT
    },
    "instructor_guide": {
      "status": "$GUIDE_EXISTS",
      "length": $GUIDE_LENGTH,
      "content": $GUIDE_CONTENT
    }
  },
  "timestamp": "$(date +%s)"
}
EOF

# Set permissions so verifier can read it
chmod 644 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"