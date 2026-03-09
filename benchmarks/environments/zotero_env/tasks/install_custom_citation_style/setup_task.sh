#!/bin/bash
set -e
echo "=== Setting up install_custom_citation_style task ==="

# 1. Clean up any previous run artifacts
rm -f /home/ga/Documents/bibliography.rtf
rm -f /home/ga/Documents/journal-of-applied-ai.csl

# Remove the style from Zotero profile if it exists (to ensure fresh install)
PROFILE_DIR=$(find /home/ga/.zotero/zotero -maxdepth 1 -type d -name "*.default" | head -n 1)
if [ -n "$PROFILE_DIR" ]; then
    rm -f "$PROFILE_DIR/styles/journal-of-applied-ai.csl"
    echo "Cleaned up existing style in profile"
fi

# 2. Generate the custom CSL file
# We create a valid CSL 1.0 file based on a simple author-date style but with specific markers
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/journal-of-applied-ai.csl << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<style xmlns="http://purl.org/net/xbiblio/csl" class="in-text" version="1.0" demote-non-dropping-particle="sort-only" default-locale="en-US">
  <info>
    <title>Journal of Applied AI</title>
    <id>http://www.zotero.org/styles/journal-of-applied-ai</id>
    <link href="http://www.zotero.org/styles/journal-of-applied-ai" rel="self"/>
    <author>
      <name>Task Generator</name>
    </author>
    <category citation-format="author-date"/>
    <updated>2025-01-01T00:00:00+00:00</updated>
  </info>
  <macro name="author">
    <names variable="author">
      <name name-as-sort-order="all" and="symbol" sort-separator=", " initialize-with="." delimiter="; " delimiter-precedes-last="always"/>
      <label form="short" prefix=" (" suffix=")" text-case="capitalize-first"/>
    </names>
  </macro>
  <citation collapse="citation-number">
    <sort>
      <key variable="citation-number"/>
    </sort>
    <layout prefix="[" suffix="]" delimiter=", ">
      <text variable="citation-number"/>
    </layout>
  </citation>
  <bibliography entry-spacing="0" second-field-align="flush">
    <layout suffix=". [JAA]">
      <text variable="citation-number" prefix="[" suffix="] "/>
      <text macro="author" suffix=". "/>
      <text variable="title" font-style="italic" suffix=". "/>
      <text variable="container-title" font-style="italic" suffix=", "/>
      <date variable="issued" suffix=".">
        <date-part name="year"/>
      </date>
    </layout>
  </bibliography>
</style>
EOF
chown ga:ga /home/ga/Documents/journal-of-applied-ai.csl
echo "Created custom CSL file at /home/ga/Documents/journal-of-applied-ai.csl"

# 3. Ensure Zotero library has the required papers
# We use the seed script to ensure "all" mode papers (includes ML papers) are present
echo "Seeding library..."
python3 /workspace/scripts/seed_library.py --mode all > /dev/null

# 4. Record initial state and start time
date +%s > /tmp/task_start_time.txt

# 5. Start Zotero (if not running) and ensure window is ready
if ! pgrep -f "zotero" > /dev/null; then
    echo "Starting Zotero..."
    sudo -u ga bash -c 'DISPLAY=:1 /opt/zotero/zotero --no-remote > /dev/null 2>&1 &'
    sleep 10
fi

# Wait for Zotero window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Zotero"; then
        echo "Zotero window detected"
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# 6. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="