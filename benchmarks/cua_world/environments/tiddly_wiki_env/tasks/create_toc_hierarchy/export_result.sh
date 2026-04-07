#!/bin/bash
set -e
echo "=== Exporting create_toc_hierarchy result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Helper function to grab existence and tags safely into JSON format
get_tiddler_state_json() {
    local title="$1"
    local exists=$(tiddler_exists "$title")
    local tags=""
    local text=""
    
    if [ "$exists" = "true" ]; then
        tags=$(get_tiddler_field "$title" "tags")
        text=$(get_tiddler_text "$title")
    fi
    
    local esc_tags=$(json_escape "$tags")
    local esc_text=$(json_escape "$text")
    
    echo "{\"exists\": $exists, \"tags\": \"$esc_tags\", \"content_length\": ${#text}, \"text\": \"$esc_text\"}"
}

# 1. Root and Sections
ROOT_STATE=$(get_tiddler_state_json "ProjectAlpha Documentation")
ARCH_SEC_STATE=$(get_tiddler_state_json "Architecture")
API_SEC_STATE=$(get_tiddler_state_json "API Reference")
GS_SEC_STATE=$(get_tiddler_state_json "Getting Started")

# 2. ToC Index
INDEX_STATE=$(get_tiddler_state_json "Documentation Index")

# 3. Children (Architecture)
DB_STATE=$(get_tiddler_state_json "Database Schema Design")
MICRO_STATE=$(get_tiddler_state_json "Microservices Overview")
AUTH_STATE=$(get_tiddler_state_json "Authentication Flow")

# 4. Children (API)
REST_STATE=$(get_tiddler_state_json "REST API Endpoints")
GRAPH_STATE=$(get_tiddler_state_json "GraphQL Queries")
ERR_STATE=$(get_tiddler_state_json "Error Codes Reference")
WS_STATE=$(get_tiddler_state_json "WebSocket Events")

# 5. Children (Getting Started)
INST_STATE=$(get_tiddler_state_json "Installation Guide")
CONF_STATE=$(get_tiddler_state_json "Configuration Options")
DEV_STATE=$(get_tiddler_state_json "Development Environment Setup")
DEP_STATE=$(get_tiddler_state_json "Deployment Checklist")
TRB_STATE=$(get_tiddler_state_json "Troubleshooting Common Issues")

# Check TiddlyWiki server log for GUI save events (anti-gaming)
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -q "Dispatching 'save' task:" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
fi

# Construct full JSON object
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "root": $ROOT_STATE,
    "index": $INDEX_STATE,
    "sections": {
        "Architecture": $ARCH_SEC_STATE,
        "API Reference": $API_SEC_STATE,
        "Getting Started": $GS_SEC_STATE
    },
    "children": {
        "Database Schema Design": $DB_STATE,
        "Microservices Overview": $MICRO_STATE,
        "Authentication Flow": $AUTH_STATE,
        "REST API Endpoints": $REST_STATE,
        "GraphQL Queries": $GRAPH_STATE,
        "Error Codes Reference": $ERR_STATE,
        "WebSocket Events": $WS_STATE,
        "Installation Guide": $INST_STATE,
        "Configuration Options": $CONF_STATE,
        "Development Environment Setup": $DEV_STATE,
        "Deployment Checklist": $DEP_STATE,
        "Troubleshooting Common Issues": $TRB_STATE
    }
}
EOF

# Save the final result
rm -f /tmp/toc_hierarchy_result.json 2>/dev/null || sudo rm -f /tmp/toc_hierarchy_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/toc_hierarchy_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/toc_hierarchy_result.json
chmod 666 /tmp/toc_hierarchy_result.json 2>/dev/null || sudo chmod 666 /tmp/toc_hierarchy_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/toc_hierarchy_result.json"
echo "=== Export complete ==="