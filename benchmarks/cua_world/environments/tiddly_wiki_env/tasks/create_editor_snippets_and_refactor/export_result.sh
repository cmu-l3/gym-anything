#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

TIDDLER_DIR="/home/ga/mywiki/tiddlers"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Function to get latest file matching an exact title
get_latest_file() {
    local title="$1"
    local files=$(grep -l "^title: $title" "$TIDDLER_DIR"/*.tid 2>/dev/null)
    if [ -n "$files" ]; then
        ls -t $files | head -1
    fi
}

check_snippet() {
    local title="$1"
    local file=$(get_latest_file "$title")
    
    if [ -n "$file" ]; then
        local tags=$(grep "^tags:" "$file")
        local text=$(awk '/^$/{found=1; next} found{print}' "$file")
        
        local has_sys_tag="false"
        echo "$tags" | grep -q "\$:/tags/TextEditor/Snippet" && has_sys_tag="true"
        
        local has_tc_error="false"
        echo "$text" | grep -Fq "@@.tc-error" && has_tc_error="true"
        
        local has_tc_message="false"
        echo "$text" | grep -Fq "@@.tc-message-box" && has_tc_message="true"
        
        echo "{\"exists\": true, \"has_sys_tag\": $has_sys_tag, \"has_tc_error\": $has_tc_error, \"has_tc_message\": $has_tc_message}"
    else
        echo "{\"exists\": false, \"has_sys_tag\": false, \"has_tc_error\": false, \"has_tc_message\": false}"
    fi
}

check_runbook() {
    local title="$1"
    local file=$(get_latest_file "$title")
    
    if [ -n "$file" ]; then
        local tags=$(grep "^tags:" "$file")
        local text=$(awk '/^$/{found=1; next} found{print}' "$file")
        
        local has_draft="false"
        echo "$tags" | grep -qi "Draft Runbook" && has_draft="true"
        
        local has_pub="false"
        echo "$tags" | grep -qi "Published Runbook" && has_pub="true"
        
        local has_crit_placeholder="false"
        echo "$text" | grep -Fq "[INSERT CRITICAL WARNING]" && has_crit_placeholder="true"
        
        local has_info_placeholder="false"
        echo "$text" | grep -Fq "[INSERT INFO BOX]" && has_info_placeholder="true"
        
        local has_tc_error="false"
        echo "$text" | grep -Fq "@@.tc-error" && has_tc_error="true"
        
        local has_tc_message="false"
        echo "$text" | grep -Fq "@@.tc-message-box" && has_tc_message="true"
        
        echo "{\"exists\": true, \"has_draft\": $has_draft, \"has_pub\": $has_pub, \"has_crit_placeholder\": $has_crit_placeholder, \"has_info_placeholder\": $has_info_placeholder, \"has_tc_error\": $has_tc_error, \"has_tc_message\": $has_tc_message}"
    else
        echo "{\"exists\": false, \"has_draft\": false, \"has_pub\": false, \"has_crit_placeholder\": false, \"has_info_placeholder\": false, \"has_tc_error\": false, \"has_tc_message\": false}"
    fi
}

# Run checks
SNIPPET_CRIT=$(check_snippet "Snippet: Critical Warning")
SNIPPET_INFO=$(check_snippet "Snippet: Info Box")

RB_PG=$(check_runbook "PostgreSQL 16 Minor Upgrade")
RB_NGINX=$(check_runbook "Nginx SSL Certificate Rotation")
RB_K8S=$(check_runbook "Kubernetes Node Draining")

# Check GUI saves via server log
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -qi "Dispatching 'save' task:" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
fi

# Assemble JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "snippets": {
        "critical_warning": $SNIPPET_CRIT,
        "info_box": $SNIPPET_INFO
    },
    "runbooks": {
        "postgresql": $RB_PG,
        "nginx": $RB_NGINX,
        "kubernetes": $RB_K8S
    },
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely (handle permissions)
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="