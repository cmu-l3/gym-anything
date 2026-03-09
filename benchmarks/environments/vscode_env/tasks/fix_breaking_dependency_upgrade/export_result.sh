#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Fix Breaking Dependency Upgrade Result ==="

WORKSPACE_DIR="/home/ga/workspace/price_scraper"

# Focus VSCode and save all files
focus_vscode_window
sleep 1

# Try to save all files (Ctrl+K S or Ctrl+Shift+S)
echo "Attempting to save all files..."
{
    safe_xdotool ga :1 key --delay 200 ctrl+k s
    sleep 1
} || {
    echo "⚠️ First save attempt with Ctrl+K S failed, trying Ctrl+S"
    safe_xdotool ga :1 key --delay 200 ctrl+s || true
}

# Give filesystem time to sync
sleep 2

# Copy all relevant files to /tmp for verification
echo "Copying files for verification..."

# Copy requirements.txt
if [ -f "$WORKSPACE_DIR/requirements.txt" ]; then
    cp "$WORKSPACE_DIR/requirements.txt" /tmp/requirements.txt
    echo "✅ Copied requirements.txt"
else
    echo "⚠️ requirements.txt not found"
    echo "" > /tmp/requirements.txt
fi

# Copy Python source files
for pyfile in "scraper/core.py" "scraper/utils.py" "scraper/proxy_handler.py" "tests/test_scraper.py"; do
    src_path="$WORKSPACE_DIR/$pyfile"
    dest_name=$(echo "$pyfile" | tr '/' '_')
    
    if [ -f "$src_path" ]; then
        cp "$src_path" "/tmp/$dest_name"
        echo "✅ Copied $pyfile"
    else
        echo "⚠️ $pyfile not found"
        echo "" > "/tmp/$dest_name"
    fi
done

# Create manifest of exported files
cat > /tmp/export_manifest.txt << EOF
requirements.txt
scraper_core.py
scraper_utils.py
scraper_proxy_handler.py
tests_test_scraper.py
EOF

echo "✅ Export complete"
echo "Files exported to /tmp/"
ls -lh /tmp/*.py /tmp/requirements.txt 2>/dev/null || true