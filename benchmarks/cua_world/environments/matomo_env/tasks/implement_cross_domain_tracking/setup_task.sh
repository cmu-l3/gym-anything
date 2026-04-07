#!/bin/bash
echo "=== Setting up Cross-Domain Tracking Task ==="
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_timestamp

# 1. Ensure Matomo is ready and Site 1 exists
echo "Waiting for Matomo..."
wait_for_matomo 180
SITE_COUNT=$(get_site_count)
if [ "$SITE_COUNT" = "0" ]; then
    echo "Creating default site..."
    matomo_query "INSERT INTO matomo_site (name, main_url, ts_created, ecommerce, sitesearch, sitesearch_keyword_parameters, sitesearch_category_parameters, timezone, currency, exclude_unknown_urls, excluded_ips, excluded_parameters, excluded_user_agents, excluded_referrers, \`group\`, type, keep_url_fragment, creator_login) VALUES ('Dev Site', 'http://localhost', NOW(), 0, 1, '', '', 'UTC', 'USD', 0, '', '', '', '', '', 'website', 0, 'admin')"
fi

# 2. Setup static site directory
SITE_DIR="/home/ga/sites"
mkdir -p "$SITE_DIR"

# 3. Create landing.html
cat > "$SITE_DIR/landing.html" << 'HTML'
<!DOCTYPE html>
<html>
<head>
    <title>Campaign Landing Page</title>
    <!-- Matomo -->
    <script>
      var _paq = window._paq = window._paq || [];
      /* tracker methods like "setCustomDimension" should be called before "trackPageView" */
      _paq.push(['trackPageView']);
      _paq.push(['enableLinkTracking']);
      (function() {
        var u="//localhost/";
        _paq.push(['setTrackerUrl', u+'matomo.php']);
        _paq.push(['setSiteId', '1']);
        var d=document, g=d.createElement('script'), s=d.getElementsByTagName('script')[0];
        g.async=true; g.src=u+'matomo.js'; s.parentNode.insertBefore(g,s);
      })();
    </script>
    <!-- End Matomo Code -->
</head>
<body>
    <h1>Welcome to the Campaign</h1>
    <p>This is the landing page on <strong>localhost</strong>.</p>
    <p>
        <a href="http://127.0.0.1:8080/shop.html">Click here to go to the Shop (127.0.0.1)</a>
    </p>
</body>
</html>
HTML

# 4. Create shop.html
cat > "$SITE_DIR/shop.html" << 'HTML'
<!DOCTYPE html>
<html>
<head>
    <title>Campaign Shop</title>
    <!-- Matomo -->
    <script>
      var _paq = window._paq = window._paq || [];
      /* tracker methods like "setCustomDimension" should be called before "trackPageView" */
      _paq.push(['trackPageView']);
      _paq.push(['enableLinkTracking']);
      (function() {
        var u="//localhost/";
        _paq.push(['setTrackerUrl', u+'matomo.php']);
        _paq.push(['setSiteId', '1']);
        var d=document, g=d.createElement('script'), s=d.getElementsByTagName('script')[0];
        g.async=true; g.src=u+'matomo.js'; s.parentNode.insertBefore(g,s);
      })();
    </script>
    <!-- End Matomo Code -->
</head>
<body>
    <h1>Shop Page</h1>
    <p>This is the shop page on <strong>127.0.0.1</strong>.</p>
    <p>If tracking works, you should be the same visitor!</p>
</body>
</html>
HTML

chown -R ga:ga "$SITE_DIR"

# 5. Start Python HTTP Server
# Kill any existing server on 8080
fuser -k 8080/tcp 2>/dev/null || true

echo "Starting web server on port 8080..."
su - ga -c "cd $SITE_DIR && python3 -m http.server 8080 > /tmp/http_server.log 2>&1 &"

# 6. Setup Firefox state
# Start Firefox to the landing page
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/landing.html' &"
    sleep 5
fi

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
focus_window "Firefox"

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Setup Complete ==="