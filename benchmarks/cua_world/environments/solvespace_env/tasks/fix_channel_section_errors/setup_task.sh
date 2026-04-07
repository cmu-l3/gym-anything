#!/bin/bash
echo "=== Setting up fix_channel_section_errors task ==="

source /workspace/scripts/task_utils.sh

mkdir -p /home/ga/Documents/SolveSpace
chown -R ga:ga /home/ga/Documents/SolveSpace

rm -f /home/ga/Documents/SolveSpace/channel_corrected.slvs 2>/dev/null || true
rm -f /home/ga/Documents/SolveSpace/channel_draft.slvs 2>/dev/null || true

date +%s > /tmp/fix_channel_section_errors_start_ts

# Generate a C-channel cross-section .slvs with 5 pre-applied constraints,
# THREE of which contain WRONG values that must be corrected.
#
# C-channel profile (8 lines, clockwise from bottom-left, web on LEFT):
#   A=(0,0)     → B=(100,0)   req4:  bottom  [CORRECT width: 100mm]
#   B=(100,0)   → C=(100,18)  req5:  bottom-right flange [WRONG: 25 instead of 18mm]
#   C=(100,18)  → D=(20,18)   req6:  bottom inner face   [CORRECT: 80mm]
#   D=(20,18)   → E=(20,65)   req7:  web inner height    [WRONG: 32 instead of 47mm]
#   E=(20,65)   → F=(100,65)  req8:  top inner face      [80mm, not constrained directly]
#   F=(100,65)  → G=(100,83)  req9:  top-right flange    [18mm, not constrained directly]
#   G=(100,83)  → H=(0,83)    req10: top                 [100mm, not constrained directly]
#   H=(0,83)    → A=(0,0)     req11: outer wall height   [WRONG: 65 instead of 83mm]
python3 << 'PYEOF'
import os

MAGIC = b'\xb1\xb2\xb3SolveSpaceREVa'
blocks = []
blocks.append(MAGIC)

# ── Groups ──
blocks.append(b"""Group.h.v=00000001
Group.type=5000
Group.name=#references
Group.color=ff000000
Group.skipFirst=0
Group.predef.swapUV=0
Group.predef.negateU=0
Group.predef.negateV=0
Group.visible=1
Group.suppress=0
Group.relaxConstraints=0
Group.allowRedundant=0
Group.allDimsReference=0
Group.remap={
}
AddGroup""")

blocks.append(b"""Group.h.v=00000002
Group.type=5001
Group.order=1
Group.name=sketch-in-plane
Group.activeWorkplane.v=80020000
Group.color=ff000000
Group.subtype=6000
Group.skipFirst=0
Group.predef.q.w=1.000000000000000000000
Group.predef.origin.v=00010001
Group.predef.swapUV=0
Group.predef.negateU=0
Group.predef.negateV=0
Group.visible=1
Group.suppress=0
Group.relaxConstraints=0
Group.allowRedundant=0
Group.allDimsReference=0
Group.remap={
}
AddGroup""")

# ── Reference params ──
for p in [
    b"Param.h.v.=00010010\nAddParam",
    b"Param.h.v.=00010011\nAddParam",
    b"Param.h.v.=00010012\nAddParam",
    b"Param.h.v.=00010020\nParam.val=1.000000000000000000000\nAddParam",
    b"Param.h.v.=00010021\nAddParam",
    b"Param.h.v.=00010022\nAddParam",
    b"Param.h.v.=00010023\nAddParam",
    b"Param.h.v.=00020010\nAddParam",
    b"Param.h.v.=00020011\nAddParam",
    b"Param.h.v.=00020012\nAddParam",
    b"Param.h.v.=00020020\nParam.val=0.500000000000000000000\nAddParam",
    b"Param.h.v.=00020021\nParam.val=0.500000000000000000000\nAddParam",
    b"Param.h.v.=00020022\nParam.val=0.500000000000000000000\nAddParam",
    b"Param.h.v.=00020023\nParam.val=0.500000000000000000000\nAddParam",
    b"Param.h.v.=00030010\nAddParam",
    b"Param.h.v.=00030011\nAddParam",
    b"Param.h.v.=00030012\nAddParam",
    b"Param.h.v.=00030020\nParam.val=0.500000000000000000000\nAddParam",
    b"Param.h.v.=00030021\nParam.val=-0.500000000000000000000\nAddParam",
    b"Param.h.v.=00030022\nParam.val=-0.500000000000000000000\nAddParam",
    b"Param.h.v.=00030023\nParam.val=-0.500000000000000000000\nAddParam",
]:
    blocks.append(p)

def fmt(v):
    return '0' if v == 0.0 else f'{v:.21g}'

# ── C-channel geometry ──
c_channel_lines = [
    (0.0,   0.0, 100.0,  0.0),  # req4:  A→B bottom
    (100.0,  0.0, 100.0, 18.0),  # req5:  B→C bottom-right flange
    (100.0, 18.0,  20.0, 18.0),  # req6:  C→D bottom inner
    (20.0,  18.0,  20.0, 65.0),  # req7:  D→E web inner
    (20.0,  65.0, 100.0, 65.0),  # req8:  E→F top inner
    (100.0, 65.0, 100.0, 83.0),  # req9:  F→G top-right flange
    (100.0, 83.0,   0.0, 83.0),  # req10: G→H top
    (0.0,   83.0,   0.0,  0.0),  # req11: H→A outer wall
]

