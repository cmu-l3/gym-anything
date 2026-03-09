#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Advanced Link Opening Task Setup ==="
echo "Task: Test advanced link opening techniques (Ctrl+click, Shift+click, middle-click, context menu)"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-requests || true

# Wait for environment to be ready
sleep 2

# Create test pages directory
TEST_DIR="/home/ga/Documents/test_links"
mkdir -p "$TEST_DIR"

echo "Creating test HTML pages..."

# Create main index page with 5 links
cat > "$TEST_DIR/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Link Opening Test Page</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            max-width: 900px;
            margin: 40px auto;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }
        .container {
            background: white;
            color: #333;
            border-radius: 10px;
            padding: 40px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.3);
        }
        h1 {
            color: #667eea;
            border-bottom: 3px solid #667eea;
            padding-bottom: 15px;
            margin-bottom: 30px;
        }
        .instructions {
            background: #f8f9fa;
            border-left: 4px solid #667eea;
            padding: 20px;
            margin: 25px 0;
            border-radius: 5px;
        }
        .instructions h2 {
            margin-top: 0;
            color: #667eea;
            font-size: 1.3em;
        }
        .instructions ul {
            margin: 15px 0;
            padding-left: 25px;
        }
        .instructions li {
            margin: 10px 0;
            line-height: 1.6;
        }
        .instructions code {
            background: #e9ecef;
            padding: 2px 6px;
            border-radius: 3px;
            font-family: 'Courier New', monospace;
            color: #d63384;
        }
        .links-section {
            margin: 30px 0;
        }
        .link-item {
            margin: 20px 0;
            padding: 20px;
            background: #f8f9fa;
            border-radius: 8px;
            border: 2px solid #e9ecef;
            transition: all 0.3s ease;
        }
        .link-item:hover {
            border-color: #667eea;
            box-shadow: 0 4px 12px rgba(102, 126, 234, 0.2);
            transform: translateX(5px);
        }
        .link-item a {
            font-size: 20px;
            font-weight: 600;
            color: #667eea;
            text-decoration: none;
            display: block;
            margin-bottom: 8px;
        }
        .link-item a:hover {
            color: #764ba2;
            text-decoration: underline;
        }
        .link-item .instruction {
            color: #6c757d;
            font-size: 14px;
            font-style: italic;
        }
        .footer {
            margin-top: 40px;
            padding-top: 20px;
            border-top: 2px solid #e9ecef;
            color: #6c757d;
            font-size: 14px;
            text-align: center;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔗 Advanced Link Opening Workflow Test</h1>
        
        <div class="instructions">
            <h2>📋 Instructions</h2>
            <p>This page tests your knowledge of Chrome's advanced link opening techniques. Use the following methods to open each link:</p>
            <ul>
                <li><strong>Article A:</strong> <code>Ctrl+Click</code> - Opens in new background tab</li>
                <li><strong>Article B:</strong> <code>Shift+Click</code> - Opens in new window</li>
                <li><strong>Article C:</strong> <code>Middle-Click</code> (scroll wheel) - Opens in new background tab</li>
                <li><strong>Article D:</strong> Right-click → "Open link in new tab"</li>
                <li><strong>Article E:</strong> Right-click → "Open link in new window"</li>
            </ul>
            <p><strong>Goal:</strong> Successfully open all 5 articles using the specified methods. Your original tab should remain on this page after background tab operations.</p>
        </div>

        <div class="links-section">
            <h2>Test Links</h2>
            
            <div class="link-item">
                <a href="article-a.html" id="link-a">Article A - Technology Innovations</a>
                <div class="instruction">Method: Ctrl+Click (background tab)</div>
            </div>

            <div class="link-item">
                <a href="article-b.html" id="link-b">Article B - Science Breakthroughs</a>
                <div class="instruction">Method: Shift+Click (new window)</div>
            </div>

            <div class="link-item">
                <a href="article-c.html" id="link-c">Article C - Business Trends</a>
                <div class="instruction">Method: Middle-Click (background tab)</div>
            </div>

            <div class="link-item">
                <a href="article-d.html" id="link-d">Article D - Sports Updates</a>
                <div class="instruction">Method: Right-click → "Open link in new tab"</div>
            </div>

            <div class="link-item">
                <a href="article-e.html" id="link-e">Article E - Entertainment News</a>
                <div class="instruction">Method: Right-click → "Open link in new window"</div>
            </div>
        </div>

        <div class="footer">
            <p>💡 <strong>Tip:</strong> These shortcuts work in most modern browsers and are essential for efficient web navigation!</p>
        </div>
    </div>
</body>
</html>
EOF

# Create Article A page
cat > "$TEST_DIR/article-a.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Article A - Technology Innovations</title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 800px; margin: 50px auto; padding: 20px; line-height: 1.6; }
        h1 { color: #1a73e8; border-bottom: 3px solid #1a73e8; padding-bottom: 10px; }
        .meta { color: #5f6368; font-size: 14px; margin: 15px 0; }
    </style>
</head>
<body>
    <h1>Article A - Technology Innovations</h1>
    <div class="meta">Category: Technology | Published: 2025</div>
    <p>This article discusses the latest innovations in technology, including artificial intelligence, quantum computing, and blockchain technology. These advancements are reshaping how we interact with digital systems.</p>
    <p>Quantum computing promises to solve complex problems that are currently intractable for classical computers. Meanwhile, AI continues to automate and enhance various aspects of our daily lives.</p>
</body>
</html>
EOF

# Create Article B page
cat > "$TEST_DIR/article-b.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Article B - Science Breakthroughs</title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 800px; margin: 50px auto; padding: 20px; line-height: 1.6; }
        h1 { color: #0f9d58; border-bottom: 3px solid #0f9d58; padding-bottom: 10px; }
        .meta { color: #5f6368; font-size: 14px; margin: 15px 0; }
    </style>
</head>
<body>
    <h1>Article B - Science Breakthroughs</h1>
    <div class="meta">Category: Science | Published: 2025</div>
    <p>Recent scientific breakthroughs have opened new frontiers in medicine, physics, and environmental science. CRISPR gene editing, fusion energy, and climate modeling are transforming our understanding of the natural world.</p>
    <p>These discoveries have profound implications for human health, sustainable energy, and our ability to address global challenges.</p>
</body>
</html>
EOF

# Create Article C page
cat > "$TEST_DIR/article-c.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Article C - Business Trends</title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 800px; margin: 50px auto; padding: 20px; line-height: 1.6; }
        h1 { color: #f4b400; border-bottom: 3px solid #f4b400; padding-bottom: 10px; }
        .meta { color: #5f6368; font-size: 14px; margin: 15px 0; }
    </style>
</head>
<body>
    <h1>Article C - Business Trends</h1>
    <div class="meta">Category: Business | Published: 2025</div>
    <p>The business landscape is evolving rapidly with remote work, digital transformation, and sustainability becoming central themes. Companies are adapting their strategies to meet changing consumer expectations.</p>
    <p>E-commerce, fintech, and green technology are experiencing unprecedented growth as businesses embrace innovation and environmental responsibility.</p>
</body>
</html>
EOF

# Create Article D page
cat > "$TEST_DIR/article-d.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Article D - Sports Updates</title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 800px; margin: 50px auto; padding: 20px; line-height: 1.6; }
        h1 { color: #ea4335; border-bottom: 3px solid #ea4335; padding-bottom: 10px; }
        .meta { color: #5f6368; font-size: 14px; margin: 15px 0; }
    </style>
</head>
<body>
    <h1>Article D - Sports Updates</h1>
    <div class="meta">Category: Sports | Published: 2025</div>
    <p>The world of sports continues to captivate audiences with thrilling competitions, record-breaking performances, and inspiring athlete stories. From football to basketball, tennis to athletics, 2025 has been an exciting year.</p>
    <p>Technology is also playing an increasing role in sports, with advanced analytics, wearable devices, and video review systems enhancing both performance and fan experience.</p>
</body>
</html>
EOF

# Create Article E page
cat > "$TEST_DIR/article-e.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Article E - Entertainment News</title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 800px; margin: 50px auto; padding: 20px; line-height: 1.6; }
        h1 { color: #9c27b0; border-bottom: 3px solid #9c27b0; padding-bottom: 10px; }
        .meta { color: #5f6368; font-size: 14px; margin: 15px 0; }
    </style>
</head>
<body>
    <h1>Article E - Entertainment News</h1>
    <div class="meta">Category: Entertainment | Published: 2025</div>
    <p>Entertainment industry news covers the latest in film, television, music, and streaming platforms. Award-winning productions, celebrity interviews, and industry trends keep audiences engaged worldwide.</p>
    <p>Streaming services continue to revolutionize content consumption, while traditional media adapts to changing viewer preferences and technological innovations.</p>
</body>
</html>
EOF

# Set correct ownership
chown -R ga:ga "$TEST_DIR"
echo "✓ Test pages created at: $TEST_DIR"

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

# Navigate to the test page
TEST_URL="file://$TEST_DIR/index.html"
echo "Navigating to: $TEST_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 '$TEST_URL'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Close any extra tabs to ensure we start with exactly one tab
echo "Closing extra tabs to start fresh..."
for i in {1..5}; do
    TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "1")
    if [ "$TAB_COUNT" -gt 1 ]; then
        echo "Found $TAB_COUNT tabs, closing extras..."
        su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+w" || true
        sleep 0.5
    else
        break
    fi
done

# Navigate back to test page if we accidentally closed it
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 '$TEST_URL'" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 2

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    INITIAL_TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "unknown")
    echo "✓ Starting with $INITIAL_TAB_COUNT tab(s)"
    
    # Display active tab URL for verification
    ACTIVE_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""')
    echo "✓ Active URL: $ACTIVE_URL"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome should be displaying the Link Opening Test Page"
echo ""
echo "Agent should now:"
echo "  1. Ctrl+Click on 'Article A' (opens in background tab)"
echo "  2. Shift+Click on 'Article B' (opens in new window)"
echo "  3. Middle-Click on 'Article C' (opens in background tab)"
echo "  4. Right-click on 'Article D' → 'Open link in new tab'"
echo "  5. Right-click on 'Article E' → 'Open link in new window'"
echo ""
echo "Expected result: 3 windows total with 6 tabs (1 original + 5 articles)"