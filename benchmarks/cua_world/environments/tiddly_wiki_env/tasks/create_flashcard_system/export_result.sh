#!/bin/bash
set -e

echo "=== Exporting flashcard system result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Gather metric data
INITIAL_COUNT=$(cat /tmp/initial_tiddler_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(count_user_tiddlers)

# Check TiddlyWiki server log for GUI save events
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -qi "Dispatching 'save' task:" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
fi

# Helper function to extract individual tiddler data safely as JSON
get_tiddler_json() {
    local TITLE="$1"
    local EXISTS=$(tiddler_exists "$TITLE")
    local TAGS=""
    local Q=""
    local A=""
    local D=""
    local BODY=""
    
    if [ "$EXISTS" = "true" ]; then
        TAGS=$(get_tiddler_field "$TITLE" "tags")
        Q=$(get_tiddler_field "$TITLE" "question")
        A=$(get_tiddler_field "$TITLE" "answer")
        D=$(get_tiddler_field "$TITLE" "difficulty")
        BODY=$(get_tiddler_text "$TITLE")
    fi
    
    jq -n \
      --arg title "$TITLE" \
      --arg exists "$EXISTS" \
      --arg tags "$TAGS" \
      --arg q "$Q" \
      --arg a "$A" \
      --arg d "$D" \
      --arg body "$BODY" \
      '{title: $title, exists: ($exists=="true"), tags: $tags, question: $q, answer: $a, difficulty: $d, body: $body}'
}

# Fetch data for all cards and the deck
C1=$(get_tiddler_json "Beta-Blockers Mechanism")
C2=$(get_tiddler_json "ACE Inhibitor Side Effects")
C3=$(get_tiddler_json "Warfarin Interactions")
C4=$(get_tiddler_json "Statin Mechanism")
C5=$(get_tiddler_json "Metformin Contraindication")
DECK=$(get_tiddler_json "Pharmacology Deck")

# Assemble final verification JSON object
jq -n \
  --arg init "$INITIAL_COUNT" \
  --arg curr "$CURRENT_COUNT" \
  --arg gui "$GUI_SAVE_DETECTED" \
  --argjson c1 "$C1" \
  --argjson c2 "$C2" \
  --argjson c3 "$C3" \
  --argjson c4 "$C4" \
  --argjson c5 "$C5" \
  --argjson deck "$DECK" \
  '{
    initial_count: ($init|tonumber),
    current_count: ($curr|tonumber),
    gui_save_detected: ($gui=="true"),
    cards: [$c1, $c2, $c3, $c4, $c5],
    deck: $deck
  }' > /tmp/task_result.json

cat /tmp/task_result.json
echo "=== Export complete ==="