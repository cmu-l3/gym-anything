#!/bin/bash
echo "=== Setting up optimize_dashboard_base_searches task ==="

source /workspace/scripts/task_utils.sh

# Ensure Splunk is running
if ! splunk_is_running; then
    echo "WARNING: Splunk not running, restarting..."
    /opt/splunk/bin/splunk restart --accept-license --answer-yes --no-prompt
    sleep 15
fi

# Inject the inefficient dashboard XML
DASHBOARD_XML='<dashboard version="1.1">
  <label>Security Executive Overview</label>
  <description>Authentication activity overview</description>
  <row>
    <panel>
      <title>Events by User</title>
      <table>
        <search>
          <query>index=security_logs | stats count by user | sort - count</query>
          <earliest>-30d@d</earliest>
          <latest>now</latest>
        </search>
      </table>
    </panel>
    <panel>
      <title>Top Source IPs (Failed Logins)</title>
      <chart>
        <search>
          <query>index=security_logs "Failed password" | stats count by src_ip | sort - count | head 10</query>
          <earliest>-30d@d</earliest>
          <latest>now</latest>
        </search>
        <option name="charting.chart">bar</option>
      </chart>
    </panel>
  </row>
  <row>
    <panel>
      <title>Authentication Trend</title>
      <chart>
        <search>
          <query>index=security_logs | timechart count by user</query>
          <earliest>-30d@d</earliest>
          <latest>now</latest>
        </search>
        <option name="charting.chart">line</option>
      </chart>
    </panel>
    <panel>
      <title>Unique Ports</title>
      <single>
        <search>
          <query>index=security_logs | stats dc(port) as unique_ports</query>
          <earliest>-30d@d</earliest>
          <latest>now</latest>
        </search>
      </single>
    </panel>
  </row>
</dashboard>'

# Remove existing dashboard if any
curl -sk -u admin:SplunkAdmin1! -X DELETE "https://localhost:8089/servicesNS/admin/search/data/ui/views/Security_Executive_Overview" > /dev/null 2>&1

# Create the inefficient dashboard
curl -sk -u admin:SplunkAdmin1! "https://localhost:8089/servicesNS/admin/search/data/ui/views" \
  -d name="Security_Executive_Overview" \
  --data-urlencode "eai:data=$DASHBOARD_XML" > /dev/null

# Record task start time
echo "$(date +%s)" > /tmp/task_start_timestamp

# Ensure Firefox is running with Splunk visible
echo "Ensuring Firefox with Splunk is visible..."
if ! ensure_firefox_with_splunk 120; then
    echo "CRITICAL ERROR: Could not verify Splunk is visible in Firefox"
    take_screenshot /tmp/task_start_screenshot_FAILED.png
    exit 1
fi

# Navigate directly to the dashboard list to save agent clicks
navigate_to_splunk_page "http://localhost:8000/en-US/app/search/dashboards"

sleep 3
take_screenshot /tmp/task_start_screenshot.png
echo "=== Setup complete. ==="