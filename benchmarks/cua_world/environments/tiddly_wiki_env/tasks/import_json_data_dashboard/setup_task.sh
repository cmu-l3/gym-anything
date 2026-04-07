#!/bin/bash
echo "=== Setting up import_json_data_dashboard task ==="

source /workspace/scripts/task_utils.sh

# Create the JSON dataset to be imported
cat > /home/ga/usgs_historical_earthquakes.json << 'EOF'
[
  {"title": "1960 Valdivia earthquake", "tags": "Earthquake", "magnitude": "9.5", "text": "Location: Chile. Date: May 22, 1960."},
  {"title": "1964 Alaska earthquake", "tags": "Earthquake", "magnitude": "9.2", "text": "Location: Alaska, USA. Date: March 27, 1964."},
  {"title": "2004 Indian Ocean earthquake", "tags": "Earthquake", "magnitude": "9.1", "text": "Location: Indian Ocean, Sumatra, Indonesia. Date: December 26, 2004."},
  {"title": "2011 Tohoku earthquake", "tags": "Earthquake", "magnitude": "9.1", "text": "Location: Japan. Date: March 11, 2011."},
  {"title": "1952 Kamchatka earthquake", "tags": "Earthquake", "magnitude": "9.0", "text": "Location: Russia. Date: November 4, 1952."},
  {"title": "2010 Chile earthquake", "tags": "Earthquake", "magnitude": "8.8", "text": "Location: Chile. Date: February 27, 2010."},
  {"title": "1906 Ecuador-Colombia earthquake", "tags": "Earthquake", "magnitude": "8.8", "text": "Location: Ecuador/Colombia. Date: January 31, 1906."},
  {"title": "1965 Rat Islands earthquake", "tags": "Earthquake", "magnitude": "8.7", "text": "Location: Alaska, USA. Date: February 4, 1965."},
  {"title": "1950 Assam-Tibet earthquake", "tags": "Earthquake", "magnitude": "8.6", "text": "Location: India/China. Date: August 15, 1950."},
  {"title": "2012 Indian Ocean earthquake", "tags": "Earthquake", "magnitude": "8.6", "text": "Location: Indian Ocean, Sumatra. Date: April 11, 2012."}
]
EOF
chown ga:ga /home/ga/usgs_historical_earthquakes.json

# Record initial tiddler count
INITIAL_COUNT=$(count_user_tiddlers)
echo "$INITIAL_COUNT" > /tmp/initial_tiddler_count
echo "Initial tiddler count: $INITIAL_COUNT"

# Verify TiddlyWiki is running
if curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "TiddlyWiki server is running"
else
    echo "WARNING: TiddlyWiki server not accessible"
fi

# Ensure Firefox is focused on TiddlyWiki
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/import_initial.png

echo "=== Task setup complete ==="