#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Print Settings Configuration Task Setup ==="
echo "Task: Configure print dialog to save webpage as landscape PDF with minimal margins"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Install PDF processing libraries
pip3 install -q PyPDF2 pypdf pillow 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create a sample webpage with substantial content for printing
echo "Creating sample webpage for printing..."
CONTENT_DIR="/home/ga/Documents"
mkdir -p "$CONTENT_DIR"

cat > "$CONTENT_DIR/sample_article.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Web Technologies Overview</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            line-height: 1.8;
            margin: 30px;
            max-width: 1400px;
            background-color: #f9f9f9;
        }
        h1 {
            color: #2c3e50;
            border-bottom: 3px solid #3498db;
            padding-bottom: 10px;
            margin-top: 20px;
        }
        h2 {
            color: #34495e;
            margin-top: 25px;
            border-left: 4px solid #3498db;
            padding-left: 15px;
        }
        p {
            margin: 12px 0;
            text-align: justify;
        }
        .highlight-box {
            background-color: #e8f4f8;
            border-left: 5px solid #3498db;
            padding: 20px;
            margin: 20px 0;
        }
        .info-grid {
            display: grid;
            grid-template-columns: repeat(3, 1fr);
            gap: 20px;
            margin: 20px 0;
        }
        .info-card {
            background-color: white;
            padding: 15px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
    </style>
</head>
<body>
    <h1>Modern Web Technologies: A Comprehensive Overview</h1>
    
    <h2>Introduction to Web Development</h2>
    <p>Web development has evolved dramatically over the past three decades, transforming from simple static HTML pages to complex, interactive applications that rival desktop software in functionality and user experience. Modern web technologies enable developers to create responsive, accessible, and performant applications that work seamlessly across devices.</p>
    
    <p>The foundation of web development rests on three core technologies: HTML for structure, CSS for presentation, and JavaScript for behavior. Together, these technologies form the backbone of every website and web application on the internet today.</p>

    <h2>HTML5: Semantic Structure</h2>
    <p>HTML5 introduced numerous semantic elements that improve document structure and accessibility. Elements like &lt;header&gt;, &lt;nav&gt;, &lt;article&gt;, &lt;section&gt;, and &lt;footer&gt; provide meaningful context to content, making it easier for search engines and assistive technologies to understand page structure.</p>

    <div class="highlight-box">
        <h3>Key HTML5 Features</h3>
        <p><strong>Canvas and SVG:</strong> Enable graphics rendering directly in the browser without plugins.</p>
        <p><strong>Audio and Video:</strong> Native multimedia support without Flash or other third-party technologies.</p>
        <p><strong>Local Storage:</strong> Client-side data persistence for offline capabilities.</p>
        <p><strong>Geolocation API:</strong> Access to device location for location-aware applications.</p>
    </div>

    <h2>CSS3: Modern Styling and Layout</h2>
    <p>CSS3 revolutionized web design with powerful layout systems and visual effects. Flexbox and Grid provide robust solutions for responsive layouts, while transforms, transitions, and animations enable smooth, engaging user interfaces without JavaScript.</p>

    <p>Media queries allow developers to create responsive designs that adapt to different screen sizes, from mobile phones to large desktop monitors. This "mobile-first" approach has become standard practice in modern web development.</p>

    <div class="info-grid">
        <div class="info-card">
            <h3>Flexbox</h3>
            <p>One-dimensional layout system ideal for navigation bars, card layouts, and centering content.</p>
        </div>
        <div class="info-card">
            <h3>Grid</h3>
            <p>Two-dimensional layout system perfect for complex page layouts and magazine-style designs.</p>
        </div>
        <div class="info-card">
            <h3>Custom Properties</h3>
            <p>CSS variables enable theme customization and maintainable stylesheets.</p>
        </div>
    </div>

    <h2>JavaScript: The Language of the Web</h2>
    <p>JavaScript has grown from a simple scripting language into a powerful, versatile programming language capable of running on servers (Node.js), mobile devices, and IoT devices. Modern JavaScript (ES6+) includes features like arrow functions, destructuring, modules, promises, and async/await that make code more readable and maintainable.</p>

    <p>The JavaScript ecosystem is vast, with frameworks and libraries like React, Vue, Angular, and Svelte providing different approaches to building user interfaces. Each has its philosophy and strengths, catering to different project requirements and developer preferences.</p>

    <h2>Web APIs and Browser Capabilities</h2>
    <p>Modern browsers expose numerous Web APIs that enable rich functionality: Fetch API for network requests, Web Workers for background processing, Service Workers for offline capabilities, WebSockets for real-time communication, and WebRTC for peer-to-peer video and audio streaming.</p>

    <h2>Progressive Web Apps (PWAs)</h2>
    <p>Progressive Web Apps combine the best of web and native applications. They can be installed on devices, work offline, send push notifications, and provide app-like experiences while maintaining the web's inherent advantages: no app store approval process, instant updates, and a single codebase across platforms.</p>

    <h2>Performance Optimization</h2>
    <p>Web performance is crucial for user experience and SEO. Techniques include code splitting, lazy loading, image optimization, caching strategies, and minimizing render-blocking resources. Tools like Lighthouse, WebPageTest, and Chrome DevTools help developers measure and improve performance.</p>

    <h2>Accessibility and Inclusive Design</h2>
    <p>Web accessibility ensures that websites and applications are usable by everyone, including people with disabilities. Following WCAG guidelines, using semantic HTML, providing alternative text for images, ensuring keyboard navigation, and maintaining sufficient color contrast are fundamental practices.</p>

    <h2>Security Considerations</h2>
    <p>Web security is paramount in protecting user data and preventing attacks. Important concepts include HTTPS encryption, Content Security Policy (CSP), Cross-Origin Resource Sharing (CORS), protection against XSS and CSRF attacks, and secure authentication practices.</p>

    <h2>The Future of Web Development</h2>
    <p>Emerging technologies continue to shape the web's future: WebAssembly enables near-native performance for complex applications, WebGPU brings advanced graphics capabilities, and new CSS features like container queries and cascade layers provide more powerful styling tools. The web platform continues to evolve, expanding what's possible in the browser.</p>

    <h2>Conclusion</h2>
    <p>Web technologies have matured into a sophisticated platform capable of delivering high-quality experiences across all devices. As the web continues to evolve, developers must stay current with new standards, best practices, and tools while maintaining focus on performance, accessibility, and user experience. The future of the web is bright, with ongoing innovations promising even more powerful and accessible applications.</p>

</body>
</html>
EOF

chown ga:ga "$CONTENT_DIR/sample_article.html"
echo "✓ Sample webpage created at: $CONTENT_DIR/sample_article.html"

# Clear any existing PDFs in Downloads to avoid confusion
echo "Cleaning Downloads folder..."
rm -f /home/ga/Downloads/*.pdf 2>/dev/null || true
rm -f /home/ga/Downloads/webpage_print_landscape.pdf 2>/dev/null || true

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

# Navigate to the sample article
ARTICLE_URL="file:///home/ga/Documents/sample_article.html"
echo "Navigating to: $ARTICLE_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'file:///home/ga/Documents/sample_article.html'" || true
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

echo "=== Setup complete ==="
echo "Chrome should be displaying the sample article"
echo ""
echo "Agent should now:"
echo "  1. Press Ctrl+P to open print dialog"
echo "  2. Ensure destination is 'Save as PDF'"
echo "  3. Change Layout to 'Landscape'"
echo "  4. Change Margins to 'None' or 'Minimum'"
echo "  5. Ensure Scale is at 100% (or adjust if needed)"
echo "  6. Click Save and name file: webpage_print_landscape.pdf"
echo ""