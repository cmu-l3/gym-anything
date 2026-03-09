#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Architecture Spike Result ==="

WORKSPACE_DIR="/home/ga/workspace"
EXPORT_DIR="/tmp/spike_export"

# Create export directory
mkdir -p "$EXPORT_DIR"

# Give VSCode time to save any open files
echo "Ensuring files are saved..."
focus_vscode_window 2>/dev/null || true
sleep 1
{
    safe_xdotool ga :1 key --delay 100 ctrl+shift+s  # Save all
} || {
    echo "⚠️ Could not send save-all command; continuing"
}
sleep 2

# Export spike directory structure
if [ -d "$WORKSPACE_DIR/session_spike" ]; then
    echo "Exporting session_spike directory..."
    cp -r "$WORKSPACE_DIR/session_spike" "$EXPORT_DIR/" 2>/dev/null || echo "Failed to copy session_spike"
else
    echo "⚠️ session_spike directory not found"
    mkdir -p "$EXPORT_DIR/session_spike"
fi

# Export VSCode configuration
if [ -d "$WORKSPACE_DIR/.vscode" ]; then
    echo "Exporting .vscode directory..."
    cp -r "$WORKSPACE_DIR/.vscode" "$EXPORT_DIR/" 2>/dev/null || echo "Failed to copy .vscode"
else
    echo "⚠️ .vscode directory not found"
    mkdir -p "$EXPORT_DIR/.vscode"
fi

# Export Git log
echo "Exporting Git history..."
cd "$WORKSPACE_DIR"
if [ -d ".git" ]; then
    git log --all --format="%H|%s|%an|%ad" > "$EXPORT_DIR/git_log.txt" 2>&1 || echo "No commits" > "$EXPORT_DIR/git_log.txt"
    git status --porcelain > "$EXPORT_DIR/git_status.txt" 2>&1 || echo "" > "$EXPORT_DIR/git_status.txt"
else
    echo "No git repository" > "$EXPORT_DIR/git_log.txt"
    echo "" > "$EXPORT_DIR/git_status.txt"
fi

# List all files for verification
echo "Listing workspace files..."
find "$WORKSPACE_DIR" -type f -not -path "*/\.git/*" -not -path "*/\.venv/*" > "$EXPORT_DIR/file_list.txt" 2>&1 || true

echo "✅ Export complete"
echo "Export location: $EXPORT_DIR"
echo ""
echo "📊 Summary:"
[ -f "$WORKSPACE_DIR/session_spike/redis_approach.py" ] && echo "  ✓ redis_approach.py" || echo "  ✗ redis_approach.py"
[ -f "$WORKSPACE_DIR/session_spike/memory_approach.py" ] && echo "  ✓ memory_approach.py" || echo "  ✗ memory_approach.py"
[ -f "$WORKSPACE_DIR/session_spike/benchmark.py" ] && echo "  ✓ benchmark.py" || echo "  ✗ benchmark.py"
[ -f "$WORKSPACE_DIR/session_spike/requirements.txt" ] && echo "  ✓ requirements.txt" || echo "  ✗ requirements.txt"
[ -f "$WORKSPACE_DIR/session_spike/FINDINGS.md" ] && echo "  ✓ FINDINGS.md" || echo "  ✗ FINDINGS.md"
[ -f "$WORKSPACE_DIR/.vscode/settings.json" ] && echo "  ✓ .vscode/settings.json" || echo "  ✗ .vscode/settings.json"
[ -f "$WORKSPACE_DIR/.vscode/launch.json" ] && echo "  ✓ .vscode/launch.json" || echo "  ✗ .vscode/launch.json"