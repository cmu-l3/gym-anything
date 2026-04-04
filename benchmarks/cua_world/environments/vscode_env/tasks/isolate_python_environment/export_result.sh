#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Isolate Python Environment Result ==="

WORKSPACE="/home/ga/workspace/sales_analysis"

# Save any open files
echo "Saving open files..."
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
} || {
    echo "⚠️ Failed to save files; continuing"
}

sleep 2

# Export virtual environment status
echo "Checking virtual environment..."
if [ -d "$WORKSPACE/venv" ]; then
    echo "Virtual environment exists" > /tmp/venv_status.txt
    
    # List venv structure
    ls -la "$WORKSPACE/venv/bin/" > /tmp/venv_binaries.txt 2>&1 || echo "No bin directory" > /tmp/venv_binaries.txt
    
    # List installed packages in venv
    if [ -f "$WORKSPACE/venv/bin/pip" ]; then
        sudo -u ga "$WORKSPACE/venv/bin/pip" list > /tmp/venv_packages.txt 2>&1 || echo "Failed to list packages" > /tmp/venv_packages.txt
    else
        echo "pip not found in venv" > /tmp/venv_packages.txt
    fi
    
    # Try to get package versions
    if [ -f "$WORKSPACE/venv/bin/python" ]; then
        sudo -u ga "$WORKSPACE/venv/bin/python" -c "import pandas; print('pandas=' + pandas.__version__)" > /tmp/venv_versions.txt 2>&1 || echo "" > /tmp/venv_versions.txt
        sudo -u ga "$WORKSPACE/venv/bin/python" -c "import numpy; print('numpy=' + numpy.__version__)" >> /tmp/venv_versions.txt 2>&1 || true
        sudo -u ga "$WORKSPACE/venv/bin/python" -c "import matplotlib; print('matplotlib=' + matplotlib.__version__)" >> /tmp/venv_versions.txt 2>&1 || true
    fi
    
    # Test if imports work
    if [ -f "$WORKSPACE/venv/bin/python" ]; then
        sudo -u ga "$WORKSPACE/venv/bin/python" -c "import pandas; import numpy; import matplotlib; print('IMPORTS_SUCCESS')" > /tmp/venv_import_test.txt 2>&1 || echo "IMPORTS_FAILED" > /tmp/venv_import_test.txt
    fi
else
    echo "Virtual environment NOT found" > /tmp/venv_status.txt
    echo "" > /tmp/venv_binaries.txt
    echo "" > /tmp/venv_packages.txt
    echo "" > /tmp/venv_versions.txt
    echo "NO_VENV" > /tmp/venv_import_test.txt
fi

# Export VSCode settings
echo "Exporting VSCode settings..."
if [ -f "$WORKSPACE/.vscode/settings.json" ]; then
    cp "$WORKSPACE/.vscode/settings.json" /tmp/vscode_workspace_settings.json
else
    echo "{}" > /tmp/vscode_workspace_settings.json
fi

# Also check user settings (less relevant but good for debugging)
if [ -f "/home/ga/.config/Code/User/settings.json" ]; then
    cp "/home/ga/.config/Code/User/settings.json" /tmp/vscode_user_settings.json 2>/dev/null || echo "{}" > /tmp/vscode_user_settings.json
else
    echo "{}" > /tmp/vscode_user_settings.json
fi

# Export site-packages structure for verification
if [ -d "$WORKSPACE/venv/lib" ]; then
    find "$WORKSPACE/venv/lib" -maxdepth 3 -type d -name "site-packages" > /tmp/site_packages_path.txt 2>&1 || echo "" > /tmp/site_packages_path.txt
    
    # List packages in site-packages
    SITE_PACKAGES=$(find "$WORKSPACE/venv/lib" -maxdepth 3 -type d -name "site-packages" | head -n 1)
    if [ -n "$SITE_PACKAGES" ] && [ -d "$SITE_PACKAGES" ]; then
        ls -la "$SITE_PACKAGES" | grep -E "(pandas|numpy|matplotlib)" > /tmp/site_packages_contents.txt 2>&1 || echo "" > /tmp/site_packages_contents.txt
    else
        echo "" > /tmp/site_packages_contents.txt
    fi
else
    echo "" > /tmp/site_packages_path.txt
    echo "" > /tmp/site_packages_contents.txt
fi

echo "✅ Export complete"
echo "Files exported to /tmp:"
echo "  - venv_status.txt"
echo "  - venv_binaries.txt"
echo "  - venv_packages.txt"
echo "  - venv_versions.txt"
echo "  - venv_import_test.txt"
echo "  - vscode_workspace_settings.json"
echo "  - site_packages_contents.txt"