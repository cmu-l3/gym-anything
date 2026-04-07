#!/bin/bash
echo "=== Exporting configure_magnitude_pipeline results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Gather timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

SCAMP_STAT=$(stat -c "%Y %s" "$SEISCOMP_ROOT/etc/scamp.cfg" 2>/dev/null || echo "0 0")
SCAMP_MTIME=$(echo "$SCAMP_STAT" | awk '{print $1}')

SCMAG_STAT=$(stat -c "%Y %s" "$SEISCOMP_ROOT/etc/scmag.cfg" 2>/dev/null || echo "0 0")
SCMAG_MTIME=$(echo "$SCMAG_STAT" | awk '{print $1}')

USER_SCAMP_DUMP=$(stat -c "%s" "/home/ga/scamp_config_dump.txt" 2>/dev/null || echo "0")
USER_SCMAG_DUMP=$(stat -c "%s" "/home/ga/scmag_config_dump.txt" 2>/dev/null || echo "0")

# 3. Generate the TRUE effective configuration to bypass arbitrary syntax/formatting
# SeisComP's config dump interprets the user's config and outputs flattened key=value pairs
echo "Dumping effective SeisComP configuration for rigorous verification..."
su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
    LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
    seiscomp exec scamp --dump-config 2>/dev/null" > /tmp/true_scamp_dump.txt

su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
    LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
    seiscomp exec scmag --dump-config 2>/dev/null" > /tmp/true_scmag_dump.txt

# Base64 encode the files to safely store them in JSON without escaping issues
TRUE_SCAMP_B64=$(base64 -w 0 /tmp/true_scamp_dump.txt 2>/dev/null || echo "")
TRUE_SCMAG_B64=$(base64 -w 0 /tmp/true_scmag_dump.txt 2>/dev/null || echo "")

# 4. Create the result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "task_start": $TASK_START,
  "scamp_mtime": $SCAMP_MTIME,
  "scmag_mtime": $SCMAG_MTIME,
  "user_scamp_dump_size": $USER_SCAMP_DUMP,
  "user_scmag_dump_size": $USER_SCMAG_DUMP,
  "true_scamp_b64": "$TRUE_SCAMP_B64",
  "true_scmag_b64": "$TRUE_SCMAG_B64"
}
EOF

# Move securely to prevent permission failures
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON written to /tmp/task_result.json"
echo "=== Export complete ==="