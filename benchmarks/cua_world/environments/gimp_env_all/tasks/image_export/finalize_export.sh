#!/bin/bash
set -e

echo "=== Finalizing image export task ==="

# Install xdotool if not present for basic window management
apt-get update -qq && apt-get install -y -qq xdotool wmctrl || true

# Just ensure we're in a clean state - don't automate the export since that's the task
echo "🔍 Checking export status..."

# Look for the exported file
if [ -f "/home/ga/Desktop/landscape_final.png" ]; then
    echo "✅ Export file found: landscape_final.png"
    ls -la /home/ga/Desktop/landscape_final.png
    chown ga:ga /home/ga/Desktop/landscape_final.png
    
    # Verify it's actually a PNG file
    file_type=$(file /home/ga/Desktop/landscape_final.png | grep -o "PNG image data" || echo "unknown")
    echo "📋 File type detected: $file_type"
elif [ -f "/home/ga/Desktop/landscape_final.PNG" ]; then
    echo "✅ Export file found with uppercase extension: landscape_final.PNG"
    ls -la /home/ga/Desktop/landscape_final.PNG
    chown ga:ga /home/ga/Desktop/landscape_final.PNG
else
    echo "⚠️ Target export file not found, checking for any related files..."
    find /home/ga/Desktop -name "*landscape*final*" 2>/dev/null | head -5
    find /home/ga/Desktop -name "*.png" -newer /home/ga/Desktop/landscape_image.jpg 2>/dev/null | head -5
fi

# Ensure GIMP window focus is maintained if still running
echo "🎯 Checking GIMP status..."
if pgrep -f "gimp" > /dev/null; then
    echo "📱 GIMP is still running"
    wid=$(wmctrl -l | grep -i 'GIMP' | awk '{print $1; exit}')
    if [ -n "$wid" ]; then
        echo "🎯 GIMP window ID: $wid"
        su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
    fi
else
    echo "📴 GIMP is not running"
fi

echo "=== Image export task finalized ==="