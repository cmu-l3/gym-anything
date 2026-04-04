#!/bin/bash
set -e

echo "=== Setting up Houdini environment ==="

# Wait for desktop to be ready
sleep 5

# ================================================================
# 1. DETECT HOUDINI INSTALLATION
# ================================================================
HFS_DIR=$(find -L /opt -maxdepth 1 -type d -name "hfs*" | sort -V | tail -1)
HOUDINI_INSTALLED=false
HOUDINI_VERSION=""
HOUDINI_MAJOR=""

if [ -n "$HFS_DIR" ]; then
    HOUDINI_INSTALLED=true
    export HFS="$HFS_DIR"
    cd "$HFS_DIR" && source houdini_setup 2>/dev/null && cd / || true
    HOUDINI_VERSION=$(basename "$HFS_DIR" | sed 's/hfs//')
    HOUDINI_MAJOR=$(echo "$HOUDINI_VERSION" | cut -d. -f1-2)
    echo "Houdini $HOUDINI_VERSION found at $HFS_DIR"
else
    echo "WARNING: Houdini not installed. Skipping Houdini-specific steps."
    HOUDINI_MAJOR="20.5"
fi

# ================================================================
# 2. CREATE USER DIRECTORIES
# ================================================================
echo "Creating user directories..."

PROJECTS_DIR="/home/ga/HoudiniProjects"
DATA_DIR="/home/ga/HoudiniProjects/data"
RENDERS_DIR="/home/ga/HoudiniProjects/renders"
HOUDINI_USER_DIR="/home/ga/houdini${HOUDINI_MAJOR}"

mkdir -p "$PROJECTS_DIR"
mkdir -p "$DATA_DIR"
mkdir -p "$RENDERS_DIR"
mkdir -p "$HOUDINI_USER_DIR"
mkdir -p /home/ga/Desktop
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/

# ================================================================
# 3. CONFIGURE HOUDINI PREFERENCES (DIALOG SUPPRESSION)
# ================================================================
echo "Configuring Houdini preferences..."

# Create houdini.env for the user
cat > "$HOUDINI_USER_DIR/houdini.env" << 'ENVEOF'
# Suppress startup dialogs
HOUDINI_NO_START_PAGE_SPLASH = 1
HOUDINI_ANONYMOUS_STATISTICS = 0
HOUDINI_NOHKEY = 1
HOUDINI_LMINFO_VERBOSE = 0
HOUDINI_PROMPT_ON_CRASHES = 0
HOUDINI_DISABLE_FILE_LOAD_WARNINGS = 1
ENVEOF

# Copy config from mounted config dir if available
if [ -f /workspace/config/houdini.env ]; then
    cp /workspace/config/houdini.env "$HOUDINI_USER_DIR/houdini.env"
fi

# ================================================================
# 4. DOWNLOAD REAL 3D DATA
# ================================================================
echo "Downloading real 3D data for tasks..."

# Stanford Bunny OBJ (classic 3D test model, real scan data)
BUNNY_URL="https://graphics.stanford.edu/~mdfisher/Data/Meshes/bunny.obj"
BUNNY_FALLBACK1="https://raw.githubusercontent.com/alecjacobson/common-3d-test-models/master/data/stanford-bunny.obj"
BUNNY_PATH="$DATA_DIR/bunny.obj"

if [ ! -f "$BUNNY_PATH" ]; then
    echo "Downloading Stanford Bunny OBJ..."
    wget -q --timeout=30 "$BUNNY_URL" -O "$BUNNY_PATH" 2>/dev/null || \
    wget -q --timeout=30 "$BUNNY_FALLBACK1" -O "$BUNNY_PATH" 2>/dev/null || \
    curl -sL --max-time 30 "$BUNNY_URL" -o "$BUNNY_PATH" 2>/dev/null || \
    curl -sL --max-time 30 "$BUNNY_FALLBACK1" -o "$BUNNY_PATH" 2>/dev/null || {
        echo "WARNING: Could not download Stanford Bunny OBJ"
    }
fi

