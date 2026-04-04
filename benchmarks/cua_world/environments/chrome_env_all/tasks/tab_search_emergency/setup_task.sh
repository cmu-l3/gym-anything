#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Tab Search Emergency Task Setup: tab_search_emergency@1 ==="
echo "Task: Find flight booking tab among many open tabs using tab search"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-requests || true

# Wait for environment to be ready
sleep 2

# Create the mock flight booking HTML page
echo "Creating mock flight booking page..."
DOCUMENTS_DIR="/home/ga/Documents"
mkdir -p "$DOCUMENTS_DIR"

cat > "$DOCUMENTS_DIR/flight_booking_confirmation.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Flight Booking Confirmation - SkyTravel Airways</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            margin: 0;
            padding: 40px 20px;
            min-height: 100vh;
        }
        .container {
            max-width: 700px;
            margin: 0 auto;
            background: white;
            border-radius: 12px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
            overflow: hidden;
        }
        .header {
            background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%);
            color: white;
            padding: 30px;
            text-align: center;
        }
        .header h1 {
            margin: 0 0 10px 0;
            font-size: 28px;
        }
        .header .icon {
            font-size: 48px;
            margin-bottom: 10px;
        }
        .content {
            padding: 30px;
        }
        .confirmation-code {
            background: #f0f7ff;
            border-left: 4px solid #2196F3;
            padding: 20px;
            margin: 20px 0;
            border-radius: 4px;
        }
        .confirmation-code .label {
            font-size: 14px;
            color: #666;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        .confirmation-code .code {
            font-size: 32px;
            font-weight: bold;
            color: #2196F3;
            font-family: 'Courier New', monospace;
            margin-top: 5px;
        }
        .detail-section {
            margin: 25px 0;
        }
        .detail-section h2 {
            color: #1e3c72;
            font-size: 18px;
            margin-bottom: 15px;
            border-bottom: 2px solid #f0f0f0;
            padding-bottom: 8px;
        }
        .detail-row {
            display: flex;
            justify-content: space-between;
            padding: 12px 0;
            border-bottom: 1px solid #f5f5f5;
        }
        .detail-row:last-child {
            border-bottom: none;
        }
        .detail-label {
            font-weight: 600;
            color: #555;
        }
        .detail-value {
            color: #333;
            text-align: right;
        }
        .flight-route {
            display: flex;
            align-items: center;
            justify-content: space-between;
            background: #f8f9fa;
            padding: 20px;
            margin: 20px 0;
            border-radius: 8px;
        }
        .city {
            font-size: 24px;
            font-weight: bold;
            color: #1e3c72;
        }
        .airport-code {
            font-size: 14px;
            color: #666;
        }
        .arrow {
            font-size: 32px;
            color: #2196F3;
        }
        .status {
            display: inline-block;
            padding: 8px 16px;
            background: #4caf50;
            color: white;
            border-radius: 20px;
            font-weight: 600;
            font-size: 14px;
        }
        .footer {
            background: #f8f9fa;
            padding: 20px;
            text-align: center;
            color: #666;
            font-size: 14px;
        }
        .important-note {
            background: #fff3cd;
            border-left: 4px solid #ffc107;
            padding: 15px;
            margin: 20px 0;
            border-radius: 4px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <div class="icon">✈️</div>
            <h1>Flight Confirmed!</h1>
            <p>Your journey is all set</p>
        </div>
        
        <div class="content">
            <div class="confirmation-code">
                <div class="label">Booking Reference</div>
                <div class="code">ST-2024-9K7LP4</div>
            </div>
            
            <div class="detail-section">
                <h2>Passenger Information</h2>
                <div class="detail-row">
                    <span class="detail-label">Name:</span>
                    <span class="detail-value">Alex Morgan</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Email:</span>
                    <span class="detail-value">alex.morgan@email.com</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Phone:</span>
                    <span class="detail-value">+1 (555) 123-4567</span>
                </div>
            </div>
            
            <div class="detail-section">
                <h2>Flight Details</h2>
                
                <div class="flight-route">
                    <div>
                        <div class="city">San Francisco</div>
                        <div class="airport-code">SFO</div>
                    </div>
                    <div class="arrow">→</div>
                    <div>
                        <div class="city">Tokyo</div>
                        <div class="airport-code">NRT</div>
                    </div>
                </div>
                
                <div class="detail-row">
                    <span class="detail-label">Flight Number:</span>
                    <span class="detail-value">ST-7842</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Date:</span>
                    <span class="detail-value">April 22, 2024</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Departure Time:</span>
                    <span class="detail-value">14:30 PST</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Arrival Time:</span>
                    <span class="detail-value">18:45 JST (Apr 23)</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Duration:</span>
                    <span class="detail-value">11h 15m</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Seat:</span>
                    <span class="detail-value">14A (Window)</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Class:</span>
                    <span class="detail-value">Economy Premium</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Baggage:</span>
                    <span class="detail-value">2 x 23kg checked, 1 x 7kg cabin</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Status:</span>
                    <span class="detail-value"><span class="status">✓ CONFIRMED</span></span>
                </div>
            </div>
            
            <div class="important-note">
                <strong>⚠️ Important:</strong> Please arrive at the airport at least 3 hours before departure for international flights. Have your booking reference and passport ready for check-in.
            </div>
            
            <div class="detail-section">
                <h2>Payment Summary</h2>
                <div class="detail-row">
                    <span class="detail-label">Base Fare:</span>
                    <span class="detail-value">$1,245.00</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Taxes & Fees:</span>
                    <span class="detail-value">$187.50</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Seat Selection:</span>
                    <span class="detail-value">$45.00</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label"><strong>Total Paid:</strong></span>
                    <span class="detail-value"><strong>$1,477.50</strong></span>
                </div>
            </div>
        </div>
        
        <div class="footer">
            <p>Thank you for choosing SkyTravel Airways!</p>
            <p>Questions? Contact us at support@skytravel.com or +1-800-SKY-TRAVEL</p>
        </div>
    </div>
</body>
</html>
EOF

chown ga:ga "$DOCUMENTS_DIR/flight_booking_confirmation.html"
echo "✓ Mock flight booking page created at: $DOCUMENTS_DIR/flight_booking_confirmation.html"

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

# Close any extra tabs to start fresh
echo "Closing extra tabs to start fresh..."
for i in {1..10}; do
    TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "1")
    if [ "$TAB_COUNT" -gt 1 ]; then
        echo "Found $TAB_COUNT tabs, closing extras..."
        su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+w" || true
        sleep 0.3
    else
        break
    fi
