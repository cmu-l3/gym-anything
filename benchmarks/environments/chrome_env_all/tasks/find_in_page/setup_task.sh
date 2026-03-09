#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Find in Page Task Setup: find_in_page@1 ==="
echo "Task: Use Find in Page (Ctrl+F) to search for 'climate' and navigate through matches"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip imagemagick || true

# Install Python libraries for image processing (for verification)
pip3 install -q pillow numpy 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create a local HTML file with rich content for searching
echo "Creating content-rich HTML file for search task..."
CONTENT_DIR="/home/ga/Documents"
mkdir -p "$CONTENT_DIR"

cat > "$CONTENT_DIR/climate_article.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Climate Change Overview</title>
    <style>
        body {
            font-family: Georgia, serif;
            line-height: 1.8;
            margin: 40px;
            max-width: 900px;
            background-color: #ffffff;
            color: #202122;
        }
        h1 { color: #000000; font-size: 2em; margin-bottom: 20px; }
        h2 { color: #202122; font-size: 1.5em; margin-top: 30px; margin-bottom: 15px; }
        p { margin: 15px 0; text-align: justify; }
        .highlight-box { background-color: #f8f9fa; padding: 20px; margin: 20px 0; border-left: 4px solid #0645ad; }
    </style>
</head>
<body>
    <h1>Understanding Climate Change: A Comprehensive Overview</h1>
    
    <p>Climate change represents one of the most significant challenges facing humanity in the 21st century. The term climate refers to long-term weather patterns and averages in a particular region. When we discuss climate change, we're referring to significant, long-lasting changes in the statistical distribution of weather patterns over periods ranging from decades to millions of years.</p>

    <p>Scientific evidence overwhelmingly demonstrates that the Earth's climate is warming at an unprecedented rate. This warming of the climate system is unequivocal, with numerous indicators showing consistent trends across different measurement methods. The climate has always varied naturally throughout Earth's history, but current changes are occurring at a pace never before observed.</p>

    <h2>The Science Behind Climate Change</h2>
    
    <p>The primary driver of recent climate change is the increase in greenhouse gases in Earth's atmosphere. Human activities, particularly the burning of fossil fuels, have increased atmospheric concentrations of carbon dioxide and other greenhouse gases. These gases trap heat in the atmosphere, leading to what scientists call the greenhouse effect and resulting in global climate warming.</p>

    <p>Research into climate science has revealed that the Earth's climate operates as a complex system with many interconnected components. Ocean currents, atmospheric circulation patterns, ice sheets, and vegetation all interact to shape our planet's climate. Understanding these interactions is crucial for predicting future climate trends and developing appropriate response strategies.</p>

    <div class="highlight-box">
        <strong>Key Climate Facts:</strong>
        <ul>
            <li>Global average temperatures have risen approximately 1.1°C since pre-industrial times</li>
            <li>The rate of climate warming has accelerated in recent decades</li>
            <li>Ocean temperatures have increased, affecting marine climate conditions</li>
            <li>Arctic climate regions are warming faster than the global average</li>
            <li>Extreme climate events are becoming more frequent and intense</li>
        </ul>
    </div>

    <h2>Impacts on Global Climate Patterns</h2>
    
    <p>Climate change is already affecting weather patterns worldwide. Regions that once enjoyed predictable climate conditions now experience greater variability. Some areas face more intense droughts while others experience increased flooding. These shifts in regional climate create significant challenges for agriculture, water resources, and ecosystem stability.</p>

    <p>The changing climate is also affecting seasonal patterns. Spring arrives earlier in many regions, and autumn extends later into the year. These shifts in seasonal climate timing affect plant flowering times, animal migration patterns, and agricultural growing seasons. Such changes cascade through ecosystems, affecting species that have adapted to historical climate rhythms over thousands of years.</p>

    <h2>Climate Models and Future Projections</h2>
    
    <p>Scientists use sophisticated climate models to project future conditions under various scenarios. These models incorporate our understanding of physical climate processes and simulate how the climate system might respond to different levels of greenhouse gas emissions. While no model can predict the future with perfect accuracy, multiple independent climate models show consistent trends toward continued warming.</p>

    <p>Future climate projections suggest that without significant reductions in greenhouse gas emissions, global temperatures will continue to rise. The extent of future climate change depends largely on actions taken now to reduce emissions. Different emission scenarios produce different climate outcomes, highlighting the importance of policy decisions in shaping our climate future.</p>

    <h2>Adaptation and Mitigation Strategies</h2>
    
    <p>Addressing climate change requires both mitigation efforts to reduce greenhouse gas emissions and adaptation strategies to cope with unavoidable climate impacts. Mitigation involves transitioning to renewable energy sources, improving energy efficiency, and protecting natural climate regulators like forests and wetlands. These actions can help stabilize the climate system and limit future warming.</p>

    <p>Adaptation to climate change means adjusting human systems and practices to reduce vulnerability to climate impacts. This includes developing drought-resistant crops, building flood defenses, managing water resources more efficiently, and planning urban development with future climate conditions in mind. Communities worldwide are already implementing climate adaptation measures to protect lives and livelihoods.</p>

    <h2>The Role of International Climate Cooperation</h2>
    
    <p>Climate change is inherently a global challenge requiring international cooperation. No single nation can solve the climate crisis alone because greenhouse gases mix throughout the global atmosphere regardless of where they're emitted. International climate agreements like the Paris Agreement represent efforts to coordinate global action on reducing emissions and supporting vulnerable nations in adapting to climate impacts.</p>

    <p>Monitoring global climate trends requires sustained international collaboration in climate science. Networks of weather stations, satellites, ocean buoys, and research stations collect data that feeds into our understanding of how the climate is changing. This collaborative approach to climate observation ensures that scientists worldwide can access consistent, high-quality data for their research.</p>

    <h2>Individual Actions for Climate Awareness</h2>
    
    <p>While addressing climate change requires systemic changes at governmental and industrial levels, individual actions also matter. Understanding your personal climate footprint and making conscious choices about energy use, transportation, diet, and consumption patterns contributes to the broader effort. Education about climate science helps build public support for necessary policy changes.</p>

    <p>Staying informed about climate science and communicating climate information accurately helps counter misinformation. The climate challenge is complex, but the fundamental science is well-established. Supporting evidence-based climate policies and holding leaders accountable for climate action represents an important form of climate engagement that every citizen can practice.</p>

    <h2>Conclusion: Our Climate Future</h2>
    
    <p>The Earth's climate will continue to change in response to both past emissions already in the atmosphere and future emissions we've yet to release. The trajectory of future climate change remains partially within our control through the choices societies make today. Scientific understanding of climate processes continues to improve, providing better tools for predicting and responding to climate shifts.</p>

    <p>Addressing climate change represents one of the defining challenges of our era, but it's also an opportunity to build more sustainable, resilient, and equitable societies. By understanding climate science, supporting evidence-based policies, and adapting our practices to a changing climate, humanity can work toward a future where both people and nature can thrive despite the climate challenges ahead.</p>

</body>
</html>
EOF

chown ga:ga "$CONTENT_DIR/climate_article.html"
echo "✓ Climate article HTML created at: $CONTENT_DIR/climate_article.html"
echo "✓ The article contains 30+ instances of the word 'climate' for search testing"

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

# Navigate to the climate article
ARTICLE_URL="file:///home/ga/Documents/climate_article.html"
echo "Navigating to: $ARTICLE_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'file:///home/ga/Documents/climate_article.html'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Scroll to top to ensure consistent starting position
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Home" || true
sleep 0.5

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
echo "Chrome should be displaying the climate change article"
echo "Agent should now:"
echo "  1. Press Ctrl+F to open Find in Page"
echo "  2. Type 'climate' in the search box"
echo "  3. Observe matches found (30+ matches expected)"
echo "  4. Press Enter 2-3 times to navigate through matches"
echo "  5. Verify highlighting and match counter"