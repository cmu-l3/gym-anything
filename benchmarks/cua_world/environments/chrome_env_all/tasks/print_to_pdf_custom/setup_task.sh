#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Print-to-PDF with Custom Settings Task Setup ==="
echo "Task: Print webpage to PDF with landscape orientation, minimum margins, no headers/footers"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Install PDF processing libraries
pip3 install -q PyPDF2 pypdf pdfplumber pillow 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create the sample test page HTML file
echo "Creating sample test page HTML..."
TEST_PAGE_DIR="/home/ga/Documents"
mkdir -p "$TEST_PAGE_DIR"

cat > "$TEST_PAGE_DIR/test_print_page.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Test Print Page - Custom Settings</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            line-height: 1.6;
            margin: 30px;
            max-width: 1400px;
        }
        h1 { color: #2c3e50; margin-top: 20px; }
        h2 { color: #34495e; margin-top: 15px; }
        p { margin: 10px 0; text-align: justify; }
        .highlight { background-color: #f0f0f0; padding: 10px; margin: 10px 0; }
    </style>
</head>
<body>
    <h1>Test Document for Print Configuration</h1>
    
    <p>This is a test document to verify Chrome's print-to-PDF functionality with custom settings. This document should be printed in <strong>landscape orientation</strong> with <strong>minimum margins</strong> and <strong>no headers or footers</strong>.</p>
    
    <h2>Purpose of This Document</h2>
    <p>This test page helps verify that the agent can correctly configure Chrome's print settings to produce a PDF with specific formatting requirements. The settings being tested include page orientation, margin sizes, and the presence or absence of default headers and footers.</p>
    
    <div class="highlight">
        <h3>Required Print Settings</h3>
        <p><strong>Destination:</strong> Save as PDF</p>
        <p><strong>Orientation:</strong> Landscape (wider than tall)</p>
        <p><strong>Margins:</strong> Minimum or None (smallest possible margins)</p>
        <p><strong>Headers and Footers:</strong> Disabled (no URL or page numbers)</p>
        <p><strong>Scale:</strong> Default (100%)</p>
    </div>
    
    <h2>Content for Verification</h2>
    <p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.</p>
    
    <p>Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.</p>
    
    <h2>Testing Landscape Orientation</h2>
    <p>In landscape mode, this document should have its width greater than its height. This is particularly useful for wide tables, charts, or when you want to fit more content horizontally. The page dimensions should reflect this orientation in the final PDF.</p>
    
    <p>Landscape orientation is commonly used for presentations, wide spreadsheets, architectural drawings, and any content that benefits from a wider viewing area. The typical dimensions for letter-sized landscape pages are 11 inches wide by 8.5 inches tall, or 792 by 612 points in PDF measurements.</p>
    
    <h2>Verifying Minimal Margins</h2>
    <p>Minimum margins maximize the usable space on the page by reducing the white space around the content. Chrome's minimum margin setting typically creates margins of approximately 0.25 to 0.4 inches (18-30 points) on all sides of the page.</p>
    
    <p>This setting is useful when you want to fit more content on a page or when the content itself has built-in spacing. Be careful with minimal margins when printing on physical paper, as some printers cannot print to the very edge of the page and may clip content.</p>
    
    <h2>Headers and Footers Removal</h2>
    <p>By default, Chrome adds headers and footers to printed pages, including the page URL in the header and page numbers in the footer. For professional documents or when you want clean output, you should disable these automatic additions.</p>
    
    <p>When headers and footers are properly disabled, the top and bottom margins should be clean, with no URL text appearing at the top of the page and no page numbering at the bottom. This creates a cleaner, more professional-looking document.</p>
    
    <h2>Additional Content for Testing</h2>
    <p>This section provides additional text to ensure the PDF has sufficient content for verification. The verifier will extract text from the PDF to confirm that the content was properly rendered and that the print process completed successfully.</p>
    
    <p>Key phrases like "landscape orientation", "minimum margins", and "Test Document for Print Configuration" will be searched for in the PDF to verify content preservation. This ensures that the PDF is not empty or corrupted.</p>
    
    <div class="highlight">
        <h3>Success Criteria Summary</h3>
        <p>✓ PDF file exists in Downloads folder</p>
        <p>✓ Page width is greater than page height (landscape)</p>
        <p>✓ Margins are minimal (typically less than 30 points)</p>
        <p>✓ No URL or page numbers in header/footer regions</p>
        <p>✓ Original text content is preserved in the PDF</p>
    </div>
    
    <h2>Conclusion</h2>
    <p>This test page has been designed to have enough content to properly test margin settings and to provide verifiable text for the automated verification system. When printed correctly with the specified settings, it should produce a landscape-oriented PDF with minimal margins and no headers or footers.</p>
    
    <p>The automated verifier will analyze the PDF file's metadata and content to confirm that all required settings were correctly applied during the print process.</p>
</body>
</html>
EOF

chown ga:ga "$TEST_PAGE_DIR/test_print_page.html"
echo "✓ Test page HTML created at: $TEST_PAGE_DIR/test_print_page.html"

# Ensure Chrome is properly focused and on correct URL
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

# Navigate to the test page
TEST_PAGE_URL="file:///home/ga/Documents/test_print_page.html"
echo "Navigating to: $TEST_PAGE_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'file:///home/ga/Documents/test_print_page.html'" || true
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

echo "=== Setup complete ==="
echo "Chrome should be displaying the test print page"
echo "Agent should now:"
echo "  1. Press Ctrl+P to open print dialog"
echo "  2. Select 'Save as PDF' as destination"
echo "  3. Expand 'More settings' if needed"
echo "  4. Choose Landscape orientation"
echo "  5. Set margins to Minimum or None"
echo "  6. Uncheck 'Headers and footers'"
echo "  7. Save as: custom_print.pdf"