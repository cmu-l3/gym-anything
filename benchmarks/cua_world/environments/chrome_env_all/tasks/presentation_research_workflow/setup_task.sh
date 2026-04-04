#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Multi-Source Presentation Research Task Setup ==="
echo "Task: Organize research sources and download materials for presentation"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip imagemagick || true

# Wait for environment to be ready
sleep 2

# Create the sample image resource page with downloadable image
echo "Creating sample resource page with downloadable image..."
RESOURCE_DIR="/home/ga/Documents"
mkdir -p "$RESOURCE_DIR"

# Generate a simple climate-related image using ImageMagick
echo "Generating sample climate infographic..."
convert -size 800x600 xc:skyblue \
    -pointsize 60 -fill darkblue -gravity north -annotate +0+50 "Climate Trends 2024" \
    -pointsize 30 -fill navy -gravity center -annotate +0-50 "Global Temperature Rise: +1.2°C" \
    -pointsize 30 -fill navy -gravity center -annotate +0+0 "Sea Level Rise: +20cm" \
    -pointsize 30 -fill navy -gravity center -annotate +0+50 "Arctic Ice Loss: -13% per decade" \
    -pointsize 20 -fill darkgreen -gravity south -annotate +0+20 "Source: Climate Research Initiative" \
    "$RESOURCE_DIR/climate_data_chart.png" 2>/dev/null || {
    # Fallback: create a simple colored rectangle if convert fails
    python3 -c "
from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGB', (800, 600), color='skyblue')
d = ImageDraw.Draw(img)
d.text((400, 100), 'Climate Trends 2024', fill='darkblue', anchor='mm')
d.text((400, 300), 'Global Temperature +1.2°C', fill='navy', anchor='mm')
img.save('$RESOURCE_DIR/climate_data_chart.png')
" 2>/dev/null || touch "$RESOURCE_DIR/climate_data_chart.png"
}

# Create HTML page that displays the image
cat > "$RESOURCE_DIR/climate_resources.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>IPCC - Climate Change Visualizations</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 1000px;
            margin: 40px auto;
            padding: 20px;
            background: #f5f5f5;
        }
        h1 { color: #003366; }
        h2 { color: #0066cc; margin-top: 30px; }
        .image-container {
            background: white;
            padding: 20px;
            margin: 20px 0;
            box-shadow: 0 2px 5px rgba(0,0,0,0.1);
            text-align: center;
        }
        img {
            max-width: 100%;
            border: 2px solid #ccc;
            cursor: pointer;
        }
        .caption {
            margin-top: 10px;
            color: #666;
            font-style: italic;
        }
        .info-box {
            background: #e6f2ff;
            padding: 15px;
            margin: 20px 0;
            border-left: 4px solid #0066cc;
        }
    </style>
</head>
<body>
    <h1>IPCC Climate Change Data Visualizations</h1>
    
    <div class="info-box">
        <strong>Note:</strong> These visualizations represent key climate indicators tracked by the 
        Intergovernmental Panel on Climate Change (IPCC). Right-click on any image to download 
        for use in presentations or reports.
    </div>

    <h2>Global Climate Trends Infographic</h2>
    <div class="image-container">
        <img src="file:///home/ga/Documents/climate_data_chart.png" 
             alt="Climate Infographic" 
             id="climate-infographic"
             title="Right-click to save this infographic">
        <div class="caption">
            Key climate indicators showing temperature rise, sea level changes, and arctic ice loss. 
            <br><strong>Recommended filename:</strong> climate_infographic.png
        </div>
    </div>

    <h2>Data Sources</h2>
    <p>This infographic synthesizes data from multiple authoritative sources including 
    World Bank climate databases, peer-reviewed research, and international climate monitoring agencies.</p>
    
    <div class="info-box">
        <strong>Usage Instructions:</strong> Right-click on the image above and select 
        "Save image as..." then name it <code>climate_infographic.png</code> for your presentation materials.
    </div>

</body>
</html>
EOF

chown -R ga:ga "$RESOURCE_DIR"
echo "✓ Resource page created at: file:///home/ga/Documents/climate_resources.html"

# Clear Downloads folder to ensure clean state
echo "Clearing Downloads folder..."
rm -f /home/ga/Downloads/*.png /home/ga/Downloads/*.jpg /home/ga/Downloads/*.jpeg 2>/dev/null || true

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

# Navigate to the resource page to start
RESOURCE_URL="file:///home/ga/Documents/climate_resources.html"
echo "Navigating to: $RESOURCE_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 '$RESOURCE_URL'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    INITIAL_TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "unknown")
    echo "✓ Starting with $INITIAL_TAB_COUNT tab(s)"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Display task instructions
echo "=== Setup complete ==="
echo ""
echo "Chrome is ready with the resource page open."
echo ""
echo "AGENT INSTRUCTIONS:"
echo "===================="
echo "You are preparing a presentation on 'Global Climate Trends' and need to:"
echo ""
echo "1. Navigate to research sources (open each in a new tab):"
echo "   - https://data.worldbank.org (World Bank climate data)"
echo "   - https://scholar.google.com (Academic research)"
echo "   - https://www.bbc.com/news (Current news coverage)"
echo ""
echo "2. Organize bookmarks:"
echo "   - Open Bookmark Manager (Ctrl+Shift+O or Menu > Bookmarks > Bookmark Manager)"
echo "   - Create a new folder named: 'Climate Presentation'"
echo "   - Bookmark each of the three research sources into this folder"
echo ""
echo "3. Download the infographic:"
echo "   - The current page shows a climate infographic"
echo "   - Right-click on the image"
echo "   - Select 'Save image as...'"
echo "   - Save it as: climate_infographic.png"
echo ""
echo "This workflow simulates organizing research materials for a real presentation."
echo "===================="