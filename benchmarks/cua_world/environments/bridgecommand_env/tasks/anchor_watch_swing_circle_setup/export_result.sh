#!/bin/bash
echo "=== Exporting Anchor Watch Task Results ==="

# timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Paths
SCENARIO_DIR="/opt/bridgecommand/Scenarios/a) Anchor Watch Drill"
ORDERS_FILE="/home/ga/Documents/AnchorData/anchor_orders.txt"

# Check file existence
SCENARIO_EXISTS="false"
ENV_EXISTS="false"
OWNSHIP_EXISTS="false"
OTHERSHIP_EXISTS="false"
ORDERS_EXISTS="false"

if [ -d "$SCENARIO_DIR" ]; then
    SCENARIO_EXISTS="true"
    [ -f "$SCENARIO_DIR/environment.ini" ] && ENV_EXISTS="true"
    [ -f "$SCENARIO_DIR/ownship.ini" ] && OWNSHIP_EXISTS="true"
    [ -f "$SCENARIO_DIR/othership.ini" ] && OTHERSHIP_EXISTS="true"
fi

if [ -f "$ORDERS_FILE" ]; then
    ORDERS_EXISTS="true"
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare files for verification
# We will copy the critical INI files and the orders text file to a temp location 
# so verifier.py can copy them out easily using copy_from_env.

EXPORT_DIR="/tmp/anchor_task_export"
rm -rf "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"

if [ "$SCENARIO_EXISTS" = "true" ]; then
    cp "$SCENARIO_DIR"/*.ini "$EXPORT_DIR/" 2>/dev/null || true
fi

if [ "$ORDERS_EXISTS" = "true" ]; then
    cp "$ORDERS_FILE" "$EXPORT_DIR/anchor_orders.txt"
fi

# Create metadata JSON about the export
cat > "$EXPORT_DIR/export_meta.json" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "scenario_exists": $SCENARIO_EXISTS,
    "env_ini_exists": $ENV_EXISTS,
    "ownship_ini_exists": $OWNSHIP_EXISTS,
    "othership_ini_exists": $OTHERSHIP_EXISTS,
    "orders_exists": $ORDERS_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Package everything into a single tarball for easy extraction by verifier
tar -czf /tmp/task_result.tar.gz -C "$EXPORT_DIR" .

echo "Export packaged to /tmp/task_result.tar.gz"