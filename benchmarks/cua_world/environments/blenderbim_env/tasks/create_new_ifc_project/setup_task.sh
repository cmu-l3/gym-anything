#!/bin/bash
echo "=== Setting up create_new_ifc_project task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/office_building.ifc 2>/dev/null || true

# ── 3. Save initial state ────────────────────────────────────────────────
cat > /tmp/initial_state.json << EOF
{
    "output_file": "/home/ga/BIMProjects/office_building.ifc",
    "output_exists": false,
    "timestamp": "$(date -Iseconds)"
}
EOF

# ── 4. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 5. Launch Blender with empty scene ────────────────────────────────────
launch_blender
sleep 3

# ── 6. Dismiss splash screen ─────────────────────────────────────────────
dismiss_blender_dialogs
sleep 1

# ── 7. Focus and maximize Blender window ─────────────────────────────────
focus_blender
maximize_blender
sleep 1

# ── 8. Take initial screenshot ───────────────────────────────────────────
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "Agent should see: Blender with Bonsai add-on, empty default scene"
echo "Agent must: Create new IFC project, set name to 'Office Building', save to /home/ga/BIMProjects/office_building.ifc"
