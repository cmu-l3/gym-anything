#!/bin/bash
echo "=== Setting up open_ifc_project task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Verify IFC model exists ────────────────────────────────────────────
IFC_FILE="/home/ga/IFCModels/fzk_haus.ifc"
if [ ! -f "$IFC_FILE" ]; then
    echo "ERROR: IFC model not found at $IFC_FILE"
    exit 1
fi

echo "IFC model found: $(ls -la $IFC_FILE)"

# ── 2. Save initial state ────────────────────────────────────────────────
cat > /tmp/initial_state.json << EOF
{
    "ifc_file": "$IFC_FILE",
    "ifc_file_size": $(stat -c%s "$IFC_FILE" 2>/dev/null || echo 0),
    "timestamp": "$(date -Iseconds)"
}
EOF

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Launch Blender (empty, so agent must open IFC file) ────────────────
launch_blender
sleep 3

# ── 5. Dismiss splash screen ─────────────────────────────────────────────
dismiss_blender_dialogs
sleep 1

# ── 6. Focus and maximize Blender window ─────────────────────────────────
focus_blender
maximize_blender
sleep 1

# ── 7. Take initial screenshot ───────────────────────────────────────────
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "Agent should see: Blender with Bonsai add-on, empty scene"
echo "Agent must: Use File > Open IFC Project to open $IFC_FILE"