for i, (x0, y0, x1, y1) in enumerate(c_channel_lines):
    rn = i + 4
    ph = f'{rn:04x}'
    blocks.append(f"Param.h.v.=00{ph}0010\nParam.val={fmt(x0)}\nAddParam".encode())
    blocks.append(f"Param.h.v.=00{ph}0011\nParam.val={fmt(y0)}\nAddParam".encode())
    blocks.append(f"Param.h.v.=00{ph}0013\nParam.val={fmt(x1)}\nAddParam".encode())
    blocks.append(f"Param.h.v.=00{ph}0014\nParam.val={fmt(y1)}\nAddParam".encode())

# ── Requests ──
for n in [1, 2, 3]:
    blocks.append(f"Request.h.v={n:08x}\nRequest.type=100\nRequest.group.v=00000001\nRequest.construction=0\nAddRequest".encode())
for n in range(4, 12):
    blocks.append(f"Request.h.v={n:08x}\nRequest.type=200\nRequest.workplane.v=80020000\nRequest.group.v=00000002\nRequest.construction=0\nAddRequest".encode())

# ── Reference entities ──
for e in [
    b"""Entity.h.v=00010000
Entity.type=10000
Entity.construction=0
Entity.point[0].v=00010001
Entity.normal.v=00010020
Entity.actVisible=1
AddEntity""",
    b"""Entity.h.v=00010001
Entity.type=2000
Entity.construction=1
Entity.actVisible=1
AddEntity""",
    b"""Entity.h.v=00010020
Entity.type=3000
Entity.construction=0
Entity.point[0].v=00010001
Entity.actNormal.w=1.000000000000000000000
Entity.actVisible=1
AddEntity""",
    b"""Entity.h.v=00020000
Entity.type=10000
Entity.construction=0
Entity.point[0].v=00020001
Entity.normal.v=00020020
Entity.actVisible=1
AddEntity""",
    b"""Entity.h.v=00020001
Entity.type=2000
Entity.construction=1
Entity.actVisible=1
AddEntity""",
    b"""Entity.h.v=00020020
Entity.type=3000
Entity.construction=0
Entity.point[0].v=00020001
Entity.actNormal.w=0.500000000000000000000
Entity.actNormal.vx=0.500000000000000000000
Entity.actNormal.vy=0.500000000000000000000
Entity.actNormal.vz=0.500000000000000000000
Entity.actVisible=1
AddEntity""",
    b"""Entity.h.v=00030000
Entity.type=10000
Entity.construction=0
Entity.point[0].v=00030001
Entity.normal.v=00030020
Entity.actVisible=1
AddEntity""",
    b"""Entity.h.v=00030001
Entity.type=2000
Entity.construction=1
Entity.actVisible=1
AddEntity""",
    b"""Entity.h.v=00030020
Entity.type=3000
Entity.construction=0
Entity.point[0].v=00030001
Entity.actNormal.w=0.500000000000000000000
Entity.actNormal.vx=-0.500000000000000000000
Entity.actNormal.vy=-0.500000000000000000000
Entity.actNormal.vz=-0.500000000000000000000
Entity.actVisible=1
AddEntity""",
    b"""Entity.h.v=80020000
Entity.type=10000
Entity.construction=0
Entity.point[0].v=80020002
Entity.normal.v=80020001
Entity.actVisible=1
AddEntity""",
    b"""Entity.h.v=80020001
Entity.type=3010
Entity.construction=0
Entity.point[0].v=80020002
Entity.actNormal.w=1.000000000000000000000
Entity.actVisible=1
AddEntity""",
    b"""Entity.h.v=80020002
Entity.type=2012
Entity.construction=1
Entity.actVisible=1
AddEntity""",
]:
    blocks.append(e)

# ── Line entities ──
for i, (x0, y0, x1, y1) in enumerate(c_channel_lines):
    rn = i + 4
    ph = f'{rn:04x}'
    blocks.append(f"""Entity.h.v=00{ph}0000
Entity.type=11000
Entity.construction=0
Entity.point[0].v=00{ph}0001
Entity.point[1].v=00{ph}0002
Entity.workplane.v=80020000
Entity.actVisible=1
AddEntity""".encode())
    blocks.append(f"""Entity.h.v=00{ph}0001
Entity.type=2001
Entity.construction=0
Entity.workplane.v=80020000
Entity.actPoint.x={fmt(x0)}
Entity.actPoint.y={fmt(y0)}
Entity.actVisible=1
AddEntity""".encode())
    blocks.append(f"""Entity.h.v=00{ph}0002
Entity.type=2001
Entity.construction=0
Entity.workplane.v=80020000
Entity.actPoint.x={fmt(x1)}
Entity.actPoint.y={fmt(y1)}
Entity.actVisible=1
AddEntity""".encode())

