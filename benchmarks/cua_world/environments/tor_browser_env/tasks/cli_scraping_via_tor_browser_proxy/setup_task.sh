#!/bin/bash
echo "=== Setting up cli_scraping_via_tor_browser_proxy task ==="

# Record task start timestamp for anti-gaming checks
TASK_START_TIMESTAMP=$(date +%s)
echo "$TASK_START_TIMESTAMP" > /tmp/task_start_timestamp

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# Clean up any existing files to prevent gaming
rm -f /home/ga/Documents/tor_scraper.sh
rm -f /home/ga/Documents/tor_ip.json
rm -f /home/ga/Documents/ddg_onion.html

# Kill any running Tor Browser instances to ensure agent starts it
pkill -u ga -f "tor-browser" 2>/dev/null || true
pkill -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
pkill -u ga -f "torbrowser" 2>/dev/null || true

# Provide a small task info file on Desktop for reference
cat > /home/ga/Desktop/TASK_INFO.txt << 'EOF'
TASK: CLI Scraping via Tor Browser Proxy

1. Open Tor Browser (this starts the local proxy on port 9150).
2. Write a bash script at /home/ga/Documents/tor_scraper.sh.
3. The script must use `curl` to download:
   - https://check.torproject.org/api/ip -> /home/ga/Documents/tor_ip.json
   - https://duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion/ -> /home/ga/Documents/ddg_onion.html
4. You must route the curl requests through 127.0.0.1:9150 and use remote DNS resolution (e.g. -x socks5h:// or --socks5-hostname).
5. Run the script so the output files are generated.
EOF
chown ga:ga /home/ga/Desktop/TASK_INFO.txt

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="