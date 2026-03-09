#!/bin/bash
set -e

echo "=== Finalizing JPEG export task ==="

# Install xdotool if not present
apt-get update -qq && apt-get install -y -qq xdotool wmctrl || true

# Click on center of the screen (so if workspaces are open, we can focus on the first one)
# su - ga -c "DISPLAY=:1 xdotool mousemove --sync 800 600 click 1" || true
sleep 1

# Focus GIMP window to ensure any dialogs are visible
echo "🎯 Ensuring GIMP window focus..."
wid=$(wmctrl -l | grep -i 'GIMP' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    echo "GIMP window ID: $wid"
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
    sleep 1
fi

# Check if export was successful by looking for common JPEG filenames
echo "🔍 Checking for exported JPEG files..."
exported_files=$(find /home/ga/Desktop -name "*.jpg" -o -name "*.jpeg" 2>/dev/null | head -5)

if [ -n "$exported_files" ]; then
    echo "✅ JPEG export found:"
    echo "$exported_files" | while read file; do
        if [ -f "$file" ]; then
            echo "  - $(basename "$file") ($(stat --format="%s" "$file") bytes)"
            chown ga:ga "$file"
        fi
    done
else
    echo "⚠️ No JPEG files found on Desktop, checking for common export names..."
    find /home/ga -name "*export*" -name "*.jpg" -o -name "*photo*" -name "*.jpg" 2>/dev/null | head -5
fi

echo "=== JPEG export finalization completed ==="