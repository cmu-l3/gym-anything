#!/bin/bash
echo "=== Setting up correct_mounting_plate_rev_b task ==="

source /workspace/scripts/task_utils.sh

mkdir -p /home/ga/Documents/SolveSpace
chown -R ga:ga /home/ga/Documents/SolveSpace

rm -f /home/ga/Documents/SolveSpace/plate_rev_b.slvs 2>/dev/null || true
rm -f /home/ga/Documents/SolveSpace/plate_rev_a.slvs 2>/dev/null || true

date +%s > /tmp/correct_mounting_plate_rev_b_start_ts

# Generate an instrument mounting plate cross-section .slvs with 6 pre-applied
# constraints, THREE of which contain WRONG values matching REV-A (superseded).
# The agent must apply the Engineering Change Order and correct the wrong values.
#
# Mounting plate profile (6 lines, clockwise from bottom-left):
#   A=(0,0)     → B=(160,0)   req4: bottom         [WRONG: 120, correct: 160mm]
#   B=(160,0)   → C=(160,100) req5: right side      [WRONG:  75, correct: 100mm]
#   C=(160,100) → D=(110,100) req6: top-right step  [WRONG:  35, correct:  50mm]
#   D=(110,100) → E=(110,60)  req7: cutout depth    [CORRECT: 40mm]
#   E=(110,60)  → F=(0,60)    req8: inner horiz.    [CORRECT: 110mm]
#   F=(0,60)    → A=(0,0)     req9: left side       [CORRECT: 60mm]
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

# ── Mounting plate geometry (REV-B correct geometry) ──
plate_lines = [
    (0.0,   0.0, 160.0,   0.0),  # req4: A→B bottom
    (160.0,  0.0, 160.0, 100.0),  # req5: B→C right side
    (160.0,100.0, 110.0, 100.0),  # req6: C→D top-right step
    (110.0,100.0, 110.0,  60.0),  # req7: D→E cutout depth
    (110.0, 60.0,   0.0,  60.0),  # req8: E→F inner horizontal
    (0.0,   60.0,   0.0,   0.0),  # req9: F→A left side
]

for i, (x0, y0, x1, y1) in enumerate(plate_lines):
    rn = i + 4
    ph = f'{rn:04x}'
    blocks.append(f"Param.h.v.=00{ph}0010\nParam.val={fmt(x0)}\nAddParam".encode())
    blocks.append(f"Param.h.v.=00{ph}0011\nParam.val={fmt(y0)}\nAddParam".encode())
    blocks.append(f"Param.h.v.=00{ph}0013\nParam.val={fmt(x1)}\nAddParam".encode())
    blocks.append(f"Param.h.v.=00{ph}0014\nParam.val={fmt(y1)}\nAddParam".encode())

# ── Requests ──
for n in [1, 2, 3]:
    blocks.append(f"Request.h.v={n:08x}\nRequest.type=100\nRequest.group.v=00000001\nRequest.construction=0\nAddRequest".encode())
for n in range(4, 10):
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
for i, (x0, y0, x1, y1) in enumerate(plate_lines):
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

# COINCIDENT: close the 6-line plate loop
pairs = [
    ('00040002', '00050001'),  # B
    ('00050002', '00060001'),  # C
    ('00060002', '00070001'),  # D
    ('00070002', '00080001'),  # E
    ('00080002', '00090001'),  # F
    ('00090002', '00040001'),  # back to A
]
for ptA, ptB in pairs:
    add_c(20, f"Constraint.ptA.v={ptA}\nConstraint.ptB.v={ptB}\n")

# HORIZONTAL: req4 (A→B), req6 (C→D), req8 (E→F)
for ent in ['00040000', '00060000', '00080000']:
    add_c(80, f"Constraint.entityA.v={ent}\n")

# VERTICAL: req5 (B→C), req7 (D→E), req9 (F→A)
for ent in ['00050000', '00070000', '00090000']:
    add_c(82, f"Constraint.entityA.v={ent}\n")

