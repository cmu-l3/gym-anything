#!/bin/bash
# Setup script for Sitemap Status Integrity Audit

source /workspace/scripts/task_utils.sh

echo "=== Setting up Sitemap Status Integrity Audit ==="

# 1. Kill existing instances
kill_screamingfrog ga
sleep 1

# 2. Record start time for anti-gaming
echo "$(date -Iseconds)" > /tmp/task_start_time
date +%s > /tmp/task_start_epoch

# 3. Clean up previous run artifacts
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
SITEMAPS_DIR="/home/ga/Documents/SEO/sitemaps"

# Create directories
mkdir -p "$EXPORT_DIR"
mkdir -p "$REPORTS_DIR"
mkdir -p "$SITEMAPS_DIR"

# Remove old result files
rm -f "$EXPORT_DIR"/sitemap_audit_data.csv
rm -f "$REPORTS_DIR"/sitemap_remediation.txt

# 4. Generate the "Dirty" Sitemap XML
# We use real URLs from crawler-test.com that return specific status codes
SITEMAP_FILE="$SITEMAPS_DIR/draft_sitemap.xml"

cat > "$SITEMAP_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
   <url>
      <loc>https://crawler-test.com/status_codes/200</loc>
      <lastmod>2023-01-01</lastmod>
      <changefreq>monthly</changefreq>
      <priority>1.0</priority>
   </url>
   <url>
      <loc>https://crawler-test.com/status_codes/301</loc>
      <lastmod>2023-01-01</lastmod>
      <changefreq>monthly</changefreq>
      <priority>0.8</priority>
   </url>
   <url>
      <loc>https://crawler-test.com/status_codes/404</loc>
      <lastmod>2023-01-01</lastmod>
      <changefreq>monthly</changefreq>
      <priority>0.8</priority>
   </url>
   <url>
      <loc>https://crawler-test.com/status_codes/500</loc>
      <lastmod>2023-01-01</lastmod>
      <changefreq>monthly</changefreq>
      <priority>0.5</priority>
   </url>
   <url>
      <loc>https://crawler-test.com/status_codes/200?id=2</loc>
      <lastmod>2023-01-01</lastmod>
      <changefreq>monthly</changefreq>
      <priority>0.5</priority>
   </url>
</urlset>
EOF

# Set permissions
chown -R ga:ga "/home/ga/Documents/SEO"
chmod 644 "$SITEMAP_FILE"

echo "Created sitemap at: $SITEMAP_FILE"
echo "URLs included: 200, 301, 404, 500, 200(duplicate)"

# 5. Launch Screaming Frog
echo "Launching Screaming Frog SEO Spider..."
su - ga -c "DISPLAY=:1 /home/ga/launch_screamingfrog.sh" &

# Wait for process
if ! wait_for_process "ScreamingFrogSEOSpider\|screamingfrogseospider" 30; then
    echo "ERROR: Screaming Frog failed to start"
    exit 1
fi

# Wait for UI readiness
wait_for_sf_ready 60

# Focus window
wid=$(get_screamingfrog_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    echo "Focused Screaming Frog window: $wid"
fi

# Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Instructions:"
echo "1. Switch to Mode > List"
echo "2. Upload $SITEMAP_FILE"
echo "3. Crawl and Export to $EXPORT_DIR/sitemap_audit_data.csv"
echo "4. Write report to $REPORTS_DIR/sitemap_remediation.txt"