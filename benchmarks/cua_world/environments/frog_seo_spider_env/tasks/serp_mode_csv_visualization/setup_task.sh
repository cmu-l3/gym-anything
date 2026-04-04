#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up SERP Mode Visualization Task ==="

# 1. Kill existing instances to ensure fresh state
kill_screamingfrog ga
sleep 1

# 2. Record task start time for anti-gaming verification
echo "$(date -Iseconds)" > /tmp/task_start_time
date +%s > /tmp/task_start_epoch

# 3. Create directories
mkdir -p /home/ga/Documents/SEO/exports
mkdir -p /home/ga/Documents/SEO/reports
chown -R ga:ga /home/ga/Documents/SEO

# 4. Create the draft metadata CSV file (Input Data)
# We deliberately include a very long title to test truncation logic
cat > /home/ga/Documents/SEO/draft_metadata.csv << 'EOF'
URL,Title,Description
https://example.com/blog/seo-guide,"The Ultimate Guide to SEO that is Definitely Too Long For Google to Display Fully in the Search Results Page","Learn everything about SEO in this comprehensive guide."
https://example.com/blog/tips,"10 Quick SEO Tips","Short and sweet tips."
https://example.com/blog/marketing,"Digital Marketing Trends for 2026","What to expect in the future."
https://example.com/blog/audit,"How to Perform a Technical Audit","Step by step guide."
https://example.com/blog/tools,"Top 10 SEO Tools You Need","Tools for success."
https://example.com/blog/local,"Local SEO Strategies for Small Business Owners in Competitive Markets","Dominate your local area."
https://example.com/blog/content,"Content Marketing 101","Basics of content."
https://example.com/blog/links,"Link Building Strategies","Get more backlinks."
https://example.com/blog/ppc,"PPC vs SEO: Which is Better?","Comparing paid and organic."
https://example.com/blog/social,"Social Media Integration","Connect your accounts."
EOF
chown ga:ga /home/ga/Documents/SEO/draft_metadata.csv

# 5. Clear previous exports to avoid confusion
rm -f /home/ga/Documents/SEO/exports/*.csv

# 6. Launch Screaming Frog
echo "Launching Screaming Frog..."
su - ga -c "DISPLAY=:1 /home/ga/launch_screamingfrog.sh" &

# 7. Wait for application to be ready
if ! wait_for_process "ScreamingFrogSEOSpider\|screamingfrogseospider" 30; then
    echo "ERROR: Screaming Frog failed to start"
    exit 1
fi

wait_for_window "Screaming Frog\|SEO Spider" 45

# Wait for full initialization
wait_for_sf_ready 60

# 8. Focus window
wid=$(get_screamingfrog_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# 9. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Input file created at: ~/Documents/SEO/draft_metadata.csv"
echo "Ready for SERP mode task."