#!/bin/bash
set -e
echo "=== Setting up Loyalty Tier Classification Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for OrientDB to be ready
wait_for_orientdb 60

echo "Cleaning up any previous run artifacts..."

# Drop classes if they exist (Reverse order of dependencies)
# 1. Drop edges
if orientdb_class_exists "demodb" "BelongsToTier"; then
    echo "Dropping BelongsToTier edge class..."
    orientdb_sql "demodb" "DROP CLASS BelongsToTier UNSAFE" > /dev/null
fi

# 2. Drop vertices
if orientdb_class_exists "demodb" "LoyaltyTiers"; then
    echo "Dropping LoyaltyTiers vertex class..."
    orientdb_sql "demodb" "DROP CLASS LoyaltyTiers UNSAFE" > /dev/null
fi

# 3. Remove property from Profiles
# We check if property exists by looking at the schema
echo "Checking for LoyaltyTier property on Profiles..."
# There isn't a direct SQL DROP PROPERTY IF EXISTS, so we try and ignore error
orientdb_sql "demodb" "DROP PROPERTY Profiles.LoyaltyTier" > /dev/null 2>&1 || true

# Remove report file
rm -f /home/ga/loyalty_report.txt

# Ensure Firefox is open to Studio
echo "Launching Firefox..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="