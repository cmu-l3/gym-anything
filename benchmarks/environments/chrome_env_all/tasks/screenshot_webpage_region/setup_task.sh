#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Screenshot Webpage Region Task Setup ==="
echo "Task: Capture screenshot of specific webpage content using DevTools"

# Install required utilities including image processing libraries
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Install Python image processing libraries for verification
pip3 install -q pillow imagehash 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create the test HTML page with distinctive content to screenshot
echo "Creating test page with screenshot target content..."
TEST_PAGE_DIR="/home/ga/Documents"
mkdir -p "$TEST_PAGE_DIR"

cat > "$TEST_PAGE_DIR/analytics_report.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Q4 2024 Analytics Dashboard</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 0;
            padding: 40px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
        }
        .dashboard-container {
            max-width: 1200px;
            margin: 0 auto;
        }
        .header {
            background: white;
            padding: 30px;
            border-radius: 12px;
            margin-bottom: 30px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.1);
        }
        .header h1 {
            margin: 0 0 10px 0;
            color: #2c3e50;
            font-size: 32px;
        }
        .header p {
            margin: 0;
            color: #7f8c8d;
            font-size: 14px;
        }
        
        /* TARGET CONTENT FOR SCREENSHOT */
        .chart-card {
            background: white;
            border-radius: 12px;
            padding: 40px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.1);
            margin-bottom: 30px;
        }
        .chart-card h2 {
            margin: 0 0 25px 0;
            color: #2c3e50;
            font-size: 24px;
            border-bottom: 3px solid #667eea;
            padding-bottom: 15px;
        }
        .chart-visualization {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            height: 320px;
            border-radius: 8px;
            display: flex;
            align-items: center;
            justify-content: center;
            flex-direction: column;
            color: white;
            position: relative;
            overflow: hidden;
        }
        .chart-visualization::before {
            content: '';
            position: absolute;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background: repeating-linear-gradient(
                90deg,
                rgba(255,255,255,0.1) 0px,
                rgba(255,255,255,0.1) 1px,
                transparent 1px,
                transparent 50px
            );
        }
        .chart-main-value {
            font-size: 72px;
            font-weight: bold;
            margin: 0;
            text-shadow: 0 4px 8px rgba(0,0,0,0.2);
            z-index: 1;
        }
        .chart-label {
            font-size: 24px;
            margin: 10px 0 0 0;
            opacity: 0.9;
            z-index: 1;
        }
        .chart-trend {
            font-size: 20px;
            margin: 15px 0 0 0;
            padding: 8px 20px;
            background: rgba(255,255,255,0.2);
            border-radius: 20px;
            z-index: 1;
        }
        .metric-row {
            display: grid;
            grid-template-columns: repeat(3, 1fr);
            gap: 20px;
            margin-top: 25px;
        }
        .metric-item {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 8px;
            text-align: center;
        }
        .metric-item .value {
            font-size: 28px;
            font-weight: bold;
            color: #667eea;
            margin: 0 0 5px 0;
        }
        .metric-item .label {
            font-size: 14px;
            color: #7f8c8d;
            margin: 0;
        }
        
        .footer-content {
            background: white;
            padding: 20px 30px;
            border-radius: 12px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.1);
            text-align: center;
            color: #7f8c8d;
        }
    </style>
</head>
<body>
    <div class="dashboard-container">
        <div class="header">
            <h1>📊 Q4 2024 Analytics Dashboard</h1>
            <p>Real-time business intelligence and performance metrics</p>
        </div>
        
        <!-- THIS IS THE TARGET CONTENT FOR SCREENSHOT -->
        <div class="chart-card">
            <h2>💰 Total Revenue - Q4 2024</h2>
            <div class="chart-visualization">
                <p class="chart-main-value">$2.4M</p>
                <p class="chart-label">Quarterly Revenue</p>
                <p class="chart-trend">▲ +23% YoY Growth</p>
            </div>
            <div class="metric-row">
                <div class="metric-item">
                    <p class="value">$847K</p>
                    <p class="label">October Revenue</p>
                </div>
                <div class="metric-item">
                    <p class="value">$792K</p>
                    <p class="label">November Revenue</p>
                </div>
                <div class="metric-item">
                    <p class="value">$761K</p>
                    <p class="label">December Revenue</p>
                </div>
            </div>
        </div>
        
        <div class="footer-content">
            <p>Generated on: December 31, 2024 | Data updated hourly</p>
        </div>
    </div>
</body>
</html>
EOF

chown ga:ga "$TEST_PAGE_DIR/analytics_report.html"
echo "✓ Test page created at: $TEST_PAGE_DIR/analytics_report.html"

# Ensure Chrome is properly focused and ready
echo "Setting up Chrome for task..."

# Check if Chrome is running
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome not running, starting it..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh about:blank" &
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

# Navigate to the test page
TEST_PAGE_URL="file:///home/ga/Documents/analytics_report.html"
echo "Navigating to test page: $TEST_PAGE_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'file:///home/ga/Documents/analytics_report.html'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 4

# Scroll to ensure the chart is visible and centered
echo "Positioning viewport to show target content..."
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Home" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Page_Down" || true
sleep 0.5

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    ACTIVE_URL=$(curl -s http://localhost:9222/json | jq -r '[.[] | select(.type == "page")][0].url // ""')
    echo "✓ Active URL: $ACTIVE_URL"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Record task start time for verification
date +%s > /tmp/screenshot_task_start_time.txt
echo "✓ Task start time recorded"

# Clear Downloads folder to ensure clean state
echo "Clearing Downloads folder for clean test..."
rm -f /home/ga/Downloads/Screenshot*.png 2>/dev/null || true
rm -f /home/ga/Downloads/screenshot*.png 2>/dev/null || true

echo "=== Setup complete ==="
echo "Chrome is displaying the analytics dashboard."
echo "Target content: Q4 2024 Revenue Chart (purple gradient with $2.4M)"
echo ""
echo "Agent should now:"
echo "  1. Press F12 to open DevTools"
echo "  2. Press Ctrl+Shift+P to open Command Menu"
echo "  3. Type 'screenshot' and select 'Capture screenshot'"
echo "  4. Screenshot will be saved to Downloads folder"