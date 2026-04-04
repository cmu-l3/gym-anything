#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Research Bookmark Organization Task Setup ==="
echo "Task: Organize research tabs into hierarchical bookmark folders"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Wait for environment to be ready
sleep 2

# Ensure Chrome is properly focused and ready
echo "Setting up Chrome for task..."

# Check if Chrome is running
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome not running, starting it..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh https://www.google.com" &
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

# Function to open URL in new tab
open_url_in_new_tab() {
    local url="$1"
    echo "Opening tab: $url"
    
    # Open new tab
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+t" || true
    sleep 1.5
    
    # Type URL
    su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 '$url'" || true
    sleep 0.5
    
    # Press Enter
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
    sleep 2.5
}

# Navigate first tab to Google (neutral starting point)
echo "Setting up initial tab..."
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://www.google.com'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Open research tabs representing different categories
echo "Opening research tabs..."

# Paper 1: arXiv (for Papers folder)
open_url_in_new_tab "https://arxiv.org/abs/2301.00234"

# Dataset 1: Kaggle (for Datasets folder)
open_url_in_new_tab "https://www.kaggle.com/datasets/allen-institute-for-ai/CORD-19-research-challenge"

# Tool 1: GitHub repository (for Tools folder)
open_url_in_new_tab "https://github.com/pytorch/pytorch"

# Paper 2: Google Scholar search (for Papers folder)
open_url_in_new_tab "https://scholar.google.com/scholar?q=machine+learning"

# Dataset 2: UCI ML Repository (for Datasets folder)
open_url_in_new_tab "https://archive.ics.uci.edu/ml/datasets.php"

# Tool 2: Colab (for Tools folder)
open_url_in_new_tab "https://colab.research.google.com/"

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "unknown")
    echo "✓ Opened $TAB_COUNT tab(s) with research content"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Ensure bookmarks bar is visible
echo "Ensuring bookmarks bar visibility..."
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+shift+b" || true
sleep 0.5

# Save list of opened URLs for verification
curl -s http://localhost:9222/json 2>/dev/null | jq -r '.[] | select(.type == "page") | .url' > /tmp/research_tabs_urls.txt || true

echo "=== Setup complete ==="
echo "Chrome has multiple research tabs open across different categories:"
echo "  - Academic papers (arXiv, Google Scholar)"
echo "  - Datasets (Kaggle, UCI ML Repository)"
echo "  - Tools (GitHub, Colab)"
echo ""
echo "Agent should now:"
echo "  1. Open Bookmark Manager (Ctrl+Shift+O)"
echo "  2. Create 'Research' folder in bookmark bar"
echo "  3. Create sub-folders: 'Papers', 'Datasets', 'Tools'"
echo "  4. Bookmark each tab into the appropriate folder"
echo "     - arXiv, Google Scholar → Papers"
echo "     - Kaggle, UCI → Datasets"
echo "     - GitHub, Colab → Tools"