#!/bin/bash
echo "=== Exporting save_draft_post result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png
sleep 1

START_TIME=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Check for new media files in publish microservice (indicates successful upload)
NEW_MEDIA_COUNT=$(find /opt/socioboard/socioboard-api/publish -type f -newermt "@$START_TIME" \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" \) 2>/dev/null | wc -l || echo "0")
NEW_MEDIA_COUNT=$(echo "$NEW_MEDIA_COUNT" | xargs)
if [ -z "$NEW_MEDIA_COUNT" ]; then
    NEW_MEDIA_COUNT="0"
fi

# Dump Mongo documents containing the text
cat > /tmp/mongo_export.js << 'EOF'
var results = [];
db.getCollectionNames().forEach(function(c) {
  try {
    var docs = db.getCollection(c).find({
      $or: [
        { "postDetails": { $regex: "Q3 sustainability", $options: "i" } },
        { "description": { $regex: "Q3 sustainability", $options: "i" } },
        { "message": { $regex: "Q3 sustainability", $options: "i" } },
        { "text": { $regex: "Q3 sustainability", $options: "i" } },
        { "content": { $regex: "Q3 sustainability", $options: "i" } }
      ]
    }).toArray();
    docs.forEach(function(d) {
      if (d._id) d._id = d._id.toString();
      d._collection = c;
      results.push(d);
    });
  } catch (e) {
    // Ignore errors for unqueryable collections
  }
});
print("MONGO_RESULTS_START");
print(JSON.stringify(results));
print("MONGO_RESULTS_END");
EOF

MONGO_OUT=$(mongosh socioboard --quiet /tmp/mongo_export.js 2>/dev/null || mongo socioboard --quiet /tmp/mongo_export.js 2>/dev/null)
JSON_DOCS=$(echo "$MONGO_OUT" | awk '/MONGO_RESULTS_START/{flag=1; next} /MONGO_RESULTS_END/{flag=0} flag')

# Validate JSON before passing to jq
if ! echo "$JSON_DOCS" | jq . >/dev/null 2>&1; then
    JSON_DOCS="[]"
fi

# Export to result JSON securely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
jq -n \
  --arg new_media "$NEW_MEDIA_COUNT" \
  --arg timestamp "$(date -Iseconds)" \
  --argjson docs "$JSON_DOCS" \
  '{new_media_count: $new_media|tonumber, mongo_docs: $docs, timestamp: $timestamp}' > "$TEMP_JSON"

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="