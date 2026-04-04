#!/bin/bash
set -e

echo "=== Setting up Chrome Custom Search Engine Task ==="

# Ensure Chrome is running (it should be from environment setup)
# Check if Chrome process exists
if ! pgrep -f "chrome" > /dev/null; then
    echo "Chrome not running, launching..."
    export DISPLAY=:1
    google-chrome-stable \
        --remote-debugging-port=1337 \
        --user-data-dir=/home/ga/.config/google-chrome \
        --no-first-run \
        --no-default-browser-check \
        --disable-popup-blocking \
        --start-maximized \
        > /tmp/chrome_ga.log 2>&1 &
    
    # Wait for Chrome to be ready
    sleep 3
fi

# Verify Chrome is accessible
for i in {1..10}; do
    if curl -s http://localhost:1337/json > /dev/null 2>&1; then
        echo "Chrome is ready for custom search engine configuration"
        break
    fi
    if [ $i -eq 10 ]; then
        echo "Warning: Chrome may not be fully ready, but proceeding..."
    fi
    sleep 2
done

# Optional: Open Chrome settings to help the agent
# Uncomment if you want to give the agent a head start
# xdotool key ctrl+l
# sleep 0.5
# xdotool type "chrome://settings"
# xdotool key Return
# sleep 2

echo "Setup complete. Agent can now add custom search engine."
exit 0