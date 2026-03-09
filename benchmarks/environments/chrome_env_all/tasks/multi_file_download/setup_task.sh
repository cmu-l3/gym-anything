#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Multiple File Downloads Task Setup ==="
echo "Task: Download three files (PDF, image, text) from a webpage"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Install Python libraries for verification
pip3 install -q pillow 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Generate test files for download
echo "Generating test files..."
TEST_FILES_DIR="/tmp/download_test_files"
mkdir -p "$TEST_FILES_DIR"

# Create sample PDF (minimal valid PDF with some content)
cat > "$TEST_FILES_DIR/sample.pdf" << 'EOF'
%PDF-1.4
1 0 obj
<<
/Type /Catalog
/Pages 2 0 R
>>
endobj
2 0 obj
<<
/Type /Pages
/Kids [3 0 R]
/Count 1
>>
endobj
3 0 obj
<<
/Type /Page
/Parent 2 0 R
/Resources <<
/Font <<
/F1 <<
/Type /Font
/Subtype /Type1
/BaseFont /Helvetica
>>
>>
>>
/MediaBox [0 0 612 792]
/Contents 4 0 R
>>
endobj
4 0 obj
<<
/Length 44
>>
stream
BT
/F1 12 Tf
100 700 Td
(Sample PDF Document) Tj
ET
endstream
endobj
xref
0 5
0000000000 65535 f 
0000000009 00000 n 
0000000058 00000 n 
0000000115 00000 n 
0000000317 00000 n 
trailer
<<
/Size 5
/Root 1 0 R
>>
startxref
410
%%EOF
EOF

echo "✓ Sample PDF created ($(stat -c%s "$TEST_FILES_DIR/sample.pdf") bytes)"

# Create sample PNG (1x1 red pixel, valid PNG)
printf '\x89\x50\x4e\x47\x0d\x0a\x1a\x0a\x00\x00\x00\x0d\x49\x48\x44\x52\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90\x77\x53\xde\x00\x00\x00\x0c\x49\x44\x41\x54\x08\xd7\x63\xf8\xcf\xc0\x00\x00\x03\x01\x01\x00\x18\xdd\x8d\xb4\x00\x00\x00\x00\x49\x45\x4e\x44\xae\x42\x60\x82' > "$TEST_FILES_DIR/image.png"

echo "✓ Sample PNG created ($(stat -c%s "$TEST_FILES_DIR/image.png") bytes)"

# Create sample text file
cat > "$TEST_FILES_DIR/document.txt" << 'EOF'
This is a sample text document for the Chrome download task.

The task tests the agent's ability to:
1. Identify download links on a webpage
2. Click each link to initiate downloads
3. Wait for downloads to complete
4. Ensure all files are saved correctly

This document serves as test content for verification purposes.
EOF

echo "✓ Sample TXT created ($(stat -c%s "$TEST_FILES_DIR/document.txt") bytes)"

# Create HTML test page with download links
echo "Creating download test page..."
cat > "$TEST_FILES_DIR/download_page.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Download Test Page - Multi-File Downloads</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            max-width: 700px;
            margin: 60px auto;
            padding: 30px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
        }
        .container {
            background: white;
            border-radius: 12px;
            padding: 40px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
        }
        h1 {
            color: #333;
            margin-bottom: 10px;
            font-size: 28px;
        }
        .subtitle {
            color: #666;
            margin-bottom: 30px;
            font-size: 14px;
        }
        .instruction {
            background: #f0f4ff;
            border-left: 4px solid #4285f4;
            padding: 15px;
            margin-bottom: 25px;
            border-radius: 4px;
        }
        .download-section {
            margin: 30px 0;
        }
        .download-link {
            display: flex;
            align-items: center;
            margin: 15px 0;
            padding: 18px 24px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            text-decoration: none;
            border-radius: 8px;
            transition: all 0.3s ease;
            box-shadow: 0 4px 15px rgba(102, 126, 234, 0.4);
        }
        .download-link:hover {
            transform: translateY(-2px);
            box-shadow: 0 6px 20px rgba(102, 126, 234, 0.6);
        }
        .download-link .icon {
            font-size: 32px;
            margin-right: 20px;
        }
        .download-link .info {
            flex-grow: 1;
        }
        .download-link .filename {
            font-weight: bold;
            font-size: 16px;
            display: block;
            margin-bottom: 4px;
        }
        .download-link .description {
            font-size: 13px;
            opacity: 0.9;
        }
        .footer {
            margin-top: 30px;
            padding-top: 20px;
            border-top: 1px solid #e0e0e0;
            color: #888;
            font-size: 12px;
            text-align: center;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>📥 File Download Test</h1>
        <p class="subtitle">Chrome Multi-File Download Task</p>
        
        <div class="instruction">
            <strong>Instructions:</strong> Click each download link below to download all three files to your Downloads folder.
        </div>

        <div class="download-section">
            <a href="file:///tmp/download_test_files/sample.pdf" download="sample.pdf" class="download-link" id="pdf-link">
                <span class="icon">📄</span>
                <div class="info">
                    <span class="filename">sample.pdf</span>
                    <span class="description">PDF document - Click to download</span>
                </div>
            </a>

            <a href="file:///tmp/download_test_files/image.png" download="image.png" class="download-link" id="png-link">
                <span class="icon">🖼️</span>
                <div class="info">
                    <span class="filename">image.png</span>
                    <span class="description">PNG image - Click to download</span>
                </div>
            </a>

            <a href="file:///tmp/download_test_files/document.txt" download="document.txt" class="download-link" id="txt-link">
                <span class="icon">📝</span>
                <div class="info">
                    <span class="filename">document.txt</span>
                    <span class="description">Text document - Click to download</span>
                </div>
            </a>
        </div>

        <div class="footer">
            Task: Download all three files (PDF, PNG, TXT) | Chrome Download Test
        </div>
    </div>

    <script>
        // Optional: Track download clicks for debugging
        document.querySelectorAll('.download-link').forEach(link => {
            link.addEventListener('click', function(e) {
                const filename = this.querySelector('.filename').textContent;
                console.log('Download initiated:', filename);
            });
        });
    </script>
</body>
</html>
EOF

echo "✓ Download test page created"

# Set proper permissions
chown -R ga:ga "$TEST_FILES_DIR"
chmod -R 755 "$TEST_FILES_DIR"

# Clear Downloads folder to start fresh
DOWNLOADS_DIR="/home/ga/Downloads"
echo "Clearing Downloads folder..."
rm -f "$DOWNLOADS_DIR/sample.pdf" "$DOWNLOADS_DIR/image.png" "$DOWNLOADS_DIR/document.txt" 2>/dev/null || true
echo "✓ Downloads folder cleared"

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

# Navigate to the download test page
DOWNLOAD_PAGE_URL="file://$TEST_FILES_DIR/download_page.html"
echo "Navigating to: $DOWNLOAD_PAGE_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 30 '$DOWNLOAD_PAGE_URL'" || true
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

# Record task start time for verification
date +%s > /tmp/task_start_time.txt

echo "=== Setup complete ==="
echo "Chrome is displaying the download test page with 3 download links"
echo "Agent should:"
echo "  1. Click 'sample.pdf' link to download PDF"
echo "  2. Click 'image.png' link to download PNG"
echo "  3. Click 'document.txt' link to download TXT"
echo "All files should be saved to: $DOWNLOADS_DIR"