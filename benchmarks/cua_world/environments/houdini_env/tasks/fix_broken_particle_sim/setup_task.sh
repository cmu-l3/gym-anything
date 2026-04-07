#!/bin/bash
echo "=== Setting up fix_broken_particle_sim task ==="

# Source utilities
source /workspace/scripts/task_utils.sh
setup_houdini_env

HFS_DIR=$(get_hfs_dir)

# ================================================================
# CREATE THE BROKEN PARTICLE SCENE WITH 4 INJECTED ERRORS
# ================================================================
BROKEN_SCENE="/home/ga/HoudiniProjects/broken_particles.hipnc"
OUTPUT_SCENE="/home/ga/HoudiniProjects/fixed_particles.hipnc"

mkdir -p /home/ga/HoudiniProjects
rm -f "$BROKEN_SCENE" "$OUTPUT_SCENE"

echo "Creating broken particle simulation scene with injected errors..."

"$HFS_DIR/bin/hython" -c "
import hou

# ============================================================
# Create emitter geometry (sphere raised above ground)
# ============================================================
emitter = hou.node('/obj').createNode('geo', 'emitter_geo')
sphere = emitter.createNode('sphere', 'source_shape')
sphere.parm('radx').set(0.5)
sphere.parm('rady').set(0.5)
sphere.parm('radz').set(0.5)
xform = emitter.createNode('xform', 'raise_source')
xform.setInput(0, sphere)
xform.parm('ty').set(5.0)
xform.setDisplayFlag(True)
xform.setRenderFlag(True)

# ============================================================
# Create ground plane collision geometry
# ============================================================
ground = hou.node('/obj').createNode('geo', 'ground_plane')
grid = ground.createNode('grid', 'ground')
grid.parm('sizex').set(20)
grid.parm('sizey').set(20)
grid.parm('rows').set(2)
grid.parm('cols').set(2)
null_out = ground.createNode('null', 'OUT')
null_out.setInput(0, grid)
null_out.setDisplayFlag(True)
null_out.setRenderFlag(True)

# ============================================================
# Create DOP network with particle simulation
# ============================================================
dopnet = hou.node('/obj').createNode('dopnet', 'particle_sim')

# POP solver
pop_solver = dopnet.createNode('popsolver', 'popsolver1')

# POP source
pop_source = dopnet.createNode('popsource', 'emitter')
pop_source.parm('emittype').set(0)  # From surface
pop_source.parm('soppath').set('/obj/emitter_geo/raise_source')
# ERROR 2: Set birth rate to 0 (no particles will be generated)
pop_source.parm('const_birth_rate').set(0)

pop_solver.setInput(0, pop_source)

# POP Force (gravity)
pop_force = dopnet.createNode('popforce', 'gravity_force')
# ERROR 1: Wrong gravity direction (positive Y = particles fly UP)
pop_force.parm('forcey').set(9.81)

pop_solver.setInput(1, pop_force)

# POP Collision Detect
pop_collision = dopnet.createNode('popcollisiondetect', 'ground_collision')
# ERROR 3: Reference non-existent SOP path (should be /obj/ground_plane/OUT)
pop_collision.parm('soppath').set('/obj/collision_geo/OUT')

pop_solver.setInput(2, pop_collision)

# ERROR 4: Set DOP substeps to 0 (invalid, simulation cannot advance)
dopnet.parm('substep').set(0)

# Layout all nodes neatly
dopnet.layoutChildren()
emitter.layoutChildren()
ground.layoutChildren()
hou.node('/obj').layoutChildren()

hou.hipFile.save('$BROKEN_SCENE')
print('Broken particle scene created.')
" 2>&1

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create broken particle scene"
    exit 1
fi

echo "Broken scene created: $(du -h "$BROKEN_SCENE" | cut -f1)"

# ================================================================
# DELETE STALE OUTPUT FILES
# ================================================================
rm -f "$OUTPUT_SCENE"
rm -rf /home/ga/HoudiniProjects/particle_cache 2>/dev/null || true

# Ensure proper ownership
chown -R ga:ga /home/ga/HoudiniProjects/

# ================================================================
# RECORD INITIAL STATE WITH ALL ERROR VALUES
# ================================================================
INITIAL_INFO=$("$HFS_DIR/bin/hython" -c "
import hou
import json

hou.hipFile.load('$BROKEN_SCENE')

result = {
    'errors': {}
}

# Check gravity force
grav = hou.node('/obj/particle_sim/gravity_force')
if grav:
    result['errors']['gravity_forcey'] = grav.parm('forcey').eval()

# Check birth rate
emitter = hou.node('/obj/particle_sim/emitter')
if emitter:
    result['errors']['birth_rate'] = emitter.parm('const_birth_rate').eval()

# Check collision path
collision = hou.node('/obj/particle_sim/ground_collision')
if collision:
    result['errors']['collision_soppath'] = collision.parm('soppath').eval()

# Check substeps
dopnet = hou.node('/obj/particle_sim')
if dopnet:
    result['errors']['substeps'] = dopnet.parm('substep').eval()

print(json.dumps(result))
" 2>/dev/null || echo '{"errors": {}}')

cat > /tmp/initial_state.json << EOF
{
    "source_scene": "$BROKEN_SCENE",
    "output_scene": "$OUTPUT_SCENE",
    "initial_errors": $INITIAL_INFO,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state saved to /tmp/initial_state.json"
cat /tmp/initial_state.json

# ================================================================
# LAUNCH HOUDINI WITH THE BROKEN SCENE
# ================================================================
kill_houdini

launch_houdini "$BROKEN_SCENE"
wait_for_houdini_window 60

# Focus and maximize
sleep 2
focus_houdini
sleep 1
maximize_houdini
sleep 1

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Task: Fix all 4 errors in the particle simulation, cache 48+ frames, save as $OUTPUT_SCENE"
