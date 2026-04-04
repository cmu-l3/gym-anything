#!/bin/bash
# set -euo pipefail

echo "=== Exporting Organize Dev Terminals Result ==="

EXPORT_DIR="/tmp/terminal_task_export"
mkdir -p "$EXPORT_DIR"

# Give terminals time to stabilize
sleep 2

echo "1. Exporting terminal process information..."
# Get all bash/zsh processes owned by user ga
ps aux | grep -E "ga.*(bash|zsh)" | grep -v grep > "$EXPORT_DIR/terminal_processes.txt" 2>&1 || echo "No terminal processes found" > "$EXPORT_DIR/terminal_processes.txt"

echo "2. Exporting terminal working directories..."
# For each bash/zsh process, get its working directory
rm -f "$EXPORT_DIR/terminal_cwds.txt"
touch "$EXPORT_DIR/terminal_cwds.txt"

for pid in $(pgrep -u ga bash 2>/dev/null); do
    if [ -d "/proc/$pid" ]; then
        cwd=$(readlink -f "/proc/$pid/cwd" 2>/dev/null || echo "N/A")
        cmdline=$(cat "/proc/$pid/cmdline" 2>/dev/null | tr '\0' ' ' || echo "N/A")
        echo "$pid|$cwd|$cmdline" >> "$EXPORT_DIR/terminal_cwds.txt"
    fi
done

for pid in $(pgrep -u ga zsh 2>/dev/null); do
    if [ -d "/proc/$pid" ]; then
        cwd=$(readlink -f "/proc/$pid/cwd" 2>/dev/null || echo "N/A")
        cmdline=$(cat "/proc/$pid/cmdline" 2>/dev/null | tr '\0' ' ' || echo "N/A")
        echo "$pid|$cwd|$cmdline" >> "$EXPORT_DIR/terminal_cwds.txt"
    fi
done

echo "3. Counting terminal instances..."
terminal_count=$(wc -l < "$EXPORT_DIR/terminal_cwds.txt")
echo "Terminal count: $terminal_count" > "$EXPORT_DIR/terminal_count.txt"

echo "4. Checking working directories..."
# Check which required directories have terminals
grep -c "/frontend" "$EXPORT_DIR/terminal_cwds.txt" > "$EXPORT_DIR/frontend_count.txt" 2>&1 || echo "0" > "$EXPORT_DIR/frontend_count.txt"
grep -c "/backend" "$EXPORT_DIR/terminal_cwds.txt" > "$EXPORT_DIR/backend_count.txt" 2>&1 || echo "0" > "$EXPORT_DIR/backend_count.txt"
grep -c "/logs" "$EXPORT_DIR/terminal_cwds.txt" > "$EXPORT_DIR/logs_count.txt" 2>&1 || echo "0" > "$EXPORT_DIR/logs_count.txt"

echo "5. Taking screenshot of terminal panel..."
# Take full screenshot to capture terminal layout
su - ga -c "DISPLAY=:1 import -window root '$EXPORT_DIR/terminal_screenshot.png'" 2>/dev/null || \
    echo "Screenshot failed" > "$EXPORT_DIR/screenshot_error.txt"

echo "6. Attempting to export VSCode terminal state..."
# Try to access VSCode workspace storage (contains terminal state)
VSCODE_STORAGE="/home/ga/.config/Code/User/workspaceStorage"
if [ -d "$VSCODE_STORAGE" ]; then
    # Find workspace storage for dev_project
    for ws_dir in "$VSCODE_STORAGE"/*/; do
        if [ -f "${ws_dir}workspace.json" ]; then
            if grep -q "dev_project" "${ws_dir}workspace.json" 2>/dev/null; then
                echo "Found workspace storage: $ws_dir" > "$EXPORT_DIR/workspace_storage_path.txt"
                cp "${ws_dir}workspace.json" "$EXPORT_DIR/" 2>/dev/null || true
                
                # Try to export state.vscdb if it exists (contains terminal info)
                if [ -f "${ws_dir}state.vscdb" ]; then
                    cp "${ws_dir}state.vscdb" "$EXPORT_DIR/" 2>/dev/null || true
                fi
                break
            fi
        fi
    done
fi

echo "7. Export summary..."
echo "========================" > "$EXPORT_DIR/summary.txt"
echo "Terminal Organization Task Export" >> "$EXPORT_DIR/summary.txt"
echo "========================" >> "$EXPORT_DIR/summary.txt"
echo "Export timestamp: $(date)" >> "$EXPORT_DIR/summary.txt"
echo "Terminal count: $(cat $EXPORT_DIR/terminal_count.txt)" >> "$EXPORT_DIR/summary.txt"
echo "Terminals in frontend/: $(cat $EXPORT_DIR/frontend_count.txt)" >> "$EXPORT_DIR/summary.txt"
echo "Terminals in backend/: $(cat $EXPORT_DIR/backend_count.txt)" >> "$EXPORT_DIR/summary.txt"
echo "Terminals in logs/: $(cat $EXPORT_DIR/logs_count.txt)" >> "$EXPORT_DIR/summary.txt"
echo "" >> "$EXPORT_DIR/summary.txt"
echo "Working directories:" >> "$EXPORT_DIR/summary.txt"
cat "$EXPORT_DIR/terminal_cwds.txt" >> "$EXPORT_DIR/summary.txt"

echo "✅ Export complete!"
echo "Export location: $EXPORT_DIR"
echo ""
echo "Files exported:"
ls -lh "$EXPORT_DIR"
echo ""
cat "$EXPORT_DIR/summary.txt"