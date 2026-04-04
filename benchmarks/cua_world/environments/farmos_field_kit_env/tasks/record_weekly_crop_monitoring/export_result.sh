#!/system/bin/sh
echo "=== Exporting task results ==="

PACKAGE="org.farmos.app"
DB_PATH="/data/data/$PACKAGE/databases"
EXPORT_DIR="/sdcard/task_export"

# Create export directory
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR/*"

# 1. Capture final visual state
screencap -p "$EXPORT_DIR/final_screenshot.png"
uiautomator dump "$EXPORT_DIR/ui_hierarchy.xml" 2>/dev/null

# 2. Attempt to export internal database (requires root/su)
# farmOS Field Kit usually uses a SQLite DB (often named distinctively or just 'webview.db' / 'Local Storage')
# We will copy the entire databases directory to analyze on host
echo "Attempting to export database files..."
if [ -d "$DB_PATH" ]; then
    # We use su to access /data/data
    su 0 cp -r "$DB_PATH" "$EXPORT_DIR/databases" 2>/dev/null
    chmod -R 777 "$EXPORT_DIR/databases"
else
    echo "WARNING: Database path $DB_PATH not found"
fi

# 3. Record task end time
date +%s > "$EXPORT_DIR/task_end_time.txt"

# 4. Create a manifest file for the verifier
echo "{" > "$EXPORT_DIR/manifest.json"
echo "  \"timestamp\": \"$(date)\"," >> "$EXPORT_DIR/manifest.json"
echo "  \"db_exported\": $([ -d "$EXPORT_DIR/databases" ] && echo "true" || echo "false")" >> "$EXPORT_DIR/manifest.json"
echo "}" >> "$EXPORT_DIR/manifest.json"

echo "Files exported to $EXPORT_DIR:"
ls -R "$EXPORT_DIR"

echo "=== Export complete ==="