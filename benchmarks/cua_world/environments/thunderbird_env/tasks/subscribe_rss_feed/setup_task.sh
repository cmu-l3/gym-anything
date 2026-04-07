#!/bin/bash
echo "=== Setting up RSS Feed Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Create realistic real-world RSS Data File
echo "Preparing local RSS feed data..."
mkdir -p /tmp/rss_data
cat > /tmp/rss_data/market_news.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8" ?>
<rss version="2.0">
<channel>
  <title>Market Intelligence News</title>
  <link>http://localhost:8080/</link>
  <description>Internal Market Updates</description>
  <item>
    <title>Global Equities Rebound Strongly</title>
    <link>http://localhost:8080/news/1</link>
    <description>Markets saw a significant uptick today following revised inflation data.</description>
    <pubDate>Mon, 01 Jan 2024 09:00:00 GMT</pubDate>
  </item>
  <item>
    <title>Tech Sector Leads Q3 Earnings</title>
    <link>http://localhost:8080/news/2</link>
    <description>Major technology firms reported better-than-expected earnings for the third quarter.</description>
    <pubDate>Mon, 01 Jan 2024 10:30:00 GMT</pubDate>
  </item>
  <item>
    <title>Central Bank Maintains Interest Rates</title>
    <link>http://localhost:8080/news/3</link>
    <description>The central bank voted to keep benchmark interest rates steady for the consecutive month.</description>
    <pubDate>Mon, 01 Jan 2024 12:15:00 GMT</pubDate>
  </item>
</channel>
</rss>
EOF
chown -R ga:ga /tmp/rss_data

# 2. Start Python HTTP Server in the background to serve the feed
pkill -f "python3 -m http.server" 2>/dev/null || true
echo "Starting local RSS server on port 8080..."
su - ga -c "cd /tmp/rss_data && python3 -m http.server 8080 > /tmp/rss_server.log 2>&1 &"
sleep 2

# 3. Start Thunderbird Application
if ! pgrep -f "thunderbird" > /dev/null; then
    su - ga -c "DISPLAY=:1 thunderbird &"
fi

# 4. Wait for the main window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "thunderbird"; then
        echo "Thunderbird window detected"
        break
    fi
    sleep 1
done

# 5. Focus and Maximize Thunderbird
WID=$(DISPLAY=:1 wmctrl -l | grep -i "thunderbird" | awk '{print $1}' | head -n 1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Settle UI and take initial evidence screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="