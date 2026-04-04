#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Secure DNS Configuration Task Setup ==="
echo "Task: Configure DNS-over-HTTPS with Cloudflare (1.1.1.1)"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 || true

# Wait for environment to be ready
sleep 2

# Create an instruction page for the agent
INSTRUCTION_HTML="/tmp/dns_config_instructions.html"
cat > "$INSTRUCTION_HTML" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>DNS Configuration Task</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 40px;
            line-height: 1.8;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }
        .container {
            max-width: 900px;
            margin: 0 auto;
            background: rgba(255, 255, 255, 0.95);
            padding: 40px;
            border-radius: 12px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.3);
            color: #333;
        }
        h1 {
            color: #667eea;
            border-bottom: 3px solid #667eea;
            padding-bottom: 10px;
            margin-bottom: 25px;
        }
        h2 {
            color: #764ba2;
            margin-top: 30px;
            margin-bottom: 15px;
        }
        .task-box {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 8px;
            border-left: 5px solid #667eea;
            margin: 20px 0;
        }
        .important {
            color: #d9534f;
            font-weight: bold;
            background: #fff3cd;
            padding: 2px 6px;
            border-radius: 3px;
        }
        code {
            background: #e9ecef;
            padding: 3px 8px;
            border-radius: 4px;
            font-family: 'Courier New', monospace;
            font-size: 0.95em;
            color: #495057;
        }
        ol {
            background: white;
            padding: 25px 25px 25px 45px;
            border-radius: 8px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
        }
        ol li {
            margin: 12px 0;
            line-height: 1.6;
        }
        .info-box {
            background: #d1ecf1;
            border: 1px solid #bee5eb;
            border-radius: 6px;
            padding: 15px;
            margin: 15px 0;
            color: #0c5460;
        }
        .highlight {
            background: #fff3cd;
            padding: 15px;
            border-radius: 6px;
            border-left: 4px solid #ffc107;
            margin: 15px 0;
        }
        ul {
            margin: 10px 0;
        }
        ul li {
            margin: 8px 0;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔒 Secure DNS Configuration Task</h1>
        
        <div class="task-box">
            <h3 style="margin-top:0;">📋 Objective</h3>
            <p>Configure Chrome to use <strong>Cloudflare's secure DNS (DNS-over-HTTPS)</strong> for enhanced privacy and security.</p>
        </div>

        <div class="info-box">
            <h3 style="margin-top:0;">💡 What is Secure DNS?</h3>
            <p><strong>DNS-over-HTTPS (DoH)</strong> encrypts your DNS queries to prevent eavesdropping and manipulation by third parties. Cloudflare's <strong>1.1.1.1</strong> service is a fast, privacy-focused DNS resolver that doesn't log your queries.</p>
        </div>

        <h2>📝 Required Configuration</h2>
        <div class="highlight">
            <ul>
                <li>Enable <span class="important">Use secure DNS</span></li>
                <li>Select <span class="important">Custom</span> provider option</li>
                <li>Choose <span class="important">Cloudflare (1.1.1.1)</span> from the dropdown</li>
                <li>Ensure configuration is saved</li>
            </ul>
        </div>

        <h2>🛣️ Navigation Path</h2>
        <ol>
            <li>Click the <strong>three-dot menu (⋮)</strong> in Chrome's top-right corner</li>
            <li>Select <code>Settings</code> from the dropdown menu</li>
            <li>In the left sidebar, click on <code>Privacy and security</code></li>
            <li>Click on <code>Security</code> in the main panel</li>
            <li>Scroll down to the <code>Advanced</code> section</li>
            <li>Find <code>Use secure DNS</code> toggle/option</li>
            <li>Enable the toggle if not already on</li>
            <li>Select <strong>"With custom"</strong> or <strong>"Choose another provider"</strong> (radio button)</li>
            <li>From the dropdown menu, select <code>Cloudflare (1.1.1.1)</code></li>
            <li>Verify the setting shows as configured</li>
        </ol>

        <div class="info-box">
            <h3 style="margin-top:0;">🔍 Alternative Path</h3>
            <p>You can also navigate directly to <code>chrome://settings/security</code> in the address bar to access the Security settings page.</p>
        </div>

        <h2>✅ Verification</h2>
        <p>Your configuration will be verified by checking Chrome's Preferences file for:</p>
        <ul>
            <li><code>dns_over_https.mode</code> set to <strong>"secure"</strong></li>
            <li><code>dns_over_https.templates</code> containing <strong>Cloudflare DNS URLs</strong></li>
        </ul>

        <div class="info-box" style="margin-top: 30px;">
            <p><em><strong>Note:</strong> DNS-over-HTTPS helps protect your privacy by encrypting DNS requests. This prevents your ISP or other network observers from seeing which websites you're visiting based on DNS queries.</em></p>
        </div>
    </div>
</body>
</html>
EOF

chown ga:ga "$INSTRUCTION_HTML" 2>/dev/null || true
echo "✓ Instruction page created at: $INSTRUCTION_HTML"

# Ensure Chrome is properly focused and ready
echo "Setting up Chrome for task..."

# Check if Chrome is running
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome not running, starting it..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh file://$INSTRUCTION_HTML" &
    sleep 5
else
    echo "Chrome is already running"
fi

# Wait for Chrome to be fully ready
sleep 2

# IMPORTANT: Click at center to select desktop (multi-desktop environments)
# This ensures we're on the first desktop where Chrome is running
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Chrome window using wmctrl
export DISPLAY=:1
wid=$(wmctrl -l | grep -i 'Google Chrome\|Chromium' | head -1 | awk '{print $1}')
if [ -z "$wid" ]; then
    echo "Warning: Could not find Chrome window"
else
    echo "Focusing Chrome window: $wid"
    wmctrl -i -a $wid || true
    sleep 1
fi

# Navigate to the instruction page
echo "Navigating to instruction page..."
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'file://$INSTRUCTION_HTML'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Check current DNS configuration (for debugging)
echo "Checking current DNS configuration..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
ALT_PROFILE="/home/ga/.config/google-chrome/Default"

if [ -f "$CHROME_PROFILE/Preferences" ]; then
    PREFS_PATH="$CHROME_PROFILE/Preferences"
elif [ -f "$ALT_PROFILE/Preferences" ]; then
    PREFS_PATH="$ALT_PROFILE/Preferences"
else
    PREFS_PATH=""
fi

if [ -n "$PREFS_PATH" ]; then
    DNS_MODE=$(jq -r '.dns_over_https.mode // "not_set"' "$PREFS_PATH" 2>/dev/null || echo "not_set")
    DNS_TEMPLATES=$(jq -r '.dns_over_https.templates // "not_set"' "$PREFS_PATH" 2>/dev/null || echo "not_set")
    echo "Current DNS mode: $DNS_MODE"
    echo "Current DNS templates: $DNS_TEMPLATES"
else
    echo "Could not find Preferences file (this is normal for fresh profile)"
fi

echo "=== Setup complete ==="
echo "Chrome is displaying DNS configuration instructions"
echo "Agent should now:"
echo "  1. Navigate to Chrome Settings (⋮ menu → Settings)"
echo "  2. Go to Privacy and security → Security"
echo "  3. Scroll to Advanced section"
echo "  4. Enable 'Use secure DNS' with custom provider"
echo "  5. Select Cloudflare (1.1.1.1) from dropdown"