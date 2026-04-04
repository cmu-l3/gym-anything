#!/bin/bash
echo "=== Setting up log_corporate_events task ==="

source /workspace/scripts/task_utils.sh

# Mark task start for anti-gaming
mark_task_start

# Clean up any existing data
clean_portfolio_data "tesla_analysis.xml"

# Create the portfolio XML with Tesla security and some history
# This provides a realistic context (chart with data) for the event
cat > /home/ga/Documents/PortfolioData/tesla_analysis.xml << 'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<client>
  <version>68</version>
  <baseCurrency>USD</baseCurrency>
  <securities>
    <security>
      <uuid>sec-tsla-001</uuid>
      <name>Tesla Inc</name>
      <currencyCode>USD</currencyCode>
      <tickerSymbol>TSLA</tickerSymbol>
      <isin>US88160R1014</isin>
      <prices>
        <price t="2024-09-03" v="21060"/>
        <price t="2024-09-10" v="21650"/>
        <price t="2024-09-20" v="23825"/>
        <price t="2024-10-01" v="25802"/>
        <price t="2024-10-08" v="24450"/>
        <price t="2024-10-10" v="23877"/>
        <price t="2024-10-11" v="21780"/>
        <price t="2024-10-24" v="26048"/>
      </prices>
      <attributes/>
      <events/>
      <isRetired>false</isRetired>
    </security>
  </securities>
  <watchlists/>
  <accounts/>
  <portfolios/>
  <plans/>
  <taxonomies/>
  <dashboards/>
  <properties/>
  <settings>
    <bookmarks/>
    <attributeTypes/>
    <configurationSets/>
  </settings>
</client>
XMLEOF

# Set permissions
chown ga:ga /home/ga/Documents/PortfolioData/tesla_analysis.xml

# Ensure Portfolio Performance is running
if ! pgrep -f "PortfolioPerformance" > /dev/null; then
    echo "Starting Portfolio Performance..."
    su - ga -c "DISPLAY=:1 SWT_GTK3=1 GDK_BACKEND=x11 /opt/portfolio-performance/PortfolioPerformance -data /home/ga/.portfolio-performance > /tmp/pp.log 2>&1 &"
    
    # Wait for window
    wait_for_pp_window 60
else
    echo "Portfolio Performance is already running"
fi

# Maximize and focus
WID=$(wmctrl -l | grep -i "Portfolio\|unnamed" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    wmctrl -ia "$WID" 2>/dev/null || true
    wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Close any open dialogs
sleep 1
xdotool key Escape 2>/dev/null || true

# Open the specific portfolio file
open_file_in_pp /home/ga/Documents/PortfolioData/tesla_analysis.xml 15

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="