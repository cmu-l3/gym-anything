#!/bin/bash
echo "=== Exporting fix_broken_particle_sim result ==="

# Source utilities
source /workspace/scripts/task_utils.sh
setup_houdini_env

# Take final screenshot
take_screenshot /tmp/task_end.png

OUTPUT_SCENE="/home/ga/HoudiniProjects/fixed_particles.hipnc"
SOURCE_SCENE="/home/ga/HoudiniProjects/broken_particles.hipnc"
HFS_DIR=$(get_hfs_dir)

# ================================================================
# CHECK OUTPUT SCENE FILE
# ================================================================
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_SCENE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_SCENE" 2>/dev/null || echo "0")
fi

# ================================================================
# ANALYZE SCENE WITH HYTHON
# ================================================================
# Determine which scene to analyze - prefer fixed scene, fall back to source
ANALYZE_SCENE="$OUTPUT_SCENE"
if [ "$OUTPUT_EXISTS" = "false" ]; then
    # If no fixed scene, analyze the source (may still have been modified in-place)
    if [ -f "$SOURCE_SCENE" ]; then
        ANALYZE_SCENE="$SOURCE_SCENE"
    fi
fi

SCENE_ANALYSIS=""
if [ -f "$ANALYZE_SCENE" ]; then
    SCENE_ANALYSIS=$("$HFS_DIR/bin/hython" -c "
import hou
import json
import sys

hou.hipFile.load('$ANALYZE_SCENE')

result = {
    'scene_loaded': True,
    'gravity_values': [],
    'birth_rates': [],
    'collision_paths': [],
    'collision_path_valid': [],
    'substeps': None,
    'particle_count_frame24': 0,
    'particle_count_frame48': 0,
    'sim_error': None,
}

# ============================================================
# Find all DOP networks and check parameters
# ============================================================
for obj_node in hou.node('/obj').children():
    if obj_node.type().name() == 'dopnet':
        # Check substeps
        substep_parm = obj_node.parm('substep')
        if substep_parm:
            result['substeps'] = substep_parm.eval()

        # Scan DOP children for POP nodes
        for dop_child in obj_node.children():
            type_name = dop_child.type().name()

            # Check POP Force nodes for gravity
            if type_name == 'popforce':
                fy = dop_child.parm('forcey')
                if fy:
                    result['gravity_values'].append({
                        'node': dop_child.path(),
                        'forcey': fy.eval(),
                    })

            # Check POP Source nodes for birth rate
            if type_name == 'popsource':
                br = dop_child.parm('const_birth_rate')
                if br:
                    result['birth_rates'].append({
                        'node': dop_child.path(),
                        'const_birth_rate': br.eval(),
                    })

            # Check POP Collision Detect for SOP path
            if type_name == 'popcollisiondetect':
                sp = dop_child.parm('soppath')
                if sp:
                    sop_path_val = sp.eval()
                    valid = hou.node(sop_path_val) is not None
                    result['collision_paths'].append({
                        'node': dop_child.path(),
                        'soppath': sop_path_val,
                        'valid': valid,
                    })
                    result['collision_path_valid'].append(valid)

# ============================================================
# Attempt simulation to check particle generation
# ============================================================
try:
    # Only attempt sim if substeps > 0 to avoid infinite loops
    if result['substeps'] is not None and result['substeps'] > 0:
        hou.setFrame(1)
        # Advance to frame 24
        for f in range(1, 25):
            hou.setFrame(f)

        # Count particles at frame 24
        for obj_node in hou.node('/obj').children():
            if obj_node.type().name() == 'dopnet':
                disp = obj_node.displayNode()
                if disp:
                    try:
                        geo = disp.geometry()
                        if geo:
                            result['particle_count_frame24'] = len(geo.points())
                    except:
                        pass
                # Also try reading from the DOP import
                try:
                    dop_io = obj_node.node('import')
                    if not dop_io:
                        # Look for any DOP I/O or output node
                        for ch in obj_node.children():
                            if ch.type().name() in ('dopimport', 'dopio', 'output'):
                                dop_io = ch
                                break
                except:
                    pass

        # Advance to frame 48
        for f in range(25, 49):
            hou.setFrame(f)

        # Count particles at frame 48
        for obj_node in hou.node('/obj').children():
            if obj_node.type().name() == 'dopnet':
                disp = obj_node.displayNode()
                if disp:
                    try:
                        geo = disp.geometry()
                        if geo:
                            result['particle_count_frame48'] = len(geo.points())
                    except:
                        pass
    else:
        result['sim_error'] = 'substeps is 0 or None, cannot simulate'
except Exception as e:
    result['sim_error'] = str(e)

print(json.dumps(result))
" 2>/dev/null || echo '{"scene_loaded": false, "sim_error": "hython failed"}')
fi

# ================================================================
# PARSE ANALYSIS RESULTS
# ================================================================
GRAVITY_Y="9.81"
BIRTH_RATE="0"
COLLISION_PATH="/obj/collision_geo/OUT"
COLLISION_VALID="false"
SUBSTEPS="0"
PARTICLE_COUNT_24="0"
PARTICLE_COUNT_48="0"
SIM_ERROR="none"
SCENE_LOADED="false"

if [ -n "$SCENE_ANALYSIS" ]; then
    SCENE_LOADED=$(echo "$SCENE_ANALYSIS" | python3 -c "import json, sys; d=json.load(sys.stdin); print('true' if d.get('scene_loaded') else 'false')" 2>/dev/null || echo "false")

    GRAVITY_Y=$(echo "$SCENE_ANALYSIS" | python3 -c "
import json, sys
d = json.load(sys.stdin)
gv = d.get('gravity_values', [])
if gv:
    print(gv[0].get('forcey', 9.81))
else:
    print(9.81)
" 2>/dev/null || echo "9.81")

    BIRTH_RATE=$(echo "$SCENE_ANALYSIS" | python3 -c "
import json, sys
d = json.load(sys.stdin)
br = d.get('birth_rates', [])
if br:
    print(br[0].get('const_birth_rate', 0))
else:
    print(0)
" 2>/dev/null || echo "0")

    COLLISION_PATH=$(echo "$SCENE_ANALYSIS" | python3 -c "
import json, sys
d = json.load(sys.stdin)
cp = d.get('collision_paths', [])
if cp:
    print(cp[0].get('soppath', '/obj/collision_geo/OUT'))
else:
    print('/obj/collision_geo/OUT')
" 2>/dev/null || echo "/obj/collision_geo/OUT")

    COLLISION_VALID=$(echo "$SCENE_ANALYSIS" | python3 -c "
import json, sys
d = json.load(sys.stdin)
cv = d.get('collision_path_valid', [])
if cv:
    print('true' if cv[0] else 'false')
else:
    print('false')
" 2>/dev/null || echo "false")

    SUBSTEPS=$(echo "$SCENE_ANALYSIS" | python3 -c "
import json, sys
d = json.load(sys.stdin)
s = d.get('substeps')
print(s if s is not None else 0)
" 2>/dev/null || echo "0")

    PARTICLE_COUNT_24=$(echo "$SCENE_ANALYSIS" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d.get('particle_count_frame24', 0))
" 2>/dev/null || echo "0")

    PARTICLE_COUNT_48=$(echo "$SCENE_ANALYSIS" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d.get('particle_count_frame48', 0))
" 2>/dev/null || echo "0")

    SIM_ERROR=$(echo "$SCENE_ANALYSIS" | python3 -c "
import json, sys
d = json.load(sys.stdin)
e = d.get('sim_error')
# Sanitize for safe JSON embedding (strip quotes, newlines)
s = str(e) if e else 'none'
s = s.replace('\"', '').replace('\\\\', '').replace('\\n', ' ')[:200]
print(s)
" 2>/dev/null || echo "none")
fi

# ================================================================
# CHECK FOR CACHED FRAMES
# ================================================================
CACHED_FRAMES="0"

# Check common cache locations
for cache_dir in \
    /home/ga/HoudiniProjects/particle_cache \
    /home/ga/HoudiniProjects/cache \
    /tmp/particle_cache \
    /home/ga/houdini20.5/cache; do
    if [ -d "$cache_dir" ]; then
        frame_count=$(find "$cache_dir" -type f \( -name "*.bgeo" -o -name "*.bgeo.sc" -o -name "*.sim" -o -name "*.bgeo.gz" \) 2>/dev/null | wc -l)
        if [ "$frame_count" -gt "$CACHED_FRAMES" ]; then
            CACHED_FRAMES="$frame_count"
        fi
    fi
done

# If simulation ran successfully with particles, that counts as cached in memory
# The particle_count at frame 48 > 0 implies frames were simulated
if [ "$PARTICLE_COUNT_48" -gt "0" ]; then
    if [ "$CACHED_FRAMES" -eq "0" ]; then
        # Simulation ran in memory; mark as having at least 48 frames if we got to frame 48
        CACHED_FRAMES="48"
    fi
fi

# ================================================================
# CHECK HOUDINI STATE
# ================================================================
HOUDINI_RUNNING="false"
if is_houdini_running | grep -q "true"; then
    HOUDINI_RUNNING="true"
fi

# ================================================================
# CREATE RESULT JSON
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "output_size_bytes": $OUTPUT_SIZE,
    "output_path": "$OUTPUT_SCENE",
    "scene_loaded": $SCENE_LOADED,
    "gravity_forcey": $GRAVITY_Y,
    "birth_rate": $BIRTH_RATE,
    "collision_soppath": "$COLLISION_PATH",
    "collision_path_valid": $COLLISION_VALID,
    "substeps": $SUBSTEPS,
    "particle_count_frame24": $PARTICLE_COUNT_24,
    "particle_count_frame48": $PARTICLE_COUNT_48,
    "cached_frames": $CACHED_FRAMES,
    "sim_error": "$SIM_ERROR",
    "houdini_was_running": $HOUDINI_RUNNING,
    "screenshot_path": "/tmp/task_end.png",
    "initial_screenshot_path": "/tmp/task_start.png",
    "raw_analysis": $(if [ -n "$SCENE_ANALYSIS" ]; then echo "$SCENE_ANALYSIS" | head -c 4000; else echo '{}'; fi),
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="