if [ -f "$BUNNY_PATH" ]; then
    echo "  Stanford Bunny OBJ: $(du -h "$BUNNY_PATH" | cut -f1)"
fi

# Download Poly Haven HDRI (real photographed environment map)
HDRI_URL="https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/1k/venice_sunset_1k.hdr"
HDRI_PATH="$DATA_DIR/venice_sunset_1k.hdr"

if [ ! -f "$HDRI_PATH" ]; then
    echo "Downloading Poly Haven HDRI (Venice Sunset)..."
    wget -q --timeout=60 "$HDRI_URL" -O "$HDRI_PATH" 2>/dev/null || \
    curl -sL --max-time 60 "$HDRI_URL" -o "$HDRI_PATH" 2>/dev/null || {
        echo "WARNING: Could not download HDRI"
    }
fi

if [ -f "$HDRI_PATH" ]; then
    echo "  HDRI: $(du -h "$HDRI_PATH" | cut -f1)"
fi

# Download Utah Teapot OBJ (another classic real test model)
TEAPOT_URL="https://graphics.stanford.edu/courses/cs148-10-summer/as3/code/as3/teapot.obj"
TEAPOT_FALLBACK="https://raw.githubusercontent.com/alecjacobson/common-3d-test-models/master/data/utah-teapot.obj"
TEAPOT_PATH="$DATA_DIR/teapot.obj"

if [ ! -f "$TEAPOT_PATH" ]; then
    echo "Downloading Utah Teapot OBJ..."
    wget -q --timeout=30 "$TEAPOT_URL" -O "$TEAPOT_PATH" 2>/dev/null || \
    wget -q --timeout=30 "$TEAPOT_FALLBACK" -O "$TEAPOT_PATH" 2>/dev/null || \
    curl -sL --max-time 30 "$TEAPOT_URL" -o "$TEAPOT_PATH" 2>/dev/null || \
    curl -sL --max-time 30 "$TEAPOT_FALLBACK" -o "$TEAPOT_PATH" 2>/dev/null || {
        echo "WARNING: Could not download Utah Teapot"
    }
fi

if [ -f "$TEAPOT_PATH" ]; then
    echo "  Utah Teapot OBJ: $(du -h "$TEAPOT_PATH" | cut -f1)"
fi

# Set ownership
chown -R ga:ga "$DATA_DIR"

echo "Data files in $DATA_DIR:"
ls -la "$DATA_DIR/" 2>/dev/null || echo "  (empty)"

# ================================================================
# 5-7: HOUDINI-SPECIFIC STEPS (SKIP IF NOT INSTALLED)
# ================================================================
if [ "$HOUDINI_INSTALLED" = "true" ]; then

    # ================================================================
    # 5a. START LICENSE SERVER AND CHECK LICENSING
    # ================================================================
    echo "Starting Houdini license server (hserver)..."

    # Start hserver if not already running
    if ! pgrep -x hserver > /dev/null 2>&1; then
        if [ -x "$HFS_DIR/bin/hserver" ]; then
            "$HFS_DIR/bin/hserver" &
            sleep 2
            echo "hserver started"
        fi
    else
        echo "hserver already running"
    fi

    # Try licensing with SideFX API credentials if available
    CREDS_FILE="/workspace/config/sidefx_credentials.env"
    if [ -f "$CREDS_FILE" ]; then
        source "$CREDS_FILE" 2>/dev/null || true
        if [ -n "${SIDEFX_CLIENT_ID:-}" ] && [ -n "${SIDEFX_CLIENT_SECRET:-}" ]; then
            echo "Attempting license setup with SideFX API credentials..."
            SESICTRL=""
            if [ -x /usr/lib/sesi/sesictrl ]; then
                SESICTRL="/usr/lib/sesi/sesictrl"
            elif [ -x "$HFS_DIR/bin/sesictrl" ]; then
                SESICTRL="$HFS_DIR/bin/sesictrl"
            fi
            if [ -n "$SESICTRL" ]; then
                "$SESICTRL" login --clientid "$SIDEFX_CLIENT_ID" --clientsecret "$SIDEFX_CLIENT_SECRET" 2>&1 || \
                    echo "sesictrl login failed — license dialog will appear in GUI"
            fi
        fi
    fi

    # Test if hython can actually run (licensing check)
    HYTHON_WORKS=false
    if "$HFS_DIR/bin/hython" -c "import hou; print('OK')" 2>/dev/null | grep -q "OK"; then
        HYTHON_WORKS=true
        echo "hython is licensed and working"
    else
        echo "hython license check failed — scenes will not be pre-created"
        echo "Houdini GUI will launch but may show a license dialog"
    fi

    # ================================================================
    # 5b. CREATE BASELINE SCENE USING HYTHON (only if licensed)
    # ================================================================
    if [ "$HYTHON_WORKS" = "true" ]; then
    echo "Creating baseline scene..."
    cat > /tmp/create_baseline.py << 'PYEOF'
