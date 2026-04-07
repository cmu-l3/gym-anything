#!/bin/bash
echo "=== Exporting fix_failed_post results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

TARGET_FILE="/opt/socioboard/socioboard-api/publish/public/media/summer_sale_promo.jpg"
FILE_EXISTS="false"
FILE_SIZE=0
FILE_READABLE="false"

# Check if file was restored
if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$TARGET_FILE" 2>/dev/null || echo "0")
    
    # Check if file has read permissions for others/group (readable by the app)
    if [ -r "$TARGET_FILE" ]; then
        FILE_READABLE="true"
    fi
fi

# Fetch the document from MongoDB
MONGO_CMD=""
if command -v mongosh >/dev/null 2>&1; then
  MONGO_CMD="mongosh"
else
  MONGO_CMD="mongo"
fi

MONGO_DOC=$($MONGO_CMD socioboard --quiet --eval '
  var doc = db.scheduled_informations.findOne({schedule_id: "summer_sale_123"});
  if (doc) {
    print(JSON.stringify(doc));
  } else {
    print("{}");
  }
' 2>/dev/null)

# Fallback to empty JSON if query fails or output is malformed
if ! echo "$MONGO_DOC" | jq . >/dev/null 2>&1; then
  MONGO_DOC="{}"
fi

# Create JSON result securely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_readable": $FILE_READABLE,
    "mongo_doc": $MONGO_DOC
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="