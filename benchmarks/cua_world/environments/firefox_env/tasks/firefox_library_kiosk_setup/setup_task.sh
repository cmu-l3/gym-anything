#!/bin/bash
echo "=== Setting up Firefox Library Kiosk Task ==="

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Create the local portal file requested in the task description
mkdir -p /workspace/assets
cat > /workspace/assets/library_portal.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Library Portal</title>
    <style>
        body { font-family: sans-serif; text-align: center; margin-top: 50px; background-color: #f4f4f9; }
        h1 { color: #333; }
        .container { background: white; padding: 40px; border-radius: 8px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); display: inline-block; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Welcome to the University Library</h1>
        <p>Please use this public research terminal responsibly.</p>
        <p><strong>Note:</strong> Browsing history is cleared automatically between sessions.</p>
    </div>
</body>
</html>
EOF
chmod 644 /workspace/assets/library_portal.html
chown ga:ga /workspace/assets/library_portal.html

# Ensure Firefox is closed initially to clear locks and reset state
pkill -f firefox 2>/dev/null || true
sleep 2

# Start Firefox cleanly
su - ga -c "DISPLAY=:1 firefox about:blank >/dev/null 2>&1 &"

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Mozilla Firefox"; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done

# Maximize and focus the window to ensure agent visibility
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true

# Settle UI
sleep 2

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="