import hou
import os
import sys

print("Creating baseline Houdini scene...")

geo = hou.node("/obj").createNode("geo", "baseline_geo")

grid = geo.createNode("grid")
grid.parm("sizex").set(10)
grid.parm("sizey").set(10)
grid.parm("rows").set(10)
grid.parm("cols").set(10)

xform = geo.createNode("xform", "ground_xform")
xform.setInput(0, grid)
xform.parm("ty").set(0)
xform.setDisplayFlag(True)
xform.setRenderFlag(True)

cam = hou.node("/obj").createNode("cam", "main_camera")
cam.parm("tx").set(5)
cam.parm("ty").set(4)
cam.parm("tz").set(5)
cam.parm("rx").set(-30)
cam.parm("ry").set(45)

light = hou.node("/obj").createNode("hlight", "key_light")
light.parm("tx").set(3)
light.parm("ty").set(5)
light.parm("tz").set(3)
light.parm("light_intensity").set(1.5)

hou.node("/obj").layoutChildren()
geo.layoutChildren()

output = "/home/ga/HoudiniProjects/baseline_scene.hipnc"
hou.hipFile.save(output)
print(f"Baseline scene saved to: {output}")
PYEOF

    su - ga -c "
        export HFS='$HFS_DIR'
        cd '$HFS_DIR' && source houdini_setup 2>/dev/null && cd /
        export HOUDINI_NO_START_PAGE_SPLASH=1
        export HOUDINI_ANONYMOUS_STATISTICS=0
        export HOUDINI_NOHKEY=1
        '$HFS_DIR/bin/hython' /tmp/create_baseline.py
    " 2>&1 | tail -5 || echo "Baseline scene creation completed"

    # ================================================================
    # 6. CREATE SCENE WITH IMPORTED BUNNY FOR MATERIAL TASK
    # ================================================================
    echo "Creating scene with imported bunny for material task..."
    cat > /tmp/create_bunny_scene.py << 'PYEOF'
import hou
import os

print("Creating bunny scene...")

bunny_path = "/home/ga/HoudiniProjects/data/bunny.obj"
if not os.path.exists(bunny_path):
    print(f"WARNING: Bunny OBJ not found at {bunny_path}")
    bunny_path = ""

geo = hou.node("/obj").createNode("geo", "bunny")

if bunny_path:
    file_sop = geo.createNode("file", "import_bunny")
    file_sop.parm("file").set(bunny_path)
    xform = geo.createNode("xform", "center_scale")
    xform.setInput(0, file_sop)
    xform.parm("scale").set(5.0)
    xform.setDisplayFlag(True)
    xform.setRenderFlag(True)
else:
    torus = geo.createNode("torus")
    torus.setDisplayFlag(True)
    torus.setRenderFlag(True)

cam = hou.node("/obj").createNode("cam", "render_camera")
cam.parm("tx").set(3)
cam.parm("ty").set(2)
cam.parm("tz").set(3)
cam.parm("rx").set(-25)
cam.parm("ry").set(45)

