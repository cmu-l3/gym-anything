#!/bin/bash
echo "=== Setting up bulk_document_embedded_media_triage task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up any stale artifacts
rm -f /tmp/task_result.json 2>/dev/null || true
for d in /home/ga/Cases/Document_Triage_2024*/; do
    [ -d "$d" ] && rm -rf "$d" && echo "Removed old case: $d"
done

# Prepare report directory
mkdir -p /home/ga/Reports
chown -R ga:ga /home/ga/Reports 2>/dev/null || true

# Prepare data directory
EVIDENCE_DIR="/home/ga/evidence/govdocs"
mkdir -p "$EVIDENCE_DIR"
cd "$EVIDENCE_DIR"

echo "Downloading real Wikipedia PDF articles (which contain embedded images)..."
# Download PDFs from Wikipedia REST API
wget -q -T 15 -O "Digital_forensics.pdf" "https://en.wikipedia.org/api/rest_v1/page/pdf/Digital_forensics" || true
wget -q -T 15 -O "Computer_security.pdf" "https://en.wikipedia.org/api/rest_v1/page/pdf/Computer_security" || true

# If downloads failed (e.g. no internet), generate a fallback PDF with an embedded image using Python
if [ ! -s "Digital_forensics.pdf" ]; then
    echo "Download failed, generating fallback synthetic PDF with embedded image..."
    python3 << 'PYEOF'
import sys
try:
    from PIL import Image
    # Create a simple image and save it as PDF
    img = Image.new('RGB', (400, 400), color='purple')
    img.save('Fallback_Evidence_Doc.pdf', 'PDF', resolution=100.0)
    print("Fallback PDF created.")
except Exception as e:
    print(f"Error creating fallback PDF: {e}")
PYEOF
fi

# Create the ZIP archive containing the documents
echo "Creating 000.zip..."
zip -q 000.zip *.pdf

if [ ! -s 000.zip ]; then
    echo "ERROR: Failed to create 000.zip"
    exit 1
fi

echo "Created data source: $EVIDENCE_DIR/000.zip ($(stat -c%s 000.zip) bytes)"
chown -R ga:ga "$EVIDENCE_DIR" 2>/dev/null || true

# Kill any running Autopsy instances
kill_autopsy

echo "Launching Autopsy..."
launch_autopsy

echo "Waiting for Autopsy process to start..."
wait_for_autopsy_window 300

# Wait for the Welcome dialog specifically
WELCOME_TIMEOUT=420
WELCOME_ELAPSED=0
WELCOME_FOUND=false

while [ $WELCOME_ELAPSED -lt $WELCOME_TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "welcome"; then
        echo "Welcome screen detected after ${WELCOME_ELAPSED}s"
        WELCOME_FOUND=true
        break
    fi
    # Nudge UI
    DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 5
    WELCOME_ELAPSED=$((WELCOME_ELAPSED + 5))
    
    if [ $((WELCOME_ELAPSED % 60)) -eq 0 ]; then
        if ! pgrep -f "/opt/autopsy" >/dev/null 2>&1; then
            echo "Autopsy died, relaunching..."
            launch_autopsy
        fi
    fi
done

if [ "$WELCOME_FOUND" = false ]; then
    echo "ERROR: Welcome screen did not appear"
else
    # Close any lingering popups to ensure focus
    sleep 3
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
fi

# Take initial screenshot showing Autopsy ready
take_screenshot /tmp/task_initial.png ga

echo "=== Setup complete ==="