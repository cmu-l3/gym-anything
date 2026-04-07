#!/bin/bash
# Export script for veterinary_ultrasound_diagnostic_export task

echo "=== Exporting task results ==="

# Record end time and take final screenshot
TASK_END=$(date +%s)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# We will package the output directory and ground truth frames into a single tarball
# so the verifier can easily retrieve all files via copy_from_env.
STAGING_DIR="/tmp/vet_staging"
mkdir -p "$STAGING_DIR"

# 1. Copy the expected deliverables directory
if [ -d "/home/ga/Documents/Cardiology_Referral" ]; then
    cp -r /home/ga/Documents/Cardiology_Referral/* "$STAGING_DIR/" 2>/dev/null || true
fi

# 2. Copy the Ground Truth snapshots
cp /tmp/gt_snapshots/*.png "$STAGING_DIR/" 2>/dev/null || true

# 3. Create a metadata JSON for timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
cat > "$STAGING_DIR/meta.json" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false")
}
EOF

# 4. Tar it all up
cd /tmp
tar -czf vet_export.tar.gz -C "$STAGING_DIR" . 2>/dev/null

chmod 666 /tmp/vet_export.tar.gz 2>/dev/null || true

echo "Results packaged into /tmp/vet_export.tar.gz"
echo "=== Export complete ==="