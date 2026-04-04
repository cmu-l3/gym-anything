#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Image Download Task Setup: save_image_as@1 ==="
echo "Task: Download a specific image using right-click 'Save image as...' menu"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip imagemagick || true

# Install Python libraries for image creation and verification
pip3 install -q pillow 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create test images and HTML page
echo "Creating test images and gallery page..."
IMAGES_DIR="/home/ga/Pictures/test_gallery"
mkdir -p "$IMAGES_DIR"

# Create test images using ImageMagick (simple colored rectangles with text)
convert -size 400x300 xc:skyblue -pointsize 40 -fill white -gravity center \
    -annotate +0+0 "Mountain\nScenery" "$IMAGES_DIR/mountain_landscape.jpg" 2>/dev/null || true

convert -size 400x300 xc:forestgreen -pointsize 40 -fill white -gravity center \
    -annotate +0+0 "Forest\nView" "$IMAGES_DIR/forest_scene.jpg" 2>/dev/null || true

convert -size 400x300 xc:orange -pointsize 40 -fill white -gravity center \
    -annotate +0+0 "Desert\nSunset" "$IMAGES_DIR/desert_sunset.jpg" 2>/dev/null || true

convert -size 400x300 xc:steelblue -pointsize 40 -fill white -gravity center \
    -annotate +0+0 "Ocean\nWaves\n[TARGET]" "$IMAGES_DIR/ocean_waves.jpg" 2>/dev/null || true

chown -R ga:ga "$IMAGES_DIR"
echo "✓ Test images created at: $IMAGES_DIR"

# Create HTML gallery page
GALLERY_FILE="/home/ga/Documents/image_gallery.html"
mkdir -p /home/ga/Documents

cat > "$GALLERY_FILE" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Nature Photo Gallery</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 20px;
            background-color: #f5f5f5;
        }
        h1 {
            color: #333;
            text-align: center;
            margin-bottom: 30px;
        }
        .gallery {
            display: grid;
            grid-template-columns: repeat(2, 1fr);
            gap: 30px;
            max-width: 900px;
            margin: 0 auto;
        }
        .image-card {
            background: white;
            padding: 15px;
            border-radius: 8px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
            text-align: center;
        }
        .image-card img {
            width: 100%;
            height: auto;
            border-radius: 4px;
            cursor: pointer;
            border: 3px solid transparent;
            transition: border-color 0.3s;
        }
        .image-card img:hover {
            border-color: #4CAF50;
        }
        .image-card.target {
            border: 3px solid #FF5722;
            background-color: #FFF3E0;
        }
        .image-card.target::before {
            content: "⭐ TARGET IMAGE TO DOWNLOAD ⭐";
            display: block;
            font-weight: bold;
            color: #FF5722;
            margin-bottom: 10px;
            font-size: 14px;
        }
        .image-card h3 {
            margin: 10px 0 5px 0;
            color: #555;
        }
        .image-card p {
            color: #777;
            font-size: 14px;
            margin: 5px 0;
        }
        .instructions {
            background: #E3F2FD;
            padding: 20px;
            border-radius: 8px;
            max-width: 900px;
            margin: 20px auto;
            border-left: 4px solid #2196F3;
        }
        .instructions h2 {
            margin-top: 0;
            color: #1976D2;
        }
        .instructions ol {
            margin: 10px 0;
        }
        .instructions li {
            margin: 8px 0;
        }
    </style>
</head>
<body>
    <h1>🌍 Nature Photo Gallery</h1>
    
    <div class="instructions">
        <h2>📋 Task Instructions</h2>
        <p><strong>Goal:</strong> Download the TARGET IMAGE (marked with orange border) and save it as <code>nature_photo.jpg</code></p>
        <ol>
            <li>Locate the target image marked with orange border and star label</li>
            <li>Right-click on the target image</li>
            <li>Select "Save image as..." from the context menu</li>
            <li>Save the file as: <strong>nature_photo.jpg</strong> (or nature_photo without extension)</li>
            <li>Ensure the file is saved in the Downloads folder</li>
        </ol>
    </div>

    <div class="gallery">
        <div class="image-card">
            <img src="file:///home/ga/Pictures/test_gallery/mountain_landscape.jpg" 
                 alt="Mountain landscape with snow peaks" 
                 id="img1">
            <h3>Mountain Landscape</h3>
            <p>Scenic mountain view with snow-capped peaks</p>
        </div>

        <div class="image-card">
            <img src="file:///home/ga/Pictures/test_gallery/forest_scene.jpg" 
                 alt="Dense forest with tall trees" 
                 id="img2">
            <h3>Forest Scene</h3>
            <p>Lush green forest with towering trees</p>
        </div>

        <div class="image-card">
            <img src="file:///home/ga/Pictures/test_gallery/desert_sunset.jpg" 
                 alt="Desert landscape at sunset" 
                 id="img3">
            <h3>Desert Sunset</h3>
            <p>Golden desert dunes at twilight</p>
        </div>

        <div class="image-card target">
            <img src="file:///home/ga/Pictures/test_gallery/ocean_waves.jpg" 
                 alt="Ocean waves crashing on shore" 
                 id="target-image">
            <h3>Ocean Waves</h3>
            <p>Powerful waves on a pristine beach</p>
        </div>
    </div>

    <script>
        // Add visual feedback on image hover
        document.querySelectorAll('.image-card img').forEach(img => {
            img.addEventListener('contextmenu', (e) => {
                console.log('Right-click detected on image:', img.alt);
            });
        });
    </script>
</body>
</html>
EOF

chown ga:ga "$GALLERY_FILE"
echo "✓ Gallery HTML created at: $GALLERY_FILE"

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

# Navigate to the gallery page
GALLERY_URL="file:///home/ga/Documents/image_gallery.html"
echo "Navigating to: $GALLERY_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'file:///home/ga/Documents/image_gallery.html'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    ACTIVE_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""')
    echo "✓ Active URL: $ACTIVE_URL"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Ensure Downloads folder exists and is clean for this task
mkdir -p /home/ga/Downloads
chown ga:ga /home/ga/Downloads

# Remove any previous test downloads to ensure clean verification
rm -f /home/ga/Downloads/nature_photo.* /home/ga/Downloads/ocean_waves.* 2>/dev/null || true

echo "=== Setup complete ==="
echo "Chrome should be displaying the image gallery"
echo "Agent should now:"
echo "  1. Locate the TARGET IMAGE (orange border with star label)"
echo "  2. Right-click on the ocean waves image"
echo "  3. Select 'Save image as...' from context menu"
echo "  4. Save as: nature_photo.jpg in Downloads folder"