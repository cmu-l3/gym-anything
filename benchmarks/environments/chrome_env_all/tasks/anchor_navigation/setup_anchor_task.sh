#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Anchor Navigation Task Setup ==="
echo "Task: Navigate within documentation page using anchor links"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Wait for environment to be ready
sleep 2

# Create a sample documentation HTML page with anchor links
echo "Creating sample documentation page with table of contents..."
DOC_DIR="/home/ga/Documents"
mkdir -p "$DOC_DIR"

cat > "$DOC_DIR/api_documentation.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>API Documentation - Chrome Navigation Library</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif;
            line-height: 1.6;
            margin: 0;
            padding: 0;
            background-color: #f5f5f5;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
        }
        header {
            background: #2c3e50;
            color: white;
            padding: 30px;
            text-align: center;
        }
        nav {
            background: #ecf0f1;
            padding: 20px;
            border-bottom: 3px solid #3498db;
            position: sticky;
            top: 0;
            z-index: 100;
        }
        nav h2 {
            margin-top: 0;
            color: #2c3e50;
        }
        nav ul {
            list-style: none;
            padding: 0;
        }
        nav li {
            margin: 10px 0;
        }
        nav a {
            color: #3498db;
            text-decoration: none;
            font-size: 16px;
            font-weight: 500;
            padding: 5px 10px;
            display: inline-block;
            transition: all 0.3s;
        }
        nav a:hover {
            background: #3498db;
            color: white;
            border-radius: 4px;
        }
        .content {
            padding: 40px;
        }
        section {
            margin-bottom: 60px;
            padding-top: 20px;
            min-height: 500px;
        }
        section h2 {
            color: #2c3e50;
            border-bottom: 3px solid #3498db;
            padding-bottom: 10px;
            margin-bottom: 20px;
        }
        section h3 {
            color: #34495e;
            margin-top: 30px;
        }
        .code-block {
            background: #f8f8f8;
            border-left: 4px solid #3498db;
            padding: 15px;
            margin: 15px 0;
            font-family: 'Courier New', monospace;
            overflow-x: auto;
        }
        .note {
            background: #fff3cd;
            border-left: 4px solid #ffc107;
            padding: 15px;
            margin: 15px 0;
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>Chrome Navigation Library</h1>
            <p>Comprehensive API Documentation v2.1</p>
        </header>
        
        <nav>
            <h2>Table of Contents</h2>
            <ul>
                <li><a href="#getting-started">Getting Started</a></li>
                <li><a href="#api-reference">API Reference</a></li>
                <li><a href="#examples">Examples</a></li>
                <li><a href="#advanced-usage">Advanced Usage</a></li>
                <li><a href="#troubleshooting">Troubleshooting</a></li>
            </ul>
        </nav>
        
        <div class="content">
            <section id="getting-started">
                <h2>Getting Started</h2>
                <p>Welcome to the Chrome Navigation Library documentation! This library provides a comprehensive set of tools for programmatic browser navigation and interaction.</p>
                
                <h3>Installation</h3>
                <p>Install the library using npm:</p>
                <div class="code-block">
                    npm install chrome-navigation-lib
                </div>
                
                <h3>Quick Start</h3>
                <p>Here's a simple example to get you started:</p>
                <div class="code-block">
                    const ChromeNav = require('chrome-navigation-lib');<br>
                    const browser = new ChromeNav();<br>
                    await browser.navigate('https://example.com');
                </div>
                
                <h3>Prerequisites</h3>
                <p>Before using this library, ensure you have:</p>
                <ul>
                    <li>Node.js version 14 or higher</li>
                    <li>Chrome or Chromium browser installed</li>
                    <li>Basic understanding of async/await patterns</li>
                </ul>
                
                <div class="note">
                    <strong>Note:</strong> This library requires Chrome DevTools Protocol (CDP) access. Make sure to launch Chrome with the --remote-debugging-port flag.
                </div>
            </section>
            
            <section id="api-reference">
                <h2>API Reference</h2>
                <p>Complete reference documentation for all available methods and properties.</p>
                
                <h3>ChromeNav Class</h3>
                <p>The main class for browser navigation operations.</p>
                
                <h4>Methods</h4>
                
                <div class="code-block">
                    <strong>navigate(url: string): Promise&lt;void&gt;</strong><br>
                    Navigates to the specified URL.<br><br>
                    
                    <strong>click(selector: string): Promise&lt;void&gt;</strong><br>
                    Clicks on an element matching the selector.<br><br>
                    
                    <strong>type(selector: string, text: string): Promise&lt;void&gt;</strong><br>
                    Types text into an input field.<br><br>
                    
                    <strong>waitForNavigation(): Promise&lt;void&gt;</strong><br>
                    Waits for navigation to complete.<br><br>
                    
                    <strong>getUrl(): Promise&lt;string&gt;</strong><br>
                    Returns the current page URL.<br><br>
                    
                    <strong>screenshot(path: string): Promise&lt;void&gt;</strong><br>
                    Takes a screenshot of the current page.
                </div>
                
                <h3>Configuration Options</h3>
                <p>Available configuration options when initializing ChromeNav:</p>
                <ul>
                    <li><strong>headless:</strong> Run browser in headless mode (default: false)</li>
                    <li><strong>debugPort:</strong> CDP port number (default: 9222)</li>
                    <li><strong>timeout:</strong> Default timeout in milliseconds (default: 30000)</li>
                    <li><strong>viewport:</strong> Default viewport dimensions</li>
                </ul>
            </section>
            
            <section id="examples">
                <h2>Examples</h2>
                <p>Practical examples demonstrating common use cases.</p>
                
                <h3>Example 1: Basic Navigation</h3>
                <div class="code-block">
                    const browser = new ChromeNav();<br>
                    await browser.navigate('https://github.com');<br>
                    console.log('Current URL:', await browser.getUrl());
                </div>
                
                <h3>Example 2: Form Submission</h3>
                <div class="code-block">
                    await browser.navigate('https://example.com/login');<br>
                    await browser.type('#username', 'user@example.com');<br>
                    await browser.type('#password', 'secretpassword');<br>
                    await browser.click('#login-button');<br>
                    await browser.waitForNavigation();
                </div>
                
                <h3>Example 3: Screenshot Capture</h3>
                <div class="code-block">
                    await browser.navigate('https://example.com');<br>
                    await browser.screenshot('./screenshots/homepage.png');<br>
                    console.log('Screenshot saved!');
                </div>
                
                <h3>Example 4: Multi-Tab Management</h3>
                <div class="code-block">
                    const tab1 = await browser.newTab();<br>
                    await tab1.navigate('https://docs.example.com');<br><br>
                    
                    const tab2 = await browser.newTab();<br>
                    await tab2.navigate('https://api.example.com');<br><br>
                    
                    await browser.switchToTab(tab1);
                </div>
                
                <div class="note">
                    <strong>Tip:</strong> Always use try-catch blocks when working with navigation operations to handle potential errors gracefully.
                </div>
            </section>
            
            <section id="advanced-usage">
                <h2>Advanced Usage</h2>
                <p>Advanced features and techniques for power users.</p>
                
                <h3>Custom CDP Commands</h3>
                <p>Send raw Chrome DevTools Protocol commands:</p>
                <div class="code-block">
                    const result = await browser.sendCDPCommand('Page.navigate', {<br>
                    &nbsp;&nbsp;url: 'https://example.com'<br>
                    });
                </div>
                
                <h3>Network Interception</h3>
                <p>Intercept and modify network requests:</p>
                <div class="code-block">
                    await browser.interceptRequests((request) => {<br>
                    &nbsp;&nbsp;if (request.url.includes('analytics')) {<br>
                    &nbsp;&nbsp;&nbsp;&nbsp;request.abort();<br>
                    &nbsp;&nbsp;} else {<br>
                    &nbsp;&nbsp;&nbsp;&nbsp;request.continue();<br>
                    &nbsp;&nbsp;}<br>
                    });
                </div>
                
                <h3>Performance Monitoring</h3>
                <p>Track page performance metrics:</p>
                <div class="code-block">
                    const metrics = await browser.getPerformanceMetrics();<br>
                    console.log('Load time:', metrics.loadTime);<br>
                    console.log('DOM content loaded:', metrics.domContentLoaded);
                </div>
            </section>
            
            <section id="troubleshooting">
                <h2>Troubleshooting</h2>
                <p>Common issues and their solutions.</p>
                
                <h3>Chrome Won't Connect</h3>
                <p>If you're having trouble connecting to Chrome:</p>
                <ul>
                    <li>Verify Chrome is running with --remote-debugging-port flag</li>
                    <li>Check that the port isn't already in use</li>
                    <li>Ensure firewall isn't blocking the connection</li>
                </ul>
                
                <h3>Timeouts During Navigation</h3>
                <p>If navigation operations timeout:</p>
                <ul>
                    <li>Increase the default timeout value</li>
                    <li>Check network connectivity</li>
                    <li>Verify the target URL is accessible</li>
                </ul>
                
                <h3>Element Not Found Errors</h3>
                <p>When selectors don't match elements:</p>
                <ul>
                    <li>Use browser developer tools to verify selectors</li>
                    <li>Wait for elements to load before interacting</li>
                    <li>Consider using more specific selectors</li>
                </ul>
                
                <div class="note">
                    <strong>Still having issues?</strong> Check our GitHub issues page or join our community Discord for help.
                </div>
            </section>
        </div>
    </div>
</body>
</html>
EOF

chown ga:ga "$DOC_DIR/api_documentation.html"
echo "✓ Documentation page created at: $DOC_DIR/api_documentation.html"

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

# Navigate to the documentation page
DOC_URL="file:///home/ga/Documents/api_documentation.html"
echo "Navigating to: $DOC_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'file:///home/ga/Documents/api_documentation.html'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    # Get current URL to verify page loaded
    CURRENT_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""' || echo "")
    echo "Current URL: $CURRENT_URL"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Documentation page with table of contents is loaded"
echo "Agent should now:"
echo "  1. Click on 'Getting Started' anchor link in table of contents"
echo "  2. Click on 'API Reference' anchor link"
echo "  3. Click on 'Examples' anchor link"
echo "These clicks should navigate to different sections on the same page"