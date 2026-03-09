#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Download History Search Task Setup: download_history_search@1 ==="
echo "Task: Locate downloaded files using Chrome's download management interface"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip wget || true

# Install Python libraries for verification
pip3 install -q requests 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create Downloads directory if it doesn't exist
DOWNLOADS_DIR="/home/ga/Downloads"
mkdir -p "$DOWNLOADS_DIR"
chown ga:ga "$DOWNLOADS_DIR"

# Seed download history by downloading test files
echo "Creating sample downloaded files..."

# We'll use wget to download files, then import them into Chrome's download history
# For simplicity, we'll create local files and use Chrome to "download" them via file:// URLs

# Create temporary directory for source files
TEMP_SOURCE="/tmp/download_sources"
mkdir -p "$TEMP_SOURCE"

# Create sample documentation files with realistic names
echo "Creating sample file 1: database_architecture_guide.pdf"
cat > "$TEMP_SOURCE/database_architecture_guide.pdf" << 'EOF'
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
/MediaBox [0 0 612 792]
/Contents 4 0 R
/Resources <<
/Font <<
/F1 <<
/Type /Font
/Subtype /Type1
/BaseFont /Helvetica
>>
>>
>>
>>
endobj
4 0 obj
<<
/Length 100
>>
stream
BT
/F1 24 Tf
50 700 Td
(Database Architecture Guide) Tj
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
465
%%EOF
EOF

echo "Creating sample file 2: user_manual_v3.pdf"
cat > "$TEMP_SOURCE/user_manual_v3.pdf" << 'EOF'
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
/MediaBox [0 0 612 792]
/Contents 4 0 R
/Resources <<
/Font <<
/F1 <<
/Type /Font
/Subtype /Type1
/BaseFont /Helvetica
>>
>>
>>
>>
endobj
4 0 obj
<<
/Length 80
>>
stream
BT
/F1 24 Tf
50 700 Td
(User Manual v3) Tj
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
445
%%EOF
EOF

echo "Creating sample file 3: project_specifications.txt"
cat > "$TEMP_SOURCE/project_specifications.txt" << 'EOF'
Project Specifications Document
================================

This document outlines the technical specifications for the software project.

Key Requirements:
- Modular architecture
- RESTful API design
- Database integration
- Authentication and authorization
- Comprehensive testing suite

Last Updated: $(date)
EOF

echo "Creating sample file 4: reference_materials.zip"
cd "$TEMP_SOURCE"
mkdir -p reference_temp
echo "Reference document 1" > reference_temp/ref1.txt
echo "Reference document 2" > reference_temp/ref2.txt
zip -q reference_materials.zip reference_temp/*.txt
rm -rf reference_temp
cd -

# Copy files to Downloads folder with proper ownership
cp "$TEMP_SOURCE/database_architecture_guide.pdf" "$DOWNLOADS_DIR/"
cp "$TEMP_SOURCE/user_manual_v3.pdf" "$DOWNLOADS_DIR/"
cp "$TEMP_SOURCE/project_specifications.txt" "$DOWNLOADS_DIR/"
cp "$TEMP_SOURCE/reference_materials.zip" "$DOWNLOADS_DIR/"
chown -R ga:ga "$DOWNLOADS_DIR"

echo "✓ Created 4 sample files in Downloads folder"

# Now we need to make Chrome aware of these downloads
# We'll start Chrome and use it to download the files we created
echo "Setting up Chrome to register downloads..."

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

# Use Chrome to download files by navigating to file:// URLs
# This will register them in Chrome's download history
echo "Registering files in Chrome download history..."

download_file_via_chrome() {
    local filename="$1"
    local filepath="$TEMP_SOURCE/$filename"
    
    echo "Downloading: $filename"
    
    # Navigate to file URL
    su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
    sleep 0.3
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
    sleep 0.3
    su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 30 'file://$filepath'" || true
    sleep 0.3
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
    sleep 2
    
    # Press Ctrl+S to save (this registers it as a download)
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+s" || true
    sleep 1
    # Press Enter to confirm save dialog
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
    sleep 1
    # Press Escape to close any remaining dialogs
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Escape" || true
    sleep 0.5
}

# Download each file through Chrome
download_file_via_chrome "database_architecture_guide.pdf"
download_file_via_chrome "user_manual_v3.pdf"
download_file_via_chrome "project_specifications.txt"
download_file_via_chrome "reference_materials.zip"

# Navigate to Google as starting point for the task
echo "Navigating to starting URL: https://www.google.com"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://www.google.com'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Verify downloads exist
DOWNLOAD_COUNT=$(ls -1 "$DOWNLOADS_DIR" | wc -l)
echo "✓ Downloads folder contains $DOWNLOAD_COUNT file(s)"

echo "=== Setup complete ==="
echo "Downloaded files:"
ls -lh "$DOWNLOADS_DIR"
echo ""
echo "Agent task:"
echo "  1. Navigate to chrome://downloads/"
echo "  2. Search for 'database' in the search box"
echo "  3. Locate the database_architecture_guide.pdf in the download history"