env_light = hou.node("/obj").createNode("envlight", "env_light")
hdri_path = "/home/ga/HoudiniProjects/data/venice_sunset_1k.hdr"
if os.path.exists(hdri_path):
    env_light.parm("env_map").set(hdri_path)
    print(f"HDRI loaded: {hdri_path}")

key_light = hou.node("/obj").createNode("hlight", "key_light")
key_light.parm("tx").set(4)
key_light.parm("ty").set(6)
key_light.parm("tz").set(2)
key_light.parm("light_intensity").set(1.0)

hou.node("/obj").layoutChildren()
geo.layoutChildren()

output = "/home/ga/HoudiniProjects/bunny_scene.hipnc"
hou.hipFile.save(output)
print(f"Bunny scene saved to: {output}")
PYEOF

    su - ga -c "
        export HFS='$HFS_DIR'
        cd '$HFS_DIR' && source houdini_setup 2>/dev/null && cd /
        export HOUDINI_NO_START_PAGE_SPLASH=1
        export HOUDINI_ANONYMOUS_STATISTICS=0
        export HOUDINI_NOHKEY=1
        '$HFS_DIR/bin/hython' /tmp/create_bunny_scene.py
    " 2>&1 | tail -5 || echo "Bunny scene creation completed"

    fi  # end of HYTHON_WORKS block

    # ================================================================
    # 7. CREATE LAUNCHER SCRIPTS
    # ================================================================
    echo "Creating launcher scripts..."

    cat > /home/ga/Desktop/launch_houdini.sh << LAUNCHER_EOF
#!/bin/bash
export DISPLAY=:1
export HFS="$HFS_DIR"
cd "\$HFS" && source houdini_setup 2>/dev/null && cd /
export HOUDINI_NO_START_PAGE_SPLASH=1
export HOUDINI_ANONYMOUS_STATISTICS=0
export HOUDINI_NOHKEY=1
export HOUDINI_LMINFO_VERBOSE=0
export HOUDINI_PROMPT_ON_CRASHES=0
"\$HFS/bin/houdini" -foreground "\$@" &
LAUNCHER_EOF
    chmod +x /home/ga/Desktop/launch_houdini.sh

    # ================================================================
    # 8. CREATE UTILITY SCRIPTS
    # ================================================================
    cat > /usr/local/bin/houdini-info << 'INFO_EOF'
#!/bin/bash
echo "=== Houdini Information ==="
HFS_DIR=$(find -L /opt -maxdepth 1 -type d -name "hfs*" | sort -V | tail -1)
if [ -z "$HFS_DIR" ]; then
    echo "Houdini not found"
    exit 1
fi
export HFS="$HFS_DIR"
cd "$HFS_DIR" && source houdini_setup 2>/dev/null && cd /
"$HFS_DIR/bin/hython" -c "import hou; print('Version:', hou.applicationVersionString())" 2>/dev/null

echo ""
echo "=== Project Files ==="
ls -la /home/ga/HoudiniProjects/ 2>/dev/null

echo ""
echo "=== Data Files ==="
ls -la /home/ga/HoudiniProjects/data/ 2>/dev/null
INFO_EOF
    chmod +x /usr/local/bin/houdini-info

    cat > /usr/local/bin/houdini-query-scene << 'QUERY_EOF'
#!/bin/bash
SCENE_FILE="${1:-}"
if [ -z "$SCENE_FILE" ] || [ ! -f "$SCENE_FILE" ]; then
    echo '{"error": "File not found or not specified"}'
    exit 1
fi

HFS_DIR=$(find -L /opt -maxdepth 1 -type d -name "hfs*" | sort -V | tail -1)
export HFS="$HFS_DIR"
cd "$HFS_DIR" && source houdini_setup 2>/dev/null && cd /

"$HFS_DIR/bin/hython" -c "
import hou
import json

hou.hipFile.load('$SCENE_FILE')

nodes = []
for node in hou.node('/obj').children():
    node_info = {
        'name': node.name(),
        'type': node.type().name(),
        'position': list(node.position()),
    }
    if node.type().name() == 'geo':
        sop_children = []
        for child in node.children():
            sop_children.append({
                'name': child.name(),
                'type': child.type().name(),
            })
        node_info['children'] = sop_children
    nodes.append(node_info)

