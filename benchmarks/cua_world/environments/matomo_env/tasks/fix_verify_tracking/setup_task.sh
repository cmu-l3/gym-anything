#!/bin/bash
echo "=== Setting up Fix & Verify Tracking Task ==="
source /workspace/scripts/task_utils.sh

# 1. Ensure Matomo is up and Site 1 exists
if ! matomo_is_installed; then
    echo "Waiting for Matomo to complete installation..."
    sleep 10
fi

# Ensure Site 1 exists
if ! site_exists "Initial Site"; then
    echo "Creating Initial Site..."
    matomo_query "INSERT INTO matomo_site (name, main_url, ts_created, ecommerce, sitesearch, sitesearch_keyword_parameters, sitesearch_category_parameters, timezone, currency, exclude_unknown_urls, excluded_ips, excluded_parameters, excluded_user_agents, excluded_referrers, \`group\`, type, keep_url_fragment, creator_login) VALUES ('Initial Site', 'http://localhost', NOW(), 0, 1, '', '', 'UTC', 'USD', 0, '', '', '', '', '', 'website', 0, 'admin')" 2>/dev/null
fi

# 2. Create the "Broken" Landing Page
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/landing_page.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Summer Sale Landing Page</title>
    <style>
        body { font-family: sans-serif; line-height: 1.6; max-width: 800px; margin: 0 auto; padding: 20px; }
        .hero { background: #ff6b6b; color: white; padding: 40px; text-align: center; border-radius: 8px; }
        .offer { border: 2px dashed #ff6b6b; padding: 20px; margin: 20px 0; text-align: center; font-size: 1.2em; }
        .content { margin-top: 30px; }
    </style>
    
    <!-- Matomo Tracking Code (BROKEN) -->
    <script>
      var _paq = window._paq = window._paq || [];
      /* tracker methods like "setCustomDimension" should be called before "trackPageView" */
      // _paq.push(['trackPageView']);  <-- TODO: Enable this!
      _paq.push(['enableLinkTracking']);
      (function() {
        var u="//demo.matomo.org/";   // <-- WRONG URL
        _paq.push(['setTrackerUrl', u+'matomo.php']);
        _paq.push(['setSiteId', '99']); // <-- WRONG SITE ID
        var d=document, g=d.createElement('script'), s=d.getElementsByTagName('script')[0];
        g.async=true; g.src=u+'matomo.js'; s.parentNode.insertBefore(g,s);
      })();
    </script>
    <!-- End Matomo Code -->

</head>
<body>
    <div class="hero">
        <h1>Summer Super Sale!</h1>
        <p>Up to 50% off on all analytics tools</p>
    </div>

    <div class="content">
        <h2>Why Choose Us?</h2>
        <p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.</p>
        
        <div class="offer">
            Use code <strong>ANALYTICS2025</strong> at checkout
        </div>

        <p>Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.</p>
        <p>Scroll down to see more offers...</p>
        <br><br><br><br><br>
        <p>Keep reading to trigger the heartbeat timer...</p>
    </div>
</body>
</html>
HTMLEOF

chown ga:ga /home/ga/Documents/landing_page.html
chmod 644 /home/ga/Documents/landing_page.html

# 3. Timestamp & Initial State
date +%s > /tmp/task_start_time.txt

# Record initial visit count for this specific page title to detect new ones
INITIAL_PAGE_VISITS=$(matomo_query "SELECT COUNT(*) FROM matomo_log_link_visit_action WHERE name='Summer Sale Landing Page'" 2>/dev/null || echo "0")
echo "$INITIAL_PAGE_VISITS" > /tmp/initial_page_visits.txt

# 4. Prepare Environment
# Ensure Firefox is ready
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox &"
    sleep 5
fi

# Close any existing tabs/windows to start clean
DISPLAY=:1 xdotool key ctrl+shift+w 2>/dev/null || true

# Maximize Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="