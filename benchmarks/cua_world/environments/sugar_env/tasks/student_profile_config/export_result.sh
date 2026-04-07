#!/bin/bash
# Do NOT use set -e
echo "=== Exporting student_profile_config task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

su - ga -c "$SUGAR_ENV scrot /tmp/profile_task_end.png" 2>/dev/null || true

TASK_START=$(cat /tmp/student_profile_config_start_ts 2>/dev/null || echo "0")

# Read current gsettings values (nick and color are valid org.sugarlabs.user keys)
NICK=$(su - ga -c "$SUGAR_ENV gsettings get org.sugarlabs.user nick" 2>/dev/null || echo "''")
COLOR=$(su - ga -c "$SUGAR_ENV gsettings get org.sugarlabs.user color" 2>/dev/null || echo "''")

echo "Current nick: $NICK"
echo "Current color: $COLOR"

# Strip surrounding quotes from gsettings output
NICK_CLEAN=$(echo "$NICK" | tr -d "'" | tr -d '"' | xargs)
COLOR_CLEAN=$(echo "$COLOR" | tr -d "'" | tr -d '"' | xargs)

NICK_CORRECT="false"
COLOR_CHANGED="false"
DEFAULT_COLOR="#FF2B34,#005FE4"

if [ "$NICK_CLEAN" = "AlexC" ]; then
    NICK_CORRECT="true"
fi
# Color is changed if it differs from the default set by setup_task.sh
if [ "$COLOR_CLEAN" != "$DEFAULT_COLOR" ] && [ -n "$COLOR_CLEAN" ]; then
    COLOR_CHANGED="true"
fi

# Check Sugar Journal for "Student Setup Log"
JOURNAL_FOUND="false"
JOURNAL_DIR="/home/ga/.sugar/default/datastore"
if [ -d "$JOURNAL_DIR" ]; then
    MATCH=$(find "$JOURNAL_DIR" -name "title" -newer /tmp/student_profile_config_start_ts \
        -exec grep -l "Student Setup Log" {} \; 2>/dev/null | head -1)
    if [ -n "$MATCH" ]; then
        JOURNAL_FOUND="true"
        echo "Found Journal entry (new): Student Setup Log"
    else
        MATCH=$(find "$JOURNAL_DIR" -name "title" \
            -exec grep -l "Student Setup Log" {} \; 2>/dev/null | head -1)
        if [ -n "$MATCH" ]; then
            JOURNAL_FOUND="true"
            echo "Found Journal entry (any): Student Setup Log"
        fi
    fi
fi

cat > /tmp/student_profile_config_result.json << EOF
{
    "nick_value": "$NICK_CLEAN",
    "color_value": "$COLOR_CLEAN",
    "nick_correct": $NICK_CORRECT,
    "color_changed": $COLOR_CHANGED,
    "journal_found": $JOURNAL_FOUND
}
EOF

chmod 666 /tmp/student_profile_config_result.json
echo "Result saved to /tmp/student_profile_config_result.json"
cat /tmp/student_profile_config_result.json
echo "=== Export complete ==="
