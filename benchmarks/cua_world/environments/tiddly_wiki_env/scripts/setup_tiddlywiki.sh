#!/bin/bash
set -e

echo "=== Setting up TiddlyWiki ==="

# Wait for desktop to be ready
sleep 5

# Create wiki directory for user ga
WIKI_DIR="/home/ga/mywiki"
mkdir -p "$WIKI_DIR"
chown ga:ga "$WIKI_DIR"

# Initialize TiddlyWiki server wiki as ga user
su - ga -c "cd /home/ga && tiddlywiki mywiki --init server"

# Seed the wiki with real content from data files
if [ -f /workspace/data/seed_tiddlers.json ]; then
    echo "=== Seeding wiki with real content ==="
    # Use Node.js to parse JSON and create .tid files
    su - ga -c 'node -e "
const fs = require(\"fs\");
const path = require(\"path\");

const tiddlers = JSON.parse(fs.readFileSync(\"/workspace/data/seed_tiddlers.json\", \"utf8\"));
const tiddlerDir = \"/home/ga/mywiki/tiddlers\";

// Ensure tiddlers directory exists
if (!fs.existsSync(tiddlerDir)) {
    fs.mkdirSync(tiddlerDir, { recursive: true });
}

tiddlers.forEach(t => {
    // Sanitize filename
    let filename = t.title.replace(/[\/\\\\:*?\"<>|]/g, \"_\").replace(/\\s+/g, \" \");
    let filepath = path.join(tiddlerDir, filename + \".tid\");

    let content = \"\";
    if (t.created) content += \"created: \" + t.created + \"\\n\";
    if (t.modified) content += \"modified: \" + t.modified + \"\\n\";
    if (t.tags) content += \"tags: \" + t.tags + \"\\n\";
    content += \"title: \" + t.title + \"\\n\";
    if (t.type) content += \"type: \" + t.type + \"\\n\";
    content += \"\\n\" + (t.text || \"\");

    fs.writeFileSync(filepath, content, \"utf8\");
    console.log(\"Created: \" + filename);
});

console.log(\"Seeded \" + tiddlers.length + \" tiddlers\");
"'
fi

# Start TiddlyWiki server on port 8080 (no auth for easier agent interaction)
su - ga -c "cd /home/ga && nohup tiddlywiki mywiki --listen host=0.0.0.0 port=8080 > /home/ga/tiddlywiki.log 2>&1 &"

# Wait for TiddlyWiki server to start
echo "Waiting for TiddlyWiki server..."
TIMEOUT=60
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if curl -s http://localhost:8080/ > /dev/null 2>&1; then
        echo "TiddlyWiki server is running on port 8080"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "WARNING: TiddlyWiki server did not start within timeout"
    cat /home/ga/tiddlywiki.log
fi

# Configure Firefox profile
FIREFOX_PROFILE_DIR="/home/ga/.mozilla/firefox"
sudo -u ga mkdir -p "$FIREFOX_PROFILE_DIR/default-release"

# Create profiles.ini
cat > "$FIREFOX_PROFILE_DIR/profiles.ini" << 'EOF'
[Install4F96D1932A9F858E]
Default=default-release
Locked=1

[Profile0]
Name=default-release
IsRelative=1
Path=default-release
Default=1

[General]
StartWithLastProfile=1
Version=2
EOF
chown ga:ga "$FIREFOX_PROFILE_DIR/profiles.ini"

# Create user.js with preferences
cat > "$FIREFOX_PROFILE_DIR/default-release/user.js" << 'EOF'
// Disable first-run screens
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.messaging-system.whatsNewPanel.enabled", false);

// Set homepage to TiddlyWiki
user_pref("browser.startup.homepage", "http://localhost:8080/");
user_pref("browser.startup.page", 1);

// Disable password save prompts
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);

// Disable sidebar
user_pref("sidebar.revamp", false);
user_pref("sidebar.verticalTabs", false);
user_pref("browser.sidebar.dismissed", true);

// Disable new tab page
user_pref("browser.newtabpage.enabled", false);
user_pref("browser.newtab.url", "about:blank");

// Performance
user_pref("browser.cache.disk.enable", false);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.tabs.warnOnCloseOtherTabs", false);
EOF
chown ga:ga "$FIREFOX_PROFILE_DIR/default-release/user.js"

# Launch Firefox pointing to TiddlyWiki
su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/' > /tmp/firefox.log 2>&1 &"

# Wait for Firefox window to appear
echo "Waiting for Firefox..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|tiddly"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Maximize Firefox window
sleep 3
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|tiddly" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
    echo "Firefox maximized"
fi

echo "=== TiddlyWiki setup complete ==="
echo "Access TiddlyWiki at http://localhost:8080/"