# WHERE_DRAGGED: pin A=(0,0)
add_c(200, "Constraint.ptA.v=00040001\n")

# ── PRE-INJECTED DIMENSIONAL CONSTRAINTS (6 total, 3 WRONG from REV-A) ──
# 1. WRONG: A→B bottom width = 120mm  (REV-A value; correct REV-B = 160mm)
add_dist('00040001', '00040002', 120.0)

# 2. WRONG: B→C right side height = 75mm  (REV-A value; correct REV-B = 100mm)
add_dist('00050001', '00050002', 75.0)

# 3. WRONG: C→D top-right step = 35mm  (REV-A value; correct REV-B = 50mm)
add_dist('00060001', '00060002', 35.0)

# 4. CORRECT: D→E cutout depth = 40mm  (unchanged in REV-B)
add_dist('00070001', '00070002', 40.0)

# 5. CORRECT: E→F inner horizontal = 110mm  (unchanged in REV-B)
add_dist('00080001', '00080002', 110.0)

# 6. CORRECT: F→A left side = 60mm  (unchanged in REV-B)
add_dist('00090001', '00090002', 60.0)

# ── Write file ──
content = b'\n\n'.join(blocks) + b'\n'
outpath = '/home/ga/Documents/SolveSpace/plate_rev_a.slvs'
with open(outpath, 'wb') as f:
    f.write(content)
print(f"Generated {outpath}: {os.path.getsize(outpath)} bytes")
PYEOF

chown ga:ga /home/ga/Documents/SolveSpace/plate_rev_a.slvs

# ── Engineering Change Order on desktop ──
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/engineering_change_order.txt << 'SPECEOF'
ENGINEERING CHANGE ORDER
ECO No:   ECO-2024-0856
Part:     Instrument Mounting Plate (IMP-440)
Drawing:  IMP-440-DWG
Change authority: Chief Design Engineer
Issue date: 2024-10-22

REASON FOR CHANGE:
  Dimensional errors identified during first-article inspection.
  The current CAD file (plate_rev_a.slvs) retains superseded REV-A values.
  This ECO updates three dimensions to match REV-B production requirements.

INCORRECT VALUES (REV-A — currently in the CAD file):
  Overall plate width (bottom):   120 mm  ← WRONG
  Overall plate height (right):    75 mm  ← WRONG
  Top-right corner step width:     35 mm  ← WRONG

CORRECT VALUES (REV-B — must replace the above):
  Overall plate width (bottom):   160 mm
  Overall plate height (right):   100 mm
  Top-right corner step width:     50 mm

DIMENSIONS CONFIRMED CORRECT — DO NOT CHANGE:
  Corner cutout vertical depth:    40 mm  (keep as-is)
  Inner horizontal edge:          110 mm  (keep as-is)
  Left edge height:                60 mm  (keep as-is)

ACTION:
  Open plate_rev_a.slvs in SolveSpace.
  Locate and correct ONLY the three erroneous constraint values.
  Do not modify the three constraints that are already correct.
  Save the corrected file as:  plate_rev_b.slvs

Authorised by: ___________________  Date: 2024-10-22
SPECEOF
chown ga:ga /home/ga/Desktop/engineering_change_order.txt

kill_solvespace
launch_solvespace "/home/ga/Documents/SolveSpace/plate_rev_a.slvs"

echo "Waiting for SolveSpace to load plate_rev_a.slvs..."
wait_for_solvespace 30
sleep 5

maximize_solvespace
sleep 1

take_screenshot /tmp/correct_mounting_plate_rev_b_start.png
echo "=== correct_mounting_plate_rev_b setup complete ==="
echo "Mounting plate REV-A loaded with pre-applied dimensional constraints requiring ECO revision."
echo "Engineering Change Order at /home/ga/Desktop/engineering_change_order.txt"
