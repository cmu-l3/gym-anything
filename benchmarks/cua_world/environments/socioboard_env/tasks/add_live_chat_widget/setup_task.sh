#!/bin/bash
echo "=== Setting up add_live_chat_widget task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Wait for Socioboard web interface to be ready
if ! wait_for_http "http://localhost/" 120; then
  echo "ERROR: Socioboard not reachable at http://localhost/"
  exit 1
fi

# Ensure correct permissions on the web directory so 'ga' user can edit files
sudo chown -R ga:ga /opt/socioboard/socioboard-web-php/resources/views 2>/dev/null || true

# Generate the live chat widget snippet
cat > /home/ga/widget_code.html << 'EOF'
<!-- HelpDesk Live Chat Widget -->
<script>
  window.HelpDesk = window.HelpDesk || {};
  window.HelpDesk.widgetId = 'SB-99887766';
  (function() {
    var s = document.createElement('script');
    s.src = 'https://cdn.helpdesk.example.com/widget.js';
    s.async = true;
    document.body.appendChild(s);
  })();
</script>
<!-- End HelpDesk Widget -->
EOF

chown ga:ga /home/ga/widget_code.html

# Clear any pre-existing view caches to ensure a clean starting state
cd /opt/socioboard/socioboard-web-php && sudo -u ga php artisan view:clear 2>/dev/null || true

# Open a terminal for the agent to use
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/opt/socioboard/socioboard-web-php &"
sleep 3

# Take initial screenshot showing the terminal
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="