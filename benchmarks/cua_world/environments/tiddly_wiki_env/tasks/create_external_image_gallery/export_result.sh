#!/bin/bash
echo "=== Exporting create_external_image_gallery result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Function to safely extract tiddler details into JSON fragment
function export_landmark() {
    local TITLE="$1"
    local EXISTS=$(tiddler_exists "$TITLE")
    
    if [ "$EXISTS" = "true" ]; then
        local TYPE=$(get_tiddler_field "$TITLE" "type" | tr -d '\r\n')
        local URI=$(get_tiddler_field "$TITLE" "_canonical_uri" | tr -d '\r\n')
        local LOC=$(get_tiddler_field "$TITLE" "location" | tr -d '\r\n')
        local YEAR=$(get_tiddler_field "$TITLE" "year" | tr -d '\r\n')
        local TAGS=$(get_tiddler_field "$TITLE" "tags" | tr -d '\r\n')
        local TEXT_LEN=$(get_tiddler_text "$TITLE" | wc -c)
        
        echo "{\"exists\": true, \"type\": \"$(json_escape "$TYPE")\", \"uri\": \"$(json_escape "$URI")\", \"location\": \"$(json_escape "$LOC")\", \"year\": \"$(json_escape "$YEAR")\", \"tags\": \"$(json_escape "$TAGS")\", \"text_length\": $TEXT_LEN}"
    else
        echo "{\"exists\": false, \"type\": \"\", \"uri\": \"\", \"location\": \"\", \"year\": \"\", \"tags\": \"\", \"text_length\": 0}"
    fi
}

# Export individual image tiddlers
COLOSSEUM_DATA=$(export_landmark "Colosseum")
TAJ_MAHAL_DATA=$(export_landmark "Taj Mahal")
MACHU_PICCHU_DATA=$(export_landmark "Machu Picchu")

# Export gallery tiddler
GALLERY_TITLE="World Heritage Gallery"
GALLERY_EXISTS=$(tiddler_exists "$GALLERY_TITLE")
if [ "$GALLERY_EXISTS" = "true" ]; then
    GALLERY_TEXT=$(json_escape "$(get_tiddler_text "$GALLERY_TITLE")")
else
    GALLERY_TEXT=""
fi

# Check TiddlyWiki server log for GUI save events (anti-gaming)
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -qi "Dispatching 'save' task:.*Colosseum\|Dispatching 'save' task:.*Taj.*Mahal\|Dispatching 'save' task:.*Machu.*Picchu\|Dispatching 'save' task:.*World.*Heritage" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
fi

# Build complete JSON
JSON_RESULT=$(cat << EOF
{
    "landmarks": {
        "Colosseum": $COLOSSEUM_DATA,
        "Taj_Mahal": $TAJ_MAHAL_DATA,
        "Machu_Picchu": $MACHU_PICCHU_DATA
    },
    "gallery": {
        "exists": $GALLERY_EXISTS,
        "text": "$GALLERY_TEXT"
    },
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/image_gallery_result.json"

echo "Result saved to /tmp/image_gallery_result.json"
cat /tmp/image_gallery_result.json
echo "=== Export complete ==="