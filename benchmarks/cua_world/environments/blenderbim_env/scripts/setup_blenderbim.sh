#!/bin/bash
set -e

echo "=== Setting up BlenderBIM (Bonsai) ==="

# Wait for desktop to be ready
sleep 5

# ── 1. Create project directories ────────────────────────────────────────
mkdir -p /home/ga/IFCModels
mkdir -p /home/ga/BIMProjects
mkdir -p /home/ga/Desktop
chown -R ga:ga /home/ga/IFCModels /home/ga/BIMProjects /home/ga/Desktop

# ── 2. Verify IFC model data ─────────────────────────────────────────────
echo "=== Checking IFC models ==="
if [ ! -s /home/ga/IFCModels/fzk_haus.ifc ]; then
    echo "FZK-Haus not found, downloading..."
    wget -q "https://www.ifcwiki.org/images/e/e3/AC20-FZK-Haus.ifc" -O /home/ga/IFCModels/fzk_haus.ifc 2>/dev/null || true
fi

if [ -s /home/ga/IFCModels/fzk_haus.ifc ]; then
    echo "IFC models ready"
else
    echo "WARNING: No IFC models available"
fi

ls -la /home/ga/IFCModels/ 2>/dev/null || true
chown -R ga:ga /home/ga/IFCModels

# ── 3. Create launcher script ────────────────────────────────────────────
cat > /home/ga/Desktop/launch_blenderbim.sh << 'EOF'
#!/bin/bash
export DISPLAY=:1
/opt/blender/blender "$@" &
EOF
chmod +x /home/ga/Desktop/launch_blenderbim.sh
chown ga:ga /home/ga/Desktop/launch_blenderbim.sh

# ── 4. Create utility scripts ────────────────────────────────────────────

cat > /usr/local/bin/blenderbim-info << 'EOF'
#!/bin/bash
echo "=== BlenderBIM (Bonsai) Environment Info ==="
echo ""
echo "Blender version:"
/opt/blender/blender --version 2>/dev/null | head -3
echo ""
echo "IFC Models available:"
ls -la /home/ga/IFCModels/ 2>/dev/null || echo "  (none)"
echo ""
echo "BIM Projects:"
ls -la /home/ga/BIMProjects/ 2>/dev/null || echo "  (none)"
EOF
chmod +x /usr/local/bin/blenderbim-info

# ── 5. Warm-up launch to suppress first-run dialogs ─────────────────────
echo "=== Performing warm-up launch ==="
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender > /tmp/blender_warmup.log 2>&1 &"
sleep 10

# Dismiss any first-run dialogs
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape 2>/dev/null || true
sleep 1

# Close the warm-up Blender instance
pkill -f "/opt/blender/blender" 2>/dev/null || true
sleep 2

echo "=== Warm-up complete ==="

# ── 6. Save user preferences after warm-up ───────────────────────────────
chown -R ga:ga /home/ga/.config /home/ga/.local 2>/dev/null || true

echo "=== BlenderBIM (Bonsai) setup complete ==="
echo "IFC Models: /home/ga/IFCModels/"
echo "BIM Projects: /home/ga/BIMProjects/"
ls -la /home/ga/IFCModels/ 2>/dev/null || true
