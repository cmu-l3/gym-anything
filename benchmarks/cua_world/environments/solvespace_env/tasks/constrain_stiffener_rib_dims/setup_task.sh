#!/bin/bash
echo "=== Setting up constrain_stiffener_rib_dims task ==="

source /workspace/scripts/task_utils.sh

mkdir -p /home/ga/Documents/SolveSpace
chown -R ga:ga /home/ga/Documents/SolveSpace

rm -f /home/ga/Documents/SolveSpace/stiffener_constrained.slvs 2>/dev/null || true
rm -f /home/ga/Documents/SolveSpace/stiffener_profile.slvs 2>/dev/null || true

date +%s > /tmp/constrain_stiffener_rib_dims_start_ts

# Generate a web stiffener rib (stepped gusset plate) cross-section .slvs
# with geometry and topological constraints only — NO dimensional constraints.
# The agent must read the fabrication drawing and apply all 6 constraints.
#
# Stiffener rib profile (6 lines, clockwise from bottom-left A):
#   A=(0,0)     → B=(130,0)   req4: overall base   [130mm]
#   B=(130,0)   → C=(130,25)  req5: bottom ledge   [25mm]
#   C=(130,25)  → D=(100,25)  req6: notch step in  [30mm, 130-100=30]
#   D=(100,25)  → E=(100,70)  req7: web height     [45mm, 70-25=45]
#   E=(100,70)  → F=(0,70)    req8: top edge       [100mm]
#   F=(0,70)    → A=(0,0)     req9: left side      [70mm]
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

# ── Stiffener rib geometry ──
stiffener_lines = [
    (0.0,   0.0, 130.0,  0.0),  # req4: A→B overall base
    (130.0,  0.0, 130.0, 25.0),  # req5: B→C bottom ledge
    (130.0, 25.0, 100.0, 25.0),  # req6: C→D notch step in
    (100.0, 25.0, 100.0, 70.0),  # req7: D→E web height
    (100.0, 70.0,   0.0, 70.0),  # req8: E→F top edge
    (0.0,   70.0,   0.0,  0.0),  # req9: F→A left side
]

for i, (x0, y0, x1, y1) in enumerate(stiffener_lines):
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
for i, (x0, y0, x1, y1) in enumerate(stiffener_lines):
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

# COINCIDENT: close the 6-line stiffener loop
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

# ── Write file (NO dimensional constraints — agent must add them) ──
content = b'\n\n'.join(blocks) + b'\n'
outpath = '/home/ga/Documents/SolveSpace/stiffener_profile.slvs'
with open(outpath, 'wb') as f:
    f.write(content)
print(f"Generated {outpath}: {os.path.getsize(outpath)} bytes")
PYEOF

chown ga:ga /home/ga/Documents/SolveSpace/stiffener_profile.slvs

# ── Fabrication drawing on desktop ──
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/stiffener_fabrication_drawing.txt << 'SPECEOF'
FABRICATION DRAWING — WEB STIFFENER PLATE
Drawing No:    WSP-2024-112-A
Part:          Column-to-beam connection gusset stiffener
Material:      10mm mild steel plate (S355 grade)
Surface:       Hot-rolled, mill scale acceptable on concealed faces
Application:   Intermediate web stiffener, portal frame haunch

PLATE DIMENSIONS (all in mm, tolerance ±0.5 mm):
  Overall base length:     130 mm  (full base of plate, from left to right)
  Bottom ledge height:      25 mm  (stepped cutback at bottom-right corner)
  Ledge horizontal depth:   30 mm  (horizontal distance of the step)
  Web height above ledge:   45 mm  (vertical from ledge level to top)
  Top edge length:         100 mm  (upper edge of plate)
  Total plate height:       70 mm  (overall height, left face)

CONSTRAINT REQUIREMENT:
  All six dimensional constraints listed above must be applied to the 2D
  profile sketch before the file is released for plasma cutting and fitting.

Save the constrained file as:  stiffener_constrained.slvs

Issued by: Structural Steelwork Division
Reference: Column schedule drawing STE-2024-089, connection type C3
SPECEOF
chown ga:ga /home/ga/Desktop/stiffener_fabrication_drawing.txt

kill_solvespace
launch_solvespace "/home/ga/Documents/SolveSpace/stiffener_profile.slvs"

echo "Waiting for SolveSpace to load stiffener_profile.slvs..."
wait_for_solvespace 30
sleep 5

maximize_solvespace
sleep 1

take_screenshot /tmp/constrain_stiffener_rib_dims_start.png
echo "=== constrain_stiffener_rib_dims setup complete ==="
echo "Stiffener rib loaded: 6 lines, H/V/coincident constraints only, NO dimensional constraints."
echo "Fabrication drawing at /home/ga/Desktop/stiffener_fabrication_drawing.txt"