result = {
    'filename': hou.hipFile.name(),
    'node_count': len(hou.node('/obj').children()),
    'nodes': nodes,
}
print(json.dumps(result))
" 2>/dev/null
QUERY_EOF
    chmod +x /usr/local/bin/houdini-query-scene

    # ================================================================
    # 9. SET PERMISSIONS
    # ================================================================
    echo "Setting file permissions..."
    chown -R ga:ga /home/ga/
    chown -R ga:ga "$HOUDINI_USER_DIR"

    # ================================================================
    # 10. WARM-UP LAUNCH (DISMISS FIRST-RUN DIALOGS)
    # ================================================================
    echo "Performing warm-up launch to clear first-run dialogs..."

    su - ga -c "
        export DISPLAY=:1
        export HFS='$HFS_DIR'
        cd '$HFS_DIR' && source houdini_setup 2>/dev/null && cd /
        export HOUDINI_NO_START_PAGE_SPLASH=1
        export HOUDINI_ANONYMOUS_STATISTICS=0
        export HOUDINI_NOHKEY=1
        export HOUDINI_LMINFO_VERBOSE=0
        export HOUDINI_PROMPT_ON_CRASHES=0
        setsid '$HFS_DIR/bin/houdini' -foreground > /tmp/houdini_warmup.log 2>&1 &
    "

    echo "Waiting for Houdini window..."
    TIMEOUT=60
    ELAPSED=0
    while [ $ELAPSED -lt $TIMEOUT ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "houdini\|untitled\|license\|unable"; then
            echo "Houdini window detected after ${ELAPSED}s"
            break
        fi
        sleep 2
        ELAPSED=$((ELAPSED + 2))
    done

    if [ $ELAPSED -ge $TIMEOUT ]; then
        echo "WARNING: Houdini window did not appear within ${TIMEOUT}s"
        ps aux | grep -i houdini | grep -v grep || true
    fi

    sleep 3
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1

    pkill -f "houdini" 2>/dev/null || true
    sleep 2
    echo "Warm-up complete."

    # ================================================================
    # 11. LAUNCH HOUDINI WITH BASELINE SCENE
    # ================================================================
    echo "Launching Houdini with baseline scene..."

    SCENE_FILE="$PROJECTS_DIR/baseline_scene.hipnc"
    if [ ! -f "$SCENE_FILE" ]; then
        SCENE_FILE=""
    fi

    su - ga -c "
        export DISPLAY=:1
        export HFS='$HFS_DIR'
        cd '$HFS_DIR' && source houdini_setup 2>/dev/null && cd /
        export HOUDINI_NO_START_PAGE_SPLASH=1
        export HOUDINI_ANONYMOUS_STATISTICS=0
        export HOUDINI_NOHKEY=1
        export HOUDINI_LMINFO_VERBOSE=0
        export HOUDINI_PROMPT_ON_CRASHES=0
        setsid '$HFS_DIR/bin/houdini' -foreground $SCENE_FILE > /tmp/houdini.log 2>&1 &
    "

    echo "Waiting for Houdini to start..."
    TIMEOUT=60
    ELAPSED=0
    while [ $ELAPSED -lt $TIMEOUT ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "houdini\|untitled\|baseline\|license\|unable"; then
            echo "Houdini started successfully after ${ELAPSED}s"
            break
        fi
        sleep 2
        ELAPSED=$((ELAPSED + 2))
    done
    sleep 3

else
    echo "Skipping Houdini-specific steps (not installed)."
    echo "Data files are ready for when Houdini is installed."
fi

echo "=== Houdini setup complete ==="
echo "Houdini installed: $HOUDINI_INSTALLED"
echo "Project files: $PROJECTS_DIR"
ls -la "$PROJECTS_DIR" 2>/dev/null
echo "Data files: $DATA_DIR"
ls -la "$DATA_DIR" 2>/dev/null
