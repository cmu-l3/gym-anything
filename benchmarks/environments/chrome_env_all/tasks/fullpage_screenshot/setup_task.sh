#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Full-Page Screenshot Task Setup ==="
echo "Task: Capture full-page screenshot using Chrome DevTools"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Install image processing libraries for verification
pip3 install -q Pillow numpy 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create a long-form webpage for screenshot testing
echo "Creating long-form test webpage..."
DOCS_DIR="/home/ga/Documents"
mkdir -p "$DOCS_DIR"

cat > "$DOCS_DIR/long_article_test.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Web Development Best Practices - Complete Guide</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            line-height: 1.8;
            margin: 0;
            padding: 40px 60px;
            max-width: 1000px;
            background: linear-gradient(to bottom, #f8f9fa 0%, #ffffff 100%);
        }
        h1 {
            color: #1a73e8;
            font-size: 2.5em;
            margin-top: 40px;
            margin-bottom: 20px;
            border-bottom: 3px solid #1a73e8;
            padding-bottom: 10px;
        }
        h2 {
            color: #34495e;
            font-size: 1.8em;
            margin-top: 35px;
            margin-bottom: 15px;
        }
        h3 {
            color: #5a6c7d;
            font-size: 1.4em;
            margin-top: 25px;
            margin-bottom: 10px;
        }
        p {
            margin: 15px 0;
            text-align: justify;
            color: #2c3e50;
        }
        .highlight-box {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 25px;
            margin: 25px 0;
            border-radius: 8px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        .highlight-box h3 {
            color: white;
            margin-top: 0;
        }
        .code-block {
            background: #282c34;
            color: #61dafb;
            padding: 20px;
            margin: 20px 0;
            border-radius: 6px;
            font-family: 'Courier New', monospace;
            overflow-x: auto;
        }
        .info-box {
            background: #e3f2fd;
            border-left: 5px solid #2196f3;
            padding: 20px;
            margin: 20px 0;
        }
        ul, ol {
            margin: 15px 0;
            padding-left: 30px;
        }
        li {
            margin: 8px 0;
        }
    </style>
</head>
<body>
    <h1>🌐 Complete Guide to Modern Web Development Best Practices</h1>
    
    <h2>1. Introduction to Web Development Excellence</h2>
    <p>Web development has evolved dramatically over the past decade, transforming from simple static pages to complex, interactive applications that power our digital world. Modern web development requires mastery of multiple disciplines including frontend design, backend architecture, database management, security protocols, and performance optimization.</p>
    
    <p>This comprehensive guide explores the essential best practices that every web developer should know in 2024. Whether you're building a simple blog or a complex enterprise application, these principles will help you create robust, scalable, and maintainable web solutions.</p>

    <div class="highlight-box">
        <h3>🎯 Key Learning Objectives</h3>
        <ul>
            <li>Master fundamental web development principles</li>
            <li>Implement responsive and accessible design patterns</li>
            <li>Optimize performance and security</li>
            <li>Understand modern development workflows</li>
            <li>Apply industry-standard best practices</li>
        </ul>
    </div>

    <h2>2. HTML5: Semantic Markup and Structure</h2>
    <p>HTML5 introduced semantic elements that provide meaning to web content, improving accessibility and SEO. Instead of using generic div elements everywhere, semantic HTML uses descriptive tags like header, nav, main, article, section, aside, and footer.</p>

    <h3>2.1 The Power of Semantic Elements</h3>
    <p>Semantic HTML elements clearly describe their meaning to both browsers and developers. For example, a nav element indicates navigation links, while an article element represents independent, self-contained content. This semantic structure helps screen readers interpret content correctly and assists search engines in understanding page hierarchy.</p>

    <div class="code-block">
&lt;header&gt;
    &lt;nav&gt;
        &lt;ul&gt;
            &lt;li&gt;&lt;a href="#home"&gt;Home&lt;/a&gt;&lt;/li&gt;
            &lt;li&gt;&lt;a href="#about"&gt;About&lt;/a&gt;&lt;/li&gt;
        &lt;/ul&gt;
    &lt;/nav&gt;
&lt;/header&gt;
    </div>

    <h3>2.2 Document Structure Best Practices</h3>
    <p>Every HTML document should follow a clear hierarchy with appropriate heading levels (h1 through h6). The h1 element should be used once per page for the main title, followed by h2 for major sections, h3 for subsections, and so on. This logical structure benefits both accessibility and SEO.</p>

    <p>Additionally, always include proper meta tags in the head section, including charset declaration, viewport settings for responsive design, and descriptive meta descriptions for search engines. These foundational elements ensure your webpage renders correctly across all devices and platforms.</p>

    <h2>3. CSS3: Modern Styling Techniques</h2>
    <p>CSS3 revolutionized web design with powerful features like flexbox, grid layout, animations, transitions, and custom properties (CSS variables). These tools enable developers to create complex, responsive layouts without relying on JavaScript or external frameworks.</p>

    <h3>3.1 Flexbox for One-Dimensional Layouts</h3>
    <p>Flexbox excels at distributing space and aligning items within a container along a single axis (row or column). It simplifies many layout challenges that were previously difficult with floats or positioning. Common use cases include navigation menus, card layouts, and vertically centering content.</p>

    <div class="info-box">
        <strong>💡 Pro Tip:</strong> Use flexbox for components and UI elements where items need to flow in a single direction. For two-dimensional layouts with both rows and columns, CSS Grid is typically the better choice.
    </div>

    <h3>3.2 CSS Grid for Complex Layouts</h3>
    <p>CSS Grid provides a powerful two-dimensional layout system, allowing you to control both rows and columns simultaneously. Grid is perfect for page-level layouts, image galleries, and any design requiring precise alignment in multiple directions. The combination of flexbox for components and grid for overall layout structure represents current best practice.</p>

    <h3>3.3 Responsive Design Principles</h3>
    <p>Responsive web design ensures your site looks and functions well on devices of all sizes, from smartphones to large desktop monitors. This is achieved through flexible grids, fluid images, and media queries that apply different styles based on screen width, resolution, or device capabilities.</p>

    <p>Mobile-first design has become the standard approach: start with styles for small screens and progressively enhance for larger viewports. This methodology ensures faster loading on mobile devices and forces designers to prioritize content and functionality.</p>

    <h2>4. JavaScript: Modern ES6+ Features</h2>
    <p>JavaScript has evolved significantly with ECMAScript 6 (ES6) and subsequent versions introducing features that make code more readable, maintainable, and powerful. Understanding these modern features is essential for contemporary web development.</p>

    <h3>4.1 Arrow Functions and Lexical This</h3>
    <p>Arrow functions provide a concise syntax for function expressions and lexically bind the 'this' value, solving common issues with context binding in callbacks. This feature alone has eliminated countless bugs related to function context in event handlers and asynchronous operations.</p>

    <h3>4.2 Promises and Async/Await</h3>
    <p>Asynchronous programming is fundamental to web development, handling operations like API calls, file reading, and timers. Promises provide a cleaner alternative to callback hell, while async/await syntax makes asynchronous code look and behave more like synchronous code, improving readability dramatically.</p>

    <div class="code-block">
async function fetchUserData(userId) {
    try {
        const response = await fetch(`/api/users/${userId}`);
        const data = await response.json();
        return data;
    } catch (error) {
        console.error('Error fetching user:', error);
    }
}
    </div>

    <h3>4.3 Modules and Code Organization</h3>
    <p>ES6 modules allow you to organize code into reusable pieces with explicit imports and exports. This modular approach promotes code reusability, maintainability, and enables tree-shaking in build tools to eliminate unused code from production bundles.</p>

    <h2>5. Performance Optimization Strategies</h2>
    <p>Website performance directly impacts user experience, conversion rates, and search engine rankings. A fast-loading site keeps users engaged, while a slow site leads to abandonment and lost opportunities.</p>

    <h3>5.1 Image Optimization</h3>
    <p>Images typically account for the majority of page weight. Optimize images by choosing appropriate formats (WebP for photos, SVG for logos and icons), compressing files without visible quality loss, and implementing lazy loading for images below the fold. The HTML loading="lazy" attribute provides native lazy loading with minimal effort.</p>

    <h3>5.2 Code Splitting and Lazy Loading</h3>
    <p>Don't force users to download code they might never use. Code splitting breaks your JavaScript into smaller chunks loaded on demand. Modern frameworks like React, Vue, and Angular support dynamic imports that make implementing code splitting straightforward.</p>

    <h3>5.3 Caching Strategies</h3>
    <p>Implement appropriate caching headers to reduce server requests for returning visitors. Browser caching, CDN caching, and service workers for offline functionality all contribute to faster perceived and actual load times. Consider using a service worker with Workbox for sophisticated caching strategies.</p>

    <div class="highlight-box">
        <h3>⚡ Performance Checklist</h3>
        <ul>
            <li>Minify and compress all assets (HTML, CSS, JavaScript)</li>
            <li>Enable gzip or Brotli compression on server</li>
            <li>Use a Content Delivery Network (CDN)</li>
            <li>Implement lazy loading for images and videos</li>
            <li>Reduce third-party script impact</li>
            <li>Optimize critical rendering path</li>
        </ul>
    </div>

    <h2>6. Web Accessibility (a11y) Fundamentals</h2>
    <p>Web accessibility ensures that people with disabilities can perceive, understand, navigate, and interact with websites. This isn't just good ethics—in many jurisdictions, it's a legal requirement. Moreover, accessible websites often provide better user experiences for everyone.</p>

    <h3>6.1 ARIA Attributes and Roles</h3>
    <p>ARIA (Accessible Rich Internet Applications) attributes provide additional semantic information to assistive technologies. However, the first rule of ARIA is to avoid using it when native HTML elements provide the needed semantics. Only add ARIA when HTML alone cannot convey the interactive behavior or state.</p>

    <h3>6.2 Keyboard Navigation</h3>
    <p>Ensure all interactive elements are keyboard accessible. Users should be able to tab through all controls, activate buttons with Enter or Space, and navigate menus with arrow keys. Test your site by unplugging your mouse and using only the keyboard—this exercise often reveals accessibility issues.</p>

    <h3>6.3 Color Contrast and Visual Design</h3>
    <p>Maintain sufficient color contrast between text and background (WCAG requires at least 4.5:1 for normal text). Don't rely solely on color to convey information; use icons, labels, or patterns as well. Many users have color vision deficiencies, and good contrast benefits everyone, especially in bright environments.</p>

    <h2>7. Security Best Practices</h2>
    <p>Web security is not optional. Every website faces potential threats from malicious actors seeking to steal data, compromise systems, or disrupt services. Implementing security best practices protects both your users and your organization.</p>

    <h3>7.1 Input Validation and Sanitization</h3>
    <p>Never trust user input. Validate all data on both client and server sides. Sanitize input to prevent injection attacks like SQL injection and cross-site scripting (XSS). Use parameterized queries or ORM frameworks that handle escaping automatically. Encode output appropriately for the context (HTML, JavaScript, URL, etc.).</p>

    <h3>7.2 Authentication and Authorization</h3>
    <p>Implement secure authentication mechanisms using industry-standard protocols like OAuth 2.0 or OpenID Connect. Store passwords using strong hashing algorithms like bcrypt or Argon2—never store plain text passwords. Implement proper session management with secure, HttpOnly cookies and appropriate timeouts.</p>

    <h3>7.3 HTTPS and Content Security</h3>
    <p>Always use HTTPS to encrypt data in transit. Obtain SSL/TLS certificates from trusted authorities (Let's Encrypt provides free certificates). Implement Content Security Policy (CSP) headers to prevent XSS attacks by controlling which resources can be loaded. Regular security audits and dependency updates are essential for maintaining security.</p>

    <div class="info-box">
        <strong>🔒 Security Essentials:</strong> Keep all dependencies updated, use environment variables for sensitive data, implement rate limiting to prevent abuse, enable CORS appropriately, and never expose sensitive information in error messages or source code.
    </div>

    <h2>8. Version Control with Git</h2>
    <p>Git has become the universal standard for version control in software development. Mastering Git workflows enables effective collaboration, code history tracking, and the ability to experiment without fear of breaking production code.</p>

    <h3>8.1 Branch Strategy</h3>
    <p>Adopt a branching strategy that fits your team size and deployment frequency. GitFlow works well for projects with scheduled releases, while GitHub Flow suits continuous deployment environments. Feature branches isolate new development, keeping the main branch stable and deployable at all times.</p>

    <h3>8.2 Commit Best Practices</h3>
    <p>Write clear, descriptive commit messages that explain what changed and why. Follow conventional commit format when possible (feat:, fix:, docs:, etc.). Make small, focused commits that change one thing at a time—this makes code review easier and simplifies debugging when issues arise.</p>

    <h2>9. Testing and Quality Assurance</h2>
    <p>Testing is not an afterthought but an integral part of development. Automated tests catch bugs early, facilitate refactoring, serve as documentation, and give developers confidence to make changes without breaking existing functionality.</p>

    <h3>9.1 Unit Testing</h3>
    <p>Unit tests verify individual functions or components in isolation. They're fast to run and easy to write, forming the foundation of your test suite. Use frameworks like Jest, Mocha, or Jasmine for JavaScript testing. Aim for high code coverage, but focus on testing behavior rather than implementation details.</p>

    <h3>9.2 Integration and End-to-End Testing</h3>
    <p>Integration tests verify that different parts of your system work together correctly. End-to-end tests simulate real user scenarios, testing the entire application stack. Tools like Cypress, Playwright, and Selenium enable automated browser testing that catches issues unit tests might miss.</p>

    <h2>10. Continuous Integration and Deployment</h2>
    <p>CI/CD pipelines automate the process of testing and deploying code, reducing human error and enabling frequent, reliable releases. Every commit triggers automated tests, and passing changes can be automatically deployed to production.</p>

    <h3>10.1 CI/CD Pipeline Configuration</h3>
    <p>Set up automated builds that run tests, perform linting, check code coverage, and verify security vulnerabilities. Popular CI/CD platforms include GitHub Actions, GitLab CI, Jenkins, and CircleCI. Successful CI/CD implementation requires comprehensive test coverage and fast feedback loops.</p>

    <h2>11. Documentation and Code Comments</h2>
    <p>Good documentation saves countless hours for future developers (including your future self). Document the why, not just the what. Code should be self-explanatory through clear naming and structure; comments should explain complex logic, gotchas, or business requirements that aren't obvious from the code alone.</p>

    <h2>12. Conclusion and Continuous Learning</h2>
    <p>Web development is a constantly evolving field. Technologies, frameworks, and best practices change rapidly. Stay current by following industry blogs, attending conferences, participating in online communities, and regularly reviewing your code and practices.</p>

    <p>The principles outlined in this guide provide a solid foundation, but remember that best practices should adapt to your specific project requirements, team dynamics, and user needs. Always question assumptions, measure results, and iterate based on real-world data and feedback.</p>

    <div class="highlight-box">
        <h3>🎓 Next Steps</h3>
        <p>Continue your learning journey by exploring advanced topics like Progressive Web Apps (PWAs), WebAssembly, serverless architectures, and micro-frontend patterns. Build real projects, contribute to open source, and mentor others—teaching is one of the best ways to deepen your own understanding.</p>
    </div>

    <p style="margin-top: 60px; padding: 30px; background: #34495e; color: white; border-radius: 8px; text-align: center;">
        <strong>Remember:</strong> Great web development combines technical excellence with user empathy. Build with purpose, test thoroughly, deploy confidently, and always prioritize the user experience.
    </p>

</body>
</html>
EOF

chown ga:ga "$DOCS_DIR/long_article_test.html"
echo "✓ Long-form test webpage created at: $DOCS_DIR/long_article_test.html"

# Clear any existing screenshots from Downloads folder to avoid confusion
echo "Cleaning up any existing screenshots in Downloads..."
rm -f /home/ga/Downloads/*.png 2>/dev/null || true
rm -f /home/ga/Downloads/screenshot*.png 2>/dev/null || true

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

# Navigate to the long article
ARTICLE_URL="file:///home/ga/Documents/long_article_test.html"
echo "Navigating to: $ARTICLE_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 '$ARTICLE_URL'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Scroll down briefly to ensure page has fully rendered
echo "Ensuring page is fully loaded..."
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Page_Down" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Home" || true
sleep 1

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    ACTIVE_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '.[0].url // "unknown"')
    echo "✓ Active URL: $ACTIVE_URL"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome should be displaying the long-form article"
echo "Agent should now:"
echo "  1. Press F12 or Ctrl+Shift+I to open DevTools"
echo "  2. Press Ctrl+Shift+P to open Command Menu"
echo "  3. Type 'screenshot' and select 'Capture full size screenshot'"
echo "  4. Screenshot will be automatically downloaded to Downloads folder"