# ── Constraints ──
ch = 1

def add_c(ctype, extra=''):
    global ch
    blocks.append(f"Constraint.h.v={ch:08x}\nConstraint.type={ctype}\nConstraint.group.v=00000002\nConstraint.workplane.v=80020000\n{extra}AddConstraint".encode())
    ch += 1

def add_dist(ptA, ptB, val):
    global ch
    blocks.append(f"""Constraint.h.v={ch:08x}
Constraint.type=30
Constraint.group.v=00000002
Constraint.workplane.v=80020000
Constraint.valA={val:.21g}
Constraint.ptA.v={ptA}
Constraint.ptB.v={ptB}
Constraint.other=0
Constraint.other2=0
AddConstraint""".encode())
    ch += 1

# COINCIDENT: close the 8-line C-channel loop
pairs = [
    ('00040002', '00050001'),  # B
    ('00050002', '00060001'),  # C
    ('00060002', '00070001'),  # D
    ('00070002', '00080001'),  # E
    ('00080002', '00090001'),  # F
    ('00090002', '000a0001'),  # G
    ('000a0002', '000b0001'),  # H
    ('000b0002', '00040001'),  # back to A
]
for ptA, ptB in pairs:
    add_c(20, f"Constraint.ptA.v={ptA}\nConstraint.ptB.v={ptB}\n")

# HORIZONTAL: req4 (A→B), req6 (C→D), req8 (E→F), req10 (G→H)
for ent in ['00040000', '00060000', '00080000', '000a0000']:
    add_c(80, f"Constraint.entityA.v={ent}\n")

# VERTICAL: req5 (B→C), req7 (D→E), req9 (F→G), req11 (H→A)
for ent in ['00050000', '00070000', '00090000', '000b0000']:
    add_c(82, f"Constraint.entityA.v={ent}\n")

# WHERE_DRAGGED: pin A=(0,0)
add_c(200, "Constraint.ptA.v=00040001\n")

# ── PRE-INJECTED DIMENSIONAL CONSTRAINTS (5 total, 3 WRONG) ──
# 1. CORRECT: A→B bottom width = 100mm
add_dist('00040001', '00040002', 100.0)

# 2. CORRECT: C→D bottom inner face width = 80mm
add_dist('00060001', '00060002', 80.0)

# 3. WRONG: H→A outer wall height = 65mm  (correct is 83mm)
add_dist('000b0001', '000b0002', 65.0)

# 4. WRONG: B→C bottom-right flange height = 25mm  (correct is 18mm)
add_dist('00050001', '00050002', 25.0)

# 5. WRONG: D→E web inner height = 32mm  (correct is 47mm)
add_dist('00070001', '00070002', 32.0)

# ── Write file ──
content = b'\n\n'.join(blocks) + b'\n'
outpath = '/home/ga/Documents/SolveSpace/channel_draft.slvs'
with open(outpath, 'wb') as f:
    f.write(content)
print(f"Generated {outpath}: {os.path.getsize(outpath)} bytes")
PYEOF

chown ga:ga /home/ga/Documents/SolveSpace/channel_draft.slvs

# ── Approved drawing revision on desktop ──
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/channel_approved_drawing.txt << 'SPECEOF'
ENGINEERING DRAWING REVISION NOTICE
Drawing No:  CC-2024-088
Part:        Standard C-channel section (structural)
Revision:    REV-D  (supersedes REV-C)
Date:        2024-11-03
Revised by:  Engineering Drawing Office

APPROVED CROSS-SECTION DIMENSIONS (all in mm):
  Overall flange width (outer):     100 mm
  Flange thickness (top and bottom): 18 mm  [EACH flange]
  Inner flange clear width:          80 mm
  Web inner height:                  47 mm  (between inner flange surfaces)
  Section outer height (total):      83 mm

ERRORS FOUND IN CURRENT CAD FILE (REV-C values — INCORRECT):
  * Section outer height:   currently shows  65 mm  — must be  83 mm
  * Flange thickness:       currently shows  25 mm  — must be  18 mm
  * Web inner height:       currently shows  32 mm  — must be  47 mm

ACTION REQUIRED:
  Correct all three erroneous constraint values in channel_draft.slvs.
  Do not modify the two constraints that are already correct.
  Save the corrected file as:  channel_corrected.slvs

Note: This revision corrects errors from the first-article inspection report.
Tolerance: ±0.3 mm (structural channel, welded assembly)
SPECEOF
chown ga:ga /home/ga/Desktop/channel_approved_drawing.txt

kill_solvespace
launch_solvespace "/home/ga/Documents/SolveSpace/channel_draft.slvs"

echo "Waiting for SolveSpace to load channel_draft.slvs..."
wait_for_solvespace 30
sleep 5

maximize_solvespace
sleep 1

take_screenshot /tmp/fix_channel_section_errors_start.png
echo "=== fix_channel_section_errors setup complete ==="
echo "C-channel draft loaded with pre-applied dimensional constraints (some incorrect)."
echo "Approved drawing revision at /home/ga/Desktop/channel_approved_drawing.txt"
