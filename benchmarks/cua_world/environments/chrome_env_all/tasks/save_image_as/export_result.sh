#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Image Download Task Export: save_image_as@1 ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create temporary verification directory
VERIFY_DIR="/tmp/image_download_verification"
mkdir -p "$VERIFY_DIR"

# Search for the downloaded image in Downloads folder
DOWNLOADS_DIR="/home/ga/Downloads"
echo "Searching for downloaded images in $DOWNLOADS_DIR..."

# List all recent image files (modified in last 5 minutes)
echo "Recent files in Downloads:"
find "$DOWNLOADS_DIR" -type f -mmin -5 2>/dev/null | while read -r file; do
    echo "  - $(basename "$file") ($(stat -c%s "$file") bytes)"
done

# Look for images matching expected filename patterns
POSSIBLE_NAMES=(
    "nature_photo.jpg"
    "nature_photo.jpeg"
    "nature_photo.png"
    "nature_photo"
    "ocean_waves.jpg"
    "ocean_waves.jpeg"
)

FOUND_IMAGE=""
for name in "${POSSIBLE_NAMES[@]}"; do
    if [ -f "$DOWNLOADS_DIR/$name" ]; then
        echo "✓ Found potential target: $name"
        FOUND_IMAGE="$name"
        break
    fi
done

if [ -n "$FOUND_IMAGE" ]; then
    echo "✓ Found downloaded image: $FOUND_IMAGE"
    cp "$DOWNLOADS_DIR/$FOUND_IMAGE" "$VERIFY_DIR/downloaded_image"
    echo "$FOUND_IMAGE" > "$VERIFY_DIR/image_filename.txt"
    ls -lh "$DOWNLOADS_DIR/$FOUND_IMAGE"
else
    echo "⚠ No matching image found by expected name, checking for any recent images..."
    
    # Find any image file created in the last 5 minutes
    RECENT_IMAGE=$(find "$DOWNLOADS_DIR" -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.gif" \) -mmin -5 -printf "%T@ %p\n" 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
    
    if [ -n "$RECENT_IMAGE" ] && [ -f "$RECENT_IMAGE" ]; then
        IMAGE_NAME=$(basename "$RECENT_IMAGE")
        echo "✓ Found recent image: $IMAGE_NAME"
        cp "$RECENT_IMAGE" "$VERIFY_DIR/downloaded_image"
        echo "$IMAGE_NAME" > "$VERIFY_DIR/image_filename.txt"
        ls -lh "$RECENT_IMAGE"
    else
        echo "✗ No recent image files found in Downloads folder"
        echo "none" > "$VERIFY_DIR/image_filename.txt"
        
        # List all files for debugging
        echo "All files in Downloads folder:"
        ls -lah "$DOWNLOADS_DIR" || true
    fi
fi

# Copy the original target image for comparison
echo "Copying original target image for verification..."
if [ -f "/home/ga/Pictures/test_gallery/ocean_waves.jpg" ]; then
    cp "/home/ga/Pictures/test_gallery/ocean_waves.jpg" "$VERIFY_DIR/original_image.jpg"
    echo "✓ Original image copied for comparison"
fi

# Capture active tab URL via CDP for additional context
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > "$VERIFY_DIR/final_url.txt"
fi

# Take a final screenshot
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved"
fi

# Copy verification info to standard temp location for verifier access
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

echo "✅ Export complete"
echo "Verification files copied to: $VERIFY_DIR"