#!/bin/bash
set -e
echo "=== Setting up Firefox Hostile CSS Print Cleanup Task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create necessary directories
sudo -u ga mkdir -p /home/ga/Documents/Research

# Generate the hostile HTML file with real historical text
cat << 'EOF' > /home/ga/Documents/Research/Apollo_11_Report.html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Apollo 11 Mission Summary</title>
<style id="main-styles">
  body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 20px; background: #f4f4f9; }
  .header { background: #2c3e50; color: white; padding: 20px; text-align: center; font-size: 24px; margin-bottom: 20px; }
  #overlay-ad {
      position: fixed; top: 0; left: 0; width: 100%; height: 100%;
      background: rgba(220, 20, 60, 0.95); color: white; z-index: 9999;
      display: flex; align-items: center; justify-content: center;
      font-size: 40px; font-weight: bold; text-align: center;
  }
  #cookie-banner {
      position: fixed; bottom: 0; left: 0; width: 100%; background: #222;
      color: #fff; padding: 20px; z-index: 9998; text-align: center; font-size: 18px;
  }
  .article-content {
      background: white; padding: 40px; border-radius: 8px;
      box-shadow: 0 4px 6px rgba(0,0,0,0.1);
      line-height: 1.6; font-size: 14pt; color: #333; max-width: 800px; margin: 0 auto;
  }
</style>
<style id="hostile-print-css">
  @media print {
      .article-content { display: none !important; }
      #overlay-ad, #cookie-banner { display: none !important; }
      body::before { 
          content: "PRINTING IS DISABLED. COPYRIGHT 2026. ALL RIGHTS RESERVED."; 
          font-size: 30px; font-weight: bold; color: red;
          display: block; text-align: center; margin-top: 100px;
      }
  }
</style>
</head>
<body>
  <div id="overlay-ad">🚨 EXTREME FLASH SALE! 99% OFF! CLICK HERE! 🚨</div>
  <div id="cookie-banner">By using this site you agree to our 10,000 page terms of service and all tracking cookies.</div>
  
  <div class="header">Global Aerospace Research Database</div>
  <div class="article-content" id="main-text">
    <h1>Apollo 11 Mission Summary</h1>
    <p>Apollo 11 (July 16–24, 1969) was the American spaceflight that first landed humans on the Moon. Commander Neil Armstrong and Lunar Module Pilot Buzz Aldrin landed the Apollo Lunar Module Eagle on July 20, 1969, at 20:17 UTC, and Armstrong became the first person to step onto the Moon's surface six hours and 39 minutes later, on July 21 at 02:56 UTC.</p>
    <p>Aldrin joined him 19 minutes later, and they spent about two and a quarter hours together exploring the site they had named Tranquility Base upon landing. Armstrong and Aldrin collected 47.5 pounds (21.5 kg) of lunar material to bring back to Earth as pilot Michael Collins flew the Command Module Columbia in lunar orbit, and were on the Moon's surface for 21 hours, 36 minutes before lifting off to rejoin Columbia.</p>
    <br><br>
    <div style="padding: 15px; background: #eef; border-left: 4px solid #3b5998;">
        <strong>Confidential Archival Data:</strong> [MISSION_SUCCESS_CODE_77X9]
    </div>
  </div>
</body>
</html>
EOF

chown ga:ga /home/ga/Documents/Research/Apollo_11_Report.html

# Ensure no previous outputs exist
rm -f /home/ga/Documents/Research/Clean_Apollo_Report.pdf

# Start Firefox with the local file
if ! pgrep -f "firefox" > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox /home/ga/Documents/Research/Apollo_11_Report.html &"
    sleep 5
fi

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Firefox"; then
        break
    fi
    sleep 1
done

# Maximize window (CRITICAL for agent visibility)
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true
sleep 1

# Take screenshot of initial state (for evidence)
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="