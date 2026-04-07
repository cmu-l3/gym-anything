#!/bin/bash
set -e
echo "=== Setting up update_prescription_header task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 1. Locate MedinTux DrTux directory in Wine prefix
# Standard path: .../Programmes/DrTux/bin
# We search for DrTux.exe to be sure
DRTUX_EXE=$(find /home/ga/.wine/drive_c -name "DrTux.exe" 2>/dev/null | head -1)

if [ -z "$DRTUX_EXE" ]; then
    echo "ERROR: DrTux.exe not found. MedinTux installation might be incomplete."
    # Try to recover by running install check
    /workspace/scripts/setup_medintux.sh
    DRTUX_EXE=$(find /home/ga/.wine/drive_c -name "DrTux.exe" 2>/dev/null | head -1)
fi

if [ -z "$DRTUX_EXE" ]; then
    echo "FATAL: Could not locate DrTux.exe"
    exit 1
fi

DRTUX_BIN_DIR=$(dirname "$DRTUX_EXE")
# Modeles directory is usually in bin/Modeles or parallel to bin
# Let's check structure. Usually: .../DrTux/bin/DrTux.exe
# Templates: .../DrTux/bin/Modeles/EnTetes/

TEMPLATE_DIR="$DRTUX_BIN_DIR/Modeles/EnTetes"
mkdir -p "$TEMPLATE_DIR"

echo "Template directory: $TEMPLATE_DIR"

# 2. Create the initial 'Header_Standard.html' with OLD address
# We use ISO-8859-1 or UTF-8. MedinTux handles HTML well.
cat > "$TEMPLATE_DIR/Header_Standard.html" <<EOF
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<title>Header_Standard</title>
</head>
<body>
<div align="center">
  <h2>Cabinet Médical DrTux</h2>
  <p>Dr. Jean Médecin - Généraliste</p>
  <hr width="80%">
  <p>
    12 Rue de l'Ancienne Poste<br>
    69000 Lyon<br>
    Tel: 04 72 00 00 00
  </p>
  <hr width="80%">
</div>
</body>
</html>
EOF

# Ensure permissions are correct for 'ga' user
chown -R ga:ga "$(dirname "$TEMPLATE_DIR")"

# 3. Record initial state of the file
INITIAL_MTIME=$(stat -c %Y "$TEMPLATE_DIR/Header_Standard.html")
echo "$INITIAL_MTIME" > /tmp/initial_file_mtime.txt
echo "$TEMPLATE_DIR/Header_Standard.html" > /tmp/template_path.txt

# 4. Launch MedinTux Manager
# The agent needs to navigate from Manager -> DrTux, or we can launch DrTux directly.
# Task description says "Open the DrTux module", implying starting from Manager is fine,
# but launching DrTux directly saves a step and reduces navigation ambiguity.
# However, standard workflow is via Manager. Let's stick to Manager to be consistent with other tasks.

launch_medintux_manager

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="