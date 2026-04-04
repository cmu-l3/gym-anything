#!/bin/bash
# set -euo pipefail

echo "=== Exporting Fix Syntax Highlighting Result ==="

WORKSPACE_DIR="/home/ga/workspace/template_project"
RESULTS_DIR="/tmp/syntax_highlighting_results"

# Create results directory
sudo -u ga mkdir -p "$RESULTS_DIR" 2>/dev/null || mkdir -p "$RESULTS_DIR"

# Copy user settings if they exist
USER_SETTINGS="/home/ga/.config/Code/User/settings.json"
if [ -f "$USER_SETTINGS" ]; then
    cp "$USER_SETTINGS" "$RESULTS_DIR/user_settings.json" 2>/dev/null || \
    sudo -u ga cp "$USER_SETTINGS" "$RESULTS_DIR/user_settings.json" 2>/dev/null || \
    cat "$USER_SETTINGS" > "$RESULTS_DIR/user_settings.json" 2>/dev/null || \
    echo "{}" > "$RESULTS_DIR/user_settings.json"
    
    if [ -s "$RESULTS_DIR/user_settings.json" ]; then
        echo "✅ Exported user settings"
    else
        echo "⚠️ User settings file empty or not copied"
        echo "{}" > "$RESULTS_DIR/user_settings.json"
    fi
else
    echo "{}" > "$RESULTS_DIR/user_settings.json"
    echo "⚠️ User settings not found at $USER_SETTINGS"
fi

# Copy workspace settings if they exist
WORKSPACE_SETTINGS="$WORKSPACE_DIR/.vscode/settings.json"
if [ -f "$WORKSPACE_SETTINGS" ]; then
    cp "$WORKSPACE_SETTINGS" "$RESULTS_DIR/workspace_settings.json" 2>/dev/null || \
    sudo -u ga cp "$WORKSPACE_SETTINGS" "$RESULTS_DIR/workspace_settings.json" 2>/dev/null || \
    cat "$WORKSPACE_SETTINGS" > "$RESULTS_DIR/workspace_settings.json" 2>/dev/null || \
    echo "{}" > "$RESULTS_DIR/workspace_settings.json"
    
    if [ -s "$RESULTS_DIR/workspace_settings.json" ]; then
        echo "✅ Exported workspace settings"
    else
        echo "⚠️ Workspace settings file empty or not copied"
        echo "{}" > "$RESULTS_DIR/workspace_settings.json"
    fi
else
    echo "{}" > "$RESULTS_DIR/workspace_settings.json"
    echo "ℹ️ No workspace settings found (this is OK - user settings may be used)"
fi

# Create a summary report
cat > "$RESULTS_DIR/report.txt" << EOF
Fix Syntax Highlighting Task - Export Report
=============================================

Task: Configure VSCode to recognize .tpl files as HTML

Settings Files Status:
- User Settings: $([ -f "$USER_SETTINGS" ] && echo "exists" || echo "not found")
- Workspace Settings: $([ -f "$WORKSPACE_SETTINGS" ] && echo "exists" || echo "not found")

Exported Files:
$(ls -lh "$RESULTS_DIR/" 2>/dev/null | grep -E '\.(json|txt)$' || echo "No files")

Export Timestamp: $(date -Iseconds)
Workspace Path: $WORKSPACE_DIR
EOF

echo ""
echo "✅ Export complete"
echo "Results directory: $RESULTS_DIR"
echo ""
echo "Exported files:"
ls -lh "$RESULTS_DIR/" 2>/dev/null || echo "Could not list files"