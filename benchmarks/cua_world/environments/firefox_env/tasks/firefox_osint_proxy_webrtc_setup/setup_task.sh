#!/bin/bash
echo "=== Setting up OSINT Proxy & WebRTC Setup task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create the directive document with realistic OSINT context
cat > /home/ga/Desktop/OPSEC_Directive.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>OPSEC Directive: Browser Network Isolation</title>
    <style>
        body { font-family: monospace; background-color: #f4f4f9; color: #333; margin: 40px; }
        .header { background-color: #8b0000; color: white; padding: 15px; font-weight: bold; font-size: 1.2em; }
        .warning { border-left: 5px solid red; padding: 10px; background-color: #fff0f0; margin-top: 20px; }
        .config-box { background-color: #fff; border: 1px solid #ccc; padding: 15px; margin-top: 20px; }
        .code { font-weight: bold; color: #005500; }
    </style>
</head>
<body>
    <div class="header">CLASSIFIED // OPSEC DIRECTIVE // OSINT OPERATIONS</div>
    
    <div class="warning">
        <strong>CRITICAL WARNING:</strong> Operating without proxy isolation will result in immediate IP leakage. Ensure all parameters below are exactly matched before commencing collection.
    </div>

    <div class="config-box">
        <h3>REQUIRED BROWSER CONFIGURATION</h3>
        <p>1. Route all traffic through the local tunnel:</p>
        <ul>
            <li>Proxy Type: <strong>Manual proxy configuration</strong></li>
            <li>SOCKS Host: <span class="code">127.0.0.1</span></li>
            <li>Port: <span class="code">9050</span></li>
            <li>Protocol: <strong>SOCKS v5</strong></li>
            <li>DNS Leak Prevention: <strong>Proxy DNS when using SOCKS v5</strong> MUST be enabled</li>
        </ul>

        <p>2. Disable WebRTC to prevent STUN/TURN IP leaks:</p>
        <ul>
            <li>Navigate to Advanced Preferences</li>
            <li>Target Preference: <span class="code">media.peerconnection.enabled</span></li>
            <li>Required Value: <strong>false</strong></li>
        </ul>
        
        <p><em>Notice: Browser must be completely restarted/closed after applying changes to persist to disk.</em></p>
    </div>
</body>
</html>
EOF
chown ga:ga /home/ga/Desktop/OPSEC_Directive.html

# Start Firefox and open the directive
if ! pgrep -f "firefox" > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox /home/ga/Desktop/OPSEC_Directive.html &"
    sleep 5
fi

# Wait for Firefox window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla"; then
        break
    fi
    sleep 1
done

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Focus Firefox
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="