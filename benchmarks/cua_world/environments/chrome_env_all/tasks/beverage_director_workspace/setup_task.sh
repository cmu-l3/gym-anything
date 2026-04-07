#!/bin/bash
set -euo pipefail

echo "=== Setting up Beverage Director Workspace Task ==="
echo "Task: Import bookmarks, organize folders, configure fonts/translation, flags, search, and startup."

# Record task start time
date +%s > /tmp/task_start_time.txt

# Stop any running Chrome to configure initial state cleanly
pkill -f "google-chrome" 2>/dev/null || true
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 2
pkill -9 -f "google-chrome" 2>/dev/null || true

# Set up Chrome profile directory
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"

# Create a clean Preferences file with translation disabled and fonts at default
cat > "$CHROME_PROFILE/Preferences" << 'PREF_EOF'
{
   "browser": {
      "show_home_button": true
   },
   "translate": {
      "enabled": false
   },
   "webkit": {
      "webprefs": {
         "default_font_size": 16,
         "minimum_font_size": 0
      }
   }
}
PREF_EOF
chown -R ga:ga "/home/ga/.config/google-chrome"

# Create the bookmark HTML file to be imported
cat > "/home/ga/Desktop/cellar_bookmarks.html" << 'HTML_EOF'
<!DOCTYPE NETSCAPE-Bookmark-file-1>
<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
<TITLE>Bookmarks</TITLE>
<H1>Bookmarks</H1>
<DL><p>
    <DT><A HREF="https://www.inao.gouv.fr/">INAO</A>
    <DT><A HREF="https://www.federdoc.com/">Federdoc</A>
    <DT><A HREF="https://www.riojawine.com/">Rioja</A>
    <DT><A HREF="https://www.vins-bourgogne.fr/">Vins de Bourgogne</A>
    <DT><A HREF="https://www.bordeaux.com/">Bordeaux</A>
    <DT><A HREF="https://www.chianticlassico.com/">Chianti Classico</A>
    <DT><A HREF="https://www.ttb.gov/">TTB AVAs</A>
    <DT><A HREF="https://www.wineaustralia.com/">Wine Australia</A>
    <DT><A HREF="https://www.wosa.co.za/">WOSA</A>
    <DT><A HREF="https://www.nzwine.com/">NZ Wine</A>
    <DT><A HREF="https://www.winesofargentina.org/">Wines of Argentina</A>
    <DT><A HREF="https://www.skurnik.com/">Skurnik</A>
    <DT><A HREF="https://www.kermitlynch.com/">Kermit Lynch</A>
    <DT><A HREF="https://www.rosenthalwinemerchant.com/">Rosenthal</A>
    <DT><A HREF="https://www.winebow.com/">Winebow</A>
    <DT><A HREF="https://www.southernglazers.com/">Southern Glazers</A>
    <DT><A HREF="https://www.sevenfifty.com/">SevenFifty</A>
    <DT><A HREF="https://www.guildsomm.com/">GuildSomm</A>
    <DT><A HREF="https://www.wine-searcher.com/">Wine-Searcher</A>
    <DT><A HREF="https://www.jancisrobinson.com/">Jancis Robinson</A>
    <DT><A HREF="https://www.decanter.com/">Decanter</A>
    <DT><A HREF="https://winefolly.com/">Wine Folly</A>
    <DT><A HREF="https://www.espn.com/">ESPN (Junk)</A>
    <DT><A HREF="https://www.netflix.com/">Netflix (Junk)</A>
    <DT><A HREF="https://www.facebook.com/">Facebook (Junk)</A>
    <DT><A HREF="https://twitter.com/">X/Twitter (Junk)</A>
</DL><p>
HTML_EOF
chown ga:ga "/home/ga/Desktop/cellar_bookmarks.html"

# Create the spec document for the agent to reference
cat > "/home/ga/Desktop/cellar_workstation_spec.txt" << 'SPEC_EOF'
BEVERAGE TEAM BROWSER STANDARD
------------------------------
1. BOOKMARKS: Import from ~/Desktop/cellar_bookmarks.html.
   Organize imported bookmarks into these 4 folders on the Bookmark Bar:
   - Old World Appellations
   - New World Regions
   - Distributors & Allocations
   - Education & Reference
   Remove any personal/junk bookmarks imported (ESPN, Netflix, Facebook, X/Twitter).
   Do not leave any bookmarks un-foldered on the Bookmark Bar.

2. DOWNLOADS: Create directory ~/Documents/Tech_Sheets. Set as default download directory and enable "Ask where to save each file before downloading".

3. ACCESSIBILITY/TRANSLATION: Change Medium (Default) font size to 18 and Minimum font size to 14. Enable Chrome's "Offer to translate pages" setting.

4. PERFORMANCE FLAGS: Navigate to chrome://flags and enable #smooth-scrolling and #enable-parallel-downloading for handling large PDF portfolios.

5. SEARCH ENGINES: Add custom shortcuts:
   - Keyword: ws -> https://www.wine-searcher.com/find?s=%s
   - Keyword: gs -> https://www.guildsomm.com/search?q=%s

6. STARTUP: Set On Startup to open specific pages: sevenfifty.com and binwise.com.
SPEC_EOF
chown ga:ga "/home/ga/Desktop/cellar_workstation_spec.txt"

# Ensure the Tech_Sheets folder does NOT exist initially
rm -rf "/home/ga/Documents/Tech_Sheets" 2>/dev/null || true

# Launch Chrome
echo "Launching Chrome..."
su - ga -c "DISPLAY=:1 google-chrome-stable --no-first-run --no-default-browser-check > /tmp/chrome.log 2>&1 &"
sleep 5

# Maximize Chrome window
DISPLAY=:1 wmctrl -r "Google Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="