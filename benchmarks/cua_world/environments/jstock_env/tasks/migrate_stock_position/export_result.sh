#!/bin/bash
echo "=== Exporting migrate_stock_position results ==="

# Define paths
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
PORTFOLIOS_DIR="${JSTOCK_DATA_DIR}/portfolios"
OLD_CSV="${PORTFOLIOS_DIR}/My Portfolio/buyportfolio.csv"
NEW_CSV="${PORTFOLIOS_DIR}/Semiconductor Fund/buyportfolio.csv"

# Destination for verifier
EXPORT_DIR="/tmp/jstock_export"
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR"/*

# 1. Export File Existence Status
OLD_EXISTS="false"
NEW_EXISTS="false"

if [ -f "$OLD_CSV" ]; then
    OLD_EXISTS="true"
    cp "$OLD_CSV" "$EXPORT_DIR/old_portfolio.csv"
fi

if [ -f "$NEW_CSV" ]; then
    NEW_EXISTS="true"
    cp "$NEW_CSV" "$EXPORT_DIR/new_portfolio.csv"
fi

# 2. Check directory creation time (Anti-gaming)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
NEW_DIR_CREATED_DURING_TASK="false"
if [ -d "${PORTFOLIOS_DIR}/Semiconductor Fund" ]; then
    DIR_MTIME=$(stat -c %Y "${PORTFOLIOS_DIR}/Semiconductor Fund" 2>/dev/null || echo "0")
    if [ "$DIR_MTIME" -ge "$TASK_START" ]; then
        NEW_DIR_CREATED_DURING_TASK="true"
    fi
fi

# 3. Capture Final Screenshot
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_final.png 2>/dev/null || true

# 4. Create Metadata JSON
cat > "$EXPORT_DIR/file_status.json" << EOF
{
    "old_portfolio_exists": $OLD_EXISTS,
    "new_portfolio_exists": $NEW_EXISTS,
    "new_dir_created_during_task": $NEW_DIR_CREATED_DURING_TASK,
    "task_start_time": $TASK_START
}
EOF

# 5. Archive for export
# We zip the export directory to a single file for easy copy_from_env
cd /tmp
tar -czf task_result.tar.gz jstock_export task_final.png

echo "Export complete. Data saved to /tmp/task_result.tar.gz"