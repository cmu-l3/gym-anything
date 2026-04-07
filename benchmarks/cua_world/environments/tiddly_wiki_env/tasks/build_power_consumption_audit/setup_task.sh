#!/bin/bash
echo "=== Setting up build_power_consumption_audit task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time

# 1. Create the Seed Data (Appliance tiddlers)
echo "Creating Appliance seed tiddlers..."

cat > "$TIDDLER_DIR/Refrigerator.tid" << 'EOF'
title: Refrigerator
tags: Appliance
power_watts: 150
hours_per_day: 8

Standard kitchen refrigerator.
EOF

cat > "$TIDDLER_DIR/LED_Lights.tid" << 'EOF'
title: LED Lights
tags: Appliance
power_watts: 40
hours_per_day: 5

Living room and kitchen overhead lights.
EOF

cat > "$TIDDLER_DIR/Laptop.tid" << 'EOF'
title: Laptop
tags: Appliance
power_watts: 60
hours_per_day: 4

Work laptop charging.
EOF

cat > "$TIDDLER_DIR/Starlink_Router.tid" << 'EOF'
title: Starlink Router
tags: Appliance
power_watts: 50
hours_per_day: 24

Satellite internet connection, running 24/7.
EOF

cat > "$TIDDLER_DIR/Water_Pump.tid" << 'EOF'
title: Water Pump
tags: Appliance
power_watts: 800
hours_per_day: 0.5

Well water pump pressurizing the accumulator tank.
EOF

# Ensure appropriate ownership
chown -R ga:ga "$TIDDLER_DIR"

# Wait a moment for TiddlyWiki Node.js server to detect filesystem changes
sleep 2

# Refresh Firefox to ensure seed data is loaded in the browser state
echo "Refreshing Firefox..."
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key F5
sleep 2

# Take initial screenshot of the starting state
take_screenshot /tmp/power_audit_initial.png

echo "=== Task setup complete ==="