#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Feature Flag Implementation Result ==="

WORKSPACE_DIR="/home/ga/workspace/payment_app"
EXPORT_DIR="/tmp/feature_flag_export"

# Create export directory
mkdir -p "$EXPORT_DIR"

# Focus VSCode and save all files
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
} || {
    echo "⚠️ Failed to trigger save all; continuing anyway"
}

sleep 2

# Export app.py
if [ -f "$WORKSPACE_DIR/app.py" ]; then
    echo "Exporting app.py..."
    cp "$WORKSPACE_DIR/app.py" "$EXPORT_DIR/app.py"
    echo "✅ app.py exported"
else
    echo "⚠️ app.py not found"
    echo "NOT_FOUND" > "$EXPORT_DIR/app.py"
fi

# Export .env file
if [ -f "$WORKSPACE_DIR/.env" ]; then
    echo "Exporting .env..."
    cp "$WORKSPACE_DIR/.env" "$EXPORT_DIR/.env"
    echo "✅ .env exported"
else
    echo "⚠️ .env not found"
    echo "NOT_FOUND" > "$EXPORT_DIR/.env"
fi

# Export payment_processor.py (for reference)
if [ -f "$WORKSPACE_DIR/payment_processor.py" ]; then
    cp "$WORKSPACE_DIR/payment_processor.py" "$EXPORT_DIR/payment_processor.py"
fi

# Export any feature_flags.py or config.py if created
find "$WORKSPACE_DIR" -maxdepth 1 -name "*feature*.py" -o -name "*config*.py" | while read -r file; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        echo "Exporting $filename..."
        cp "$file" "$EXPORT_DIR/$filename"
    fi
done

# Set permissions
chmod -R 755 "$EXPORT_DIR"

echo "✅ Export complete"
echo "📂 Export directory: $EXPORT_DIR"
ls -la "$EXPORT_DIR"