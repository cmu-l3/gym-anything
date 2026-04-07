#!/bin/bash
echo "=== Setting up tor_storage_api_isolation_audit task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Ensure directories exist and are clean
rm -rf /home/ga/web_audit
mkdir -p /home/ga/web_audit
chown -R ga:ga /home/ga/web_audit

mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/server.log
rm -f /home/ga/Documents/initial_audit.txt
rm -f /home/ga/Documents/restart_audit.txt
chown -R ga:ga /home/ga/Documents

# Kill any existing Tor Browser instances for a clean state
echo "Killing any existing Tor Browser instances..."
pkill -u ga -f "tor-browser" 2>/dev/null || true
pkill -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
pkill -u ga -f "torbrowser" 2>/dev/null || true
sleep 2
pkill -9 -u ga -f "tor-browser" 2>/dev/null || true
pkill -9 -u ga -f "firefox.*TorBrowser" 2>/dev/null || true

# Kill any existing python http servers to free port 8080
pkill -f "python3 -m http.server" 2>/dev/null || true
fuser -k 8080/tcp 2>/dev/null || true
sleep 1

# Provide a helpful task instructions file on the Desktop
cat > /home/ga/Desktop/TASK_INSTRUCTIONS.txt << 'EOF'
Tor Storage API Isolation Audit

Your task is to test how Tor Browser isolates LocalStorage and disables Service Workers to protect user privacy.
Please refer to your primary task instructions for the exact file paths and steps to follow.

You will need to:
1. Write the test suite (index.html)
2. Run the python server
3. Test in Tor Browser and write initial_audit.txt
4. Restart Tor Browser, test again, and write restart_audit.txt
EOF
chown ga:ga /home/ga/Desktop/TASK_INSTRUCTIONS.txt

# Start Tor Browser in the background to save the agent some time
TOR_BROWSER_DIR=""
for candidate in \
    "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser" \
    "/home/ga/.local/share/torbrowser/tbb/aarch64/tor-browser" \
    "/home/ga/.local/share/torbrowser/tbb/tor-browser"
do
    if [ -d "$candidate/Browser" ]; then
        TOR_BROWSER_DIR="$candidate"
        break
    fi
done

echo "Launching Tor Browser from: $TOR_BROWSER_DIR"
if [ -n "$TOR_BROWSER_DIR" ] && [ -f "$TOR_BROWSER_DIR/start-tor-browser.desktop" ]; then
    su - ga -c "cd $TOR_BROWSER_DIR && DISPLAY=:1 ./start-tor-browser.desktop --detach > /tmp/tor_browser_initial.log 2>&1 &"
else
    su - ga -c "DISPLAY=:1 torbrowser-launcher > /tmp/tor_browser_initial.log 2>&1 &"
fi

# Take an initial screenshot (though Tor Browser may still be opening)
sleep 5
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="