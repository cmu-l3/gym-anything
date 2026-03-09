#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Organize Service Terminals Result ==="

# Give VSCode time to settle
sleep 2

# Focus VSCode window before screenshot
focus_vscode_window || true
sleep 1

# Take full screenshot of VSCode window
echo "Taking screenshot..."
SCREENSHOT_PATH="/tmp/vscode_terminal_screenshot.png"
su - ga -c "DISPLAY=:1 import -window root '$SCREENSHOT_PATH'" 2>&1 || {
    echo "⚠️ Screenshot using import failed, trying scrot..."
    su - ga -c "DISPLAY=:1 scrot '$SCREENSHOT_PATH'" 2>&1 || {
        echo "⚠️ Screenshot failed"
    }
}

if [ -f "$SCREENSHOT_PATH" ]; then
    echo "✅ Screenshot saved: $SCREENSHOT_PATH"
    ls -lh "$SCREENSHOT_PATH"
else
    echo "❌ Screenshot not created"
fi

# Take focused screenshot of just the terminal panel region (bottom 30% of screen)
echo "Capturing terminal panel region..."
TERMINAL_REGION_PATH="/tmp/vscode_terminal_region.png"
su - ga -c "DISPLAY=:1 import -window root -crop 1920x400+0+680 '$TERMINAL_REGION_PATH'" 2>&1 || {
    echo "⚠️ Terminal region screenshot failed"
}

if [ -f "$TERMINAL_REGION_PATH" ]; then
    echo "✅ Terminal region saved: $TERMINAL_REGION_PATH"
else
    echo "⚠️ Terminal region not created, will use full screenshot"
fi

# Try to extract terminal info using xdotool/wmctrl
echo "Attempting to get window info..."
su - ga -c "DISPLAY=:1 wmctrl -l" > /tmp/window_list.txt 2>&1 || echo "" > /tmp/window_list.txt
su - ga -c "DISPLAY=:1 xdotool search --name 'Visual Studio Code' getwindowname" > /tmp/vscode_window_title.txt 2>&1 || echo "" > /tmp/vscode_window_title.txt

# Try OCR on terminal region immediately (helps with debugging)
if [ -f "$TERMINAL_REGION_PATH" ] && command -v tesseract &> /dev/null; then
    echo "Running OCR on terminal panel..."
    tesseract "$TERMINAL_REGION_PATH" /tmp/terminal_ocr_result 2>&1 || true
    if [ -f "/tmp/terminal_ocr_result.txt" ]; then
        echo "OCR preview (first 200 chars):"
        head -c 200 /tmp/terminal_ocr_result.txt
        echo ""
    fi
fi

# Export list of running processes (helps verify terminals exist)
ps aux | grep -E "(bash|zsh|terminal)" > /tmp/terminal_processes.txt 2>&1 || echo "" > /tmp/terminal_processes.txt

echo ""
echo "✅ Export complete"
echo "📸 Screenshot: $SCREENSHOT_PATH"
echo "📸 Terminal region: $TERMINAL_REGION_PATH"
echo "📋 Window info: /tmp/window_list.txt"
echo "📋 Process info: /tmp/terminal_processes.txt"