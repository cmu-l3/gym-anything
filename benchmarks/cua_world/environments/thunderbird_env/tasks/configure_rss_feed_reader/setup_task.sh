#!/bin/bash
echo "=== Setting up RSS Feed Reader task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Create the internal RSS feed server directory
FEED_DIR="/home/ga/feed_server"
mkdir -p "$FEED_DIR"

# Generate realistic corporate RSS feed XML
cat > "$FEED_DIR/industry_news.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8" ?>
<rss version="2.0">
<channel>
  <title>Industry News &amp; Market Intelligence</title>
  <link>http://localhost:8080/</link>
  <description>Internal corporate news feed for market analysts.</description>
  <lastBuildDate>Mon, 09 Mar 2026 09:00:00 GMT</lastBuildDate>
  <item>
    <title>Globex Corp Announces Q3 Results</title>
    <link>http://localhost:8080/news/globex-q3</link>
    <description>Globex Corporation reported a 15% increase in revenue for the third quarter, driven by strong international sales in the logistics sector. Operating margins improved by 200 basis points.</description>
    <pubDate>Mon, 09 Mar 2026 08:30:00 GMT</pubDate>
  </item>
  <item>
    <title>Acme Corp Acquisition Finalized</title>
    <link>http://localhost:8080/news/acme-acquisition</link>
    <description>The long-awaited acquisition of Acme Corp has been finalized by the regulatory board. Integration of their primary manufacturing assets will begin next month.</description>
    <pubDate>Fri, 06 Mar 2026 14:15:00 GMT</pubDate>
  </item>
  <item>
    <title>TechNova Unveils New Cloud Infrastructure</title>
    <link>http://localhost:8080/news/technova-cloud</link>
    <description>TechNova's annual developer conference kicked off with the announcement of a distributed, edge-computing infrastructure designed to reduce latency for high-frequency trading platforms.</description>
    <pubDate>Thu, 05 Mar 2026 10:00:00 GMT</pubDate>
  </item>
</channel>
</rss>
EOF

chown -R ga:ga "$FEED_DIR"

# Start the Python HTTP server in the background
echo "Starting internal feed server on port 8080..."
su - ga -c "cd $FEED_DIR && python3 -m http.server 8080 > /tmp/feed_server.log 2>&1 &"
sleep 2

# Ensure Thunderbird is running
if ! pgrep -f "thunderbird" > /dev/null; then
    echo "Starting Thunderbird..."
    su - ga -c "DISPLAY=:1 thunderbird -profile /home/ga/.thunderbird/default-release &"
    sleep 8
fi

# Focus and maximize Thunderbird
WID=$(su - ga -c "DISPLAY=:1 xdotool search --name 'Mozilla Thunderbird' 2>/dev/null" | head -1)
if [ -n "$WID" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -i -r '$WID' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    su - ga -c "DISPLAY=:1 wmctrl -i -a '$WID'" 2>/dev/null || true
fi

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="