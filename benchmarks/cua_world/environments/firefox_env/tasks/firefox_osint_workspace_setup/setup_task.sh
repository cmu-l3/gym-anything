#!/bin/bash
echo "=== Setting up OSINT Workspace Setup task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure assets directory exists
mkdir -p /workspace/assets 2>/dev/null || sudo mkdir -p /workspace/assets

# Create the reference document with realistic intelligence data
cat > /workspace/assets/osint_reference.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>OSINT Reference - Threat Actor TTPs</title>
    <style>
        body { font-family: monospace; padding: 20px; background: #f0f0f0; }
        .container { background: white; padding: 20px; border: 1px solid #ccc; max-width: 800px; margin: 0 auto; }
        h1 { color: #8b0000; }
        .ioc { background: #eee; padding: 15px; border-left: 3px solid #8b0000; margin-bottom: 20px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>[TLP:RED] Threat Actor TTPs & Indicators</h1>
        <p><strong>Date:</strong> 2026-04-01</p>
        <p>This document contains critical indicators of compromise. Pin this to your toolbar for rapid cross-referencing during investigations.</p>
        <h2>Recent Infrastructure</h2>
        <div class="ioc">
            <p><strong>IP:</strong> 198.51.100.45</p>
            <p><strong>Domain:</strong> auth-portal-update[.]com</p>
            <p><strong>SHA256:</strong> e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855</p>
        </div>
        <p><em>Do not upload this document to external scanning services. Maintain local operational security.</em></p>
    </div>
</body>
</html>
EOF

chmod 644 /workspace/assets/osint_reference.html
chown -R ga:ga /workspace/assets 2>/dev/null || true

# Start Firefox if it is not already running
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox &"
    sleep 5
fi

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Mozilla Firefox"; then
        break
    fi
    sleep 1
done

# Maximize Firefox window to ensure full visibility for the agent
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true

# Dismiss any immediate dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take an initial screenshot to prove starting state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="