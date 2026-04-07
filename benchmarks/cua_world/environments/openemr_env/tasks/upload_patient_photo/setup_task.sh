#!/bin/bash
# Setup script for Upload Patient Photo task

echo "=== Setting up Upload Patient Photo Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Target patient
PATIENT_PID=3
PATIENT_NAME="Jayson Fadel"
PHOTO_PATH="/home/ga/Documents/patient_photo.jpg"

# Record task start timestamp (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
TASK_START=$(cat /tmp/task_start_time.txt)
echo "Task start timestamp: $TASK_START"

# Verify patient exists in database
echo "Verifying patient $PATIENT_NAME (pid=$PATIENT_PID) exists..."
PATIENT_CHECK=$(openemr_query "SELECT pid, fname, lname FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null)
if [ -z "$PATIENT_CHECK" ]; then
    echo "ERROR: Patient not found in database!"
    exit 1
fi
echo "Patient found: $PATIENT_CHECK"

# Record initial document count for this patient (for anti-gaming)
echo "Recording initial document state..."
INITIAL_DOC_COUNT=$(openemr_query "SELECT COUNT(*) FROM documents WHERE foreign_id=$PATIENT_PID" 2>/dev/null || echo "0")
echo "$INITIAL_DOC_COUNT" > /tmp/initial_doc_count.txt
echo "Initial document count for patient: $INITIAL_DOC_COUNT"

# Record initial photo state from patient_data table
INITIAL_PHOTO=$(openemr_query "SELECT COALESCE(photo,'') FROM patient_data WHERE pid=$PATIENT_PID" 2>/dev/null || echo "")
echo "$INITIAL_PHOTO" > /tmp/initial_photo_state.txt
echo "Initial photo field: '$INITIAL_PHOTO'"

# List existing image files in documents directory (for comparison later)
find /var/www/html/openemr/sites/default/documents -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" \) 2>/dev/null > /tmp/initial_image_files.txt || true
INITIAL_IMAGE_COUNT=$(wc -l < /tmp/initial_image_files.txt 2>/dev/null || echo "0")
echo "Initial image files in documents: $INITIAL_IMAGE_COUNT"

# Create sample patient photo
echo "Creating sample patient photo..."
mkdir -p /home/ga/Documents

# Try to download a sample avatar image
if ! curl -s -L -o "$PHOTO_PATH" "https://www.gravatar.com/avatar/00000000000000000000000000000000?d=mp&s=200" 2>/dev/null; then
    echo "Gravatar download failed, trying alternative..."
fi

# Verify the image was downloaded, otherwise create a placeholder
if [ ! -f "$PHOTO_PATH" ] || [ ! -s "$PHOTO_PATH" ]; then
    echo "Creating placeholder image with ImageMagick..."
    # Create a simple colored placeholder with text
    if command -v convert &> /dev/null; then
        convert -size 200x200 xc:'#4a7db8' \
            -gravity center -fill white -pointsize 18 \
            -annotate 0 "Patient\nPhoto" \
            "$PHOTO_PATH" 2>/dev/null || true
    fi
fi

# Final fallback: copy any existing image
if [ ! -f "$PHOTO_PATH" ] || [ ! -s "$PHOTO_PATH" ]; then
    echo "Using Firefox icon as fallback placeholder..."
    # Try various system images
    for fallback in \
        "/usr/share/icons/hicolor/256x256/apps/firefox.png" \
        "/usr/share/icons/gnome/256x256/apps/utilities-terminal.png" \
        "/usr/share/pixmaps/debian-logo.png"; do
        if [ -f "$fallback" ]; then
            cp "$fallback" "$PHOTO_PATH" 2>/dev/null
            # Convert to jpg if needed
            if command -v convert &> /dev/null; then
                convert "$PHOTO_PATH" -resize 200x200 "$PHOTO_PATH" 2>/dev/null || true
            fi
            break
        fi
    done
fi

# Verify photo file exists
if [ -f "$PHOTO_PATH" ]; then
    PHOTO_SIZE=$(stat -c %s "$PHOTO_PATH" 2>/dev/null || echo "0")
    echo "Patient photo created: $PHOTO_PATH ($PHOTO_SIZE bytes)"
else
    echo "WARNING: Could not create patient photo file!"
fi

# Set ownership
chown ga:ga "$PHOTO_PATH" 2>/dev/null || true
chown -R ga:ga /home/ga/Documents 2>/dev/null || true

# Ensure Firefox is running on OpenEMR login page
echo "Ensuring Firefox is running..."
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

# Kill existing Firefox for clean state
pkill -f firefox 2>/dev/null || true
sleep 2

# Start Firefox
echo "Starting Firefox with OpenEMR..."
su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_task.log 2>&1 &"
sleep 5

# Wait for Firefox window
echo "Waiting for Firefox window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla"; then
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done

# Focus and maximize Firefox window
echo "Focusing Firefox window..."
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot for audit trail
sleep 2
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SCREENSHOT_SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Upload Patient Photo Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  1. Log in to OpenEMR"
echo "     - Username: admin"
echo "     - Password: pass"
echo ""
echo "  2. Find patient: $PATIENT_NAME"
echo ""
echo "  3. Navigate to Demographics/Patient Photo section"
echo ""
echo "  4. Upload photo from: $PHOTO_PATH"
echo ""
echo "  5. Save and verify photo appears on patient chart"
echo ""