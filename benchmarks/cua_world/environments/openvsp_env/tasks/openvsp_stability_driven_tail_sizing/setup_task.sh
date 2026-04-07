#!/bin/bash
# Setup script for openvsp_stability_driven_tail_sizing task
# Creates an undersized-tail variant of eCRM-001 and writes the task specification.

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_stability_driven_tail_sizing ==="

# Ensure directories
mkdir -p "$MODELS_DIR"
mkdir -p "$EXPORTS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Copy base eCRM-001 model
cp /workspace/data/eCRM-001_wing_tail.vsp3 "$MODELS_DIR/ecrm_unstable.vsp3"
chmod 644 "$MODELS_DIR/ecrm_unstable.vsp3"

# ---------- Reduce horizontal tail to ~50% area ----------
# Scale all linear dimensions (span, chord) by 0.707 = sqrt(0.5)
# This preserves aspect ratio while halving the planform area.
python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import sys

filepath = '/home/ga/Documents/OpenVSP/ecrm_unstable.vsp3'
SCALE = 0.707          # linear scale factor: sqrt(0.5)
AREA_SCALE = 0.5       # area scale factor: 0.707^2

# In eCRM-001 .vsp3 XML, parameters are stored as individual tags
# (e.g. <TotalSpan Value="192.0" ID="...">) not <Parm Name="TotalSpan">.
LINEAR_TAGS = {'Span', 'Root_Chord', 'Tip_Chord', 'Chord',
               'TotalSpan', 'TotalProjectedSpan', 'ProjectedSpan',
               'TotalChord', 'Avg_Chord'}
AREA_TAGS   = {'TotalArea', 'Area'}

try:
    tree = ET.parse(filepath)
    root = tree.getroot()

    # Locate the Tail WingGeom component
    tail_geom = None
    for geom in root.iter('Geom'):
        for name_el in geom.iter('Name'):
            if name_el.text and name_el.text.strip() == 'Tail':
                tail_geom = geom
                break
        if tail_geom is not None:
            break

    if tail_geom is None:
        print("WARNING: Could not find Tail component", file=sys.stderr)
        sys.exit(0)

    modified = 0
    for elem in tail_geom.iter():
        if 'Value' not in elem.attrib:
            continue
        try:
            val = float(elem.get('Value'))
        except (ValueError, TypeError):
            continue

        # Scale linear dimensions (skip tiny centerline-stub values <= 1.5)
        if elem.tag in LINEAR_TAGS and val > 1.5:
            elem.set('Value', f'{val * SCALE:.15e}')
            modified += 1

        # Scale area dimensions
        elif elem.tag in AREA_TAGS and val > 1.5:
            elem.set('Value', f'{val * AREA_SCALE:.15e}')
            modified += 1

    tree.write(filepath, xml_declaration=True)
    print(f"Modified {modified} Tail parameters (scale={SCALE})")

except Exception as e:
    print(f"Error modifying tail: {e}", file=sys.stderr)
PYEOF

chown ga:ga "$MODELS_DIR/ecrm_unstable.vsp3"

# ---------- Write task specification ----------
cat > /home/ga/Desktop/stability_task_spec.txt << 'SPEC_EOF'
STABILITY-DRIVEN HORIZONTAL TAIL SIZING
========================================

BACKGROUND:
The eCRM-001 model (ecrm_unstable.vsp3) has been modified
with an undersized horizontal tail (~50% of original area).
The aircraft is likely longitudinally unstable.

OBJECTIVE:
Determine the correct horizontal tail size to achieve a
static margin between 10% and 20%, implement the change,
and verify with VSPAero analysis.

FLIGHT CONDITION FOR ANALYSIS:
  CG X-Location  : 28.5  (set in VSPAero Reference tab)
  Mach Number     : 0.3
  Analysis Points : Alpha = 0 deg and Alpha = 6 deg
  Analysis Type   : VLM (Vortex Lattice Method)

STATIC MARGIN FORMULAS:
  CL_alpha  = (CL_at_6deg - CL_at_0deg) / 6.0
  CM_alpha  = (CMy_at_6deg - CMy_at_0deg) / 6.0
  Static Margin (%) = -(CM_alpha / CL_alpha) * 100

  Stable aircraft: CM_alpha < 0 means Static Margin > 0
  Target range: 10% <= Static Margin <= 20%

TAIL RESIZING METHOD:
  Scale the horizontal tail's Span AND Root/Tip Chord
  proportionally to preserve Aspect Ratio.
  If static margin is too low, increase tail area.
  If static margin is too high, decrease tail area.

WORKFLOW:
  1. Open Analysis > VSPAero
  2. In the Overview tab, set Mach = 0.3
  3. In the Reference tab, set Xcg = 28.5
  4. Configure alpha sweep: Start=0, End=6, Npts=2
  5. Click "Start" to run the VLM solver
  6. In Results Manager, read CL and CMy at alpha=0 and alpha=6
  7. Calculate static margin using formulas above
  8. If outside [10%, 20%], resize tail and re-run analysis

DELIVERABLES:
  1. Save final model as:
     /home/ga/Documents/OpenVSP/stability_restored.vsp3

  2. Write report to:
     /home/ga/Desktop/stability_report.txt

REPORT FORMAT:
  Iteration 0 (Baseline - undersized tail):
    Tail Span = _____, Root Chord = _____
    CL_alpha = _____, CM_alpha = _____
    Static Margin = _____%

  Iteration 1:
    Tail Span = _____, Root Chord = _____
    CL_alpha = _____, CM_alpha = _____
    Static Margin = _____%

  [Additional iterations as needed]

  Final Static Margin = _____% (target: 10-20%)
SPEC_EOF

chown ga:ga /home/ga/Desktop/stability_task_spec.txt
chmod 644 /home/ga/Desktop/stability_task_spec.txt

# ---------- Clean stale outputs ----------
rm -f "$MODELS_DIR/stability_restored.vsp3"
rm -f /home/ga/Desktop/stability_report.txt
rm -f /tmp/openvsp_stability_sizing_result.json

# Remove stale VSPAero output files
find "$MODELS_DIR" \( -name "*.polar" -o -name "*.lod" \
     -o -name "*.history" -o -name "*.adb" \) \
     2>/dev/null | xargs rm -f 2>/dev/null || true

# ---------- Record task start timestamp ----------
date +%s > /tmp/task_start_timestamp

# ---------- Kill any running OpenVSP and launch ----------
kill_openvsp

launch_openvsp "$MODELS_DIR/ecrm_unstable.vsp3"
WID=$(wait_for_openvsp 60)
if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    take_screenshot /tmp/task_start_screenshot.png
    echo "OpenVSP launched successfully with undersized-tail model."
else
    echo "WARNING: OpenVSP window did not appear"
    take_screenshot /tmp/task_start_screenshot.png
fi

echo "=== Setup complete ==="