done

sleep 1

# Function to open a tab with a URL
open_tab() {
    local url="$1"
    echo "Opening tab: $url"
    su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
    sleep 0.3
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+t" || true
    sleep 0.5
    su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 30 '$url'" || true
    sleep 0.3
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
    sleep 1.5
}

# Array of distractor URLs (realistic tabs someone might have open)
echo "Opening distractor tabs..."
DISTRACTOR_URLS=(
    "https://www.wikipedia.org"
    "https://news.ycombinator.com"
    "https://www.github.com"
    "https://stackoverflow.com"
    "https://www.reddit.com"
    "https://www.youtube.com"
    "https://www.amazon.com"
    "https://www.gmail.com"
    "https://www.linkedin.com"
    "https://www.twitter.com"
)

# Open distractor tabs first
for url in "${DISTRACTOR_URLS[@]}"; do
    open_tab "$url"
done

# Now open the TARGET flight booking page in a new tab
# This ensures it's NOT the first or last tab
TARGET_URL="file:///home/ga/Documents/flight_booking_confirmation.html"
echo "Opening TARGET flight booking tab..."
open_tab "$TARGET_URL"

# Open a couple more distractor tabs to bury the target further
open_tab "https://www.nytimes.com"
open_tab "https://docs.google.com"

# Navigate to one of the earlier tabs to make it active (not the flight booking)
echo "Switching to a distractor tab to hide the target..."
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
# Press Ctrl+1 to go to first tab
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+1" || true
sleep 1

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP and count tabs
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "unknown")
    echo "✓ Total tabs open: $TAB_COUNT"
    
    # List all tabs for debugging
    echo "Current tabs:"
    curl -s http://localhost:9222/json 2>/dev/null | jq -r '.[] | select(.type == "page") | "  - \(.title | .[0:50]) | \(.url | .[0:60])"' || true
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Scenario: You need to find your flight booking confirmation urgently!"
echo "The flight booking tab is hidden among $TAB_COUNT tabs."
echo "Agent should:"
echo "  1. Press Ctrl+Shift+A to open tab search"
echo "  2. Type keywords like 'flight' or 'booking' or 'confirmation'"
echo "  3. Select the correct tab from search results"
echo "  4. Press Enter to switch to the flight booking tab"