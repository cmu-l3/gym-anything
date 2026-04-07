#!/bin/bash
echo "=== Setting up Firefox PDF Memory Profiling task ==="

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

PDF_PATH="/home/ga/Documents/Heavy_Scientific_Report.pdf"

# Download a real heavy PDF (GPT-4 Technical Report or similar public paper)
echo "Downloading real PDF dataset..."
URLS=(
    "https://cdn.openai.com/papers/gpt-4.pdf"
    "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf"
    "https://www.nasa.gov/specials/artemis/pdfs/NASA-Artemis-Plan.pdf"
)

for url in "${URLS[@]}"; do
    curl -sL "$url" -o "$PDF_PATH"
    if [ -f "$PDF_PATH" ]; then
        SIZE=$(stat -c%s "$PDF_PATH" 2>/dev/null || echo "0")
        if [ "$SIZE" -gt 10000 ]; then
            echo "Successfully downloaded PDF from $url (Size: $SIZE bytes)"
            break
        fi
    fi
    echo "Failed to download valid PDF from $url, trying next..."
done

# Ensure ownership and permissions are correct for the agent
chown ga:ga "$PDF_PATH"
chmod 644 "$PDF_PATH"

# Start Firefox if not running
if ! pgrep -f "firefox" > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox &"
    
    # Wait for the Firefox window to appear
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "firefox"; then
            echo "Firefox window detected"
            break
        fi
        sleep 1
    done
fi

# Maximize and focus Firefox
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Wait for browser to settle
sleep 2

# Clear any previous task artifacts if they exist
rm -f /home/ga/Documents/memory_baseline.json.gz 2>/dev/null
rm -f /home/ga/Documents/memory_peak.json.gz 2>/dev/null

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="