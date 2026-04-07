#!/bin/bash
echo "=== Setting up pipe_support_flange_repair task ==="

source /workspace/scripts/task_utils.sh

mkdir -p /home/ga/Documents/SolveSpace
chown -R ga:ga /home/ga/Documents/SolveSpace

rm -f /home/ga/Documents/SolveSpace/flange_corrected.slvs 2>/dev/null || true
rm -f /home/ga/Documents/SolveSpace/flange_corrected.dxf 2>/dev/null || true
rm -f /home/ga/Documents/SolveSpace/flange_start.slvs 2>/dev/null || true

date +%s > /tmp/pipe_support_flange_repair_start_ts

# Generate T-flange .slvs with 5 WRONG distance constraints (superseded revision values)
# Correct T-flange shape (matches spec): base_w=120, base_h=12, hub_w=36, hub_h=60, left_offset=42
# Geometry points at WRONG coords so the shape visually matches the wrong constraints:
#   A=(0,0), B=(90,0), C=(90,8), D=(57,8), E=(57,48), F=(33,48), G=(33,8), H=(0,8)
# Wrong constraint values injected: base_w=90, base_h=8, hub_w=24, hub_h=40, left_offset=33
python3 << 'PYEOF'
import os

MAGIC = b'\xb1\xb2\xb3SolveSpaceREVa'

blocks = []
blocks.append(MAGIC)

# Group 1: #references
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

# Group 2: sketch-in-plane
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

# Reference axis params
ref_params = [
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
]
blocks.extend(ref_params)

# T-flange: 8 points, 8 line segments (closed polygon)
# A=(0,0) B=(90,0) C=(90,8) D=(57,8) E=(57,48) F=(33,48) G=(33,8) H=(0,8)
line_coords = [
    (0.0,  0.0,  90.0,  0.0),   # req 4: A→B  bottom
    (90.0, 0.0,  90.0,  8.0),   # req 5: B→C  right
    (90.0, 8.0,  57.0,  8.0),   # req 6: C→D  step right
    (57.0, 8.0,  57.0, 48.0),   # req 7: D→E  hub right
    (57.0, 48.0, 33.0, 48.0),   # req 8: E→F  hub top
    (33.0, 48.0, 33.0,  8.0),   # req 9: F→G  hub left
    (33.0, 8.0,   0.0,  8.0),   # req 10: G→H step left
    (0.0,  8.0,   0.0,  0.0),   # req 11: H→A left
]

def fmt(v):
    if v == 0.0:
        return '0'
    return f'{v:.21g}'

for i, (x0, y0, x1, y1) in enumerate(line_coords):
    rn = i + 4
    ph = f'{rn:04x}'
    blocks.append(f"Param.h.v.=00{ph}0010\nParam.val={fmt(x0)}\nAddParam".encode())
    blocks.append(f"Param.h.v.=00{ph}0011\nParam.val={fmt(y0)}\nAddParam".encode())
    blocks.append(f"Param.h.v.=00{ph}0013\nParam.val={fmt(x1)}\nAddParam".encode())
    blocks.append(f"Param.h.v.=00{ph}0014\nParam.val={fmt(y1)}\nAddParam".encode())

# Requests: reference axes
for n in [1, 2, 3]:
    blocks.append(f"Request.h.v={n:08x}\nRequest.type=100\nRequest.group.v=00000001\nRequest.construction=0\nAddRequest".encode())
# Line segments
for n in range(4, 12):
    blocks.append(f"Request.h.v={n:08x}\nRequest.type=200\nRequest.workplane.v=80020000\nRequest.group.v=00000002\nRequest.construction=0\nAddRequest".encode())

# Reference entities
blocks.append(b"""Entity.h.v=00010000
Entity.type=10000
Entity.construction=0
Entity.point[0].v=00010001
Entity.normal.v=00010020
Entity.actVisible=1
AddEntity""")
blocks.append(b"""Entity.h.v=00010001
Entity.type=2000
Entity.construction=1
Entity.actVisible=1
AddEntity""")
blocks.append(b"""Entity.h.v=00010020
Entity.type=3000
Entity.construction=0
Entity.point[0].v=00010001
Entity.actNormal.w=1.000000000000000000000
Entity.actVisible=1
AddEntity""")
blocks.append(b"""Entity.h.v=00020000
Entity.type=10000
Entity.construction=0
Entity.point[0].v=00020001
Entity.normal.v=00020020
Entity.actVisible=1
AddEntity""")
blocks.append(b"""Entity.h.v=00020001
Entity.type=2000
Entity.construction=1
Entity.actVisible=1
AddEntity""")
blocks.append(b"""Entity.h.v=00020020
Entity.type=3000
Entity.construction=0
Entity.point[0].v=00020001
Entity.actNormal.w=0.500000000000000000000
Entity.actNormal.vx=0.500000000000000000000
Entity.actNormal.vy=0.500000000000000000000
Entity.actNormal.vz=0.500000000000000000000
Entity.actVisible=1
AddEntity""")
blocks.append(b"""Entity.h.v=00030000
Entity.type=10000
Entity.construction=0
Entity.point[0].v=00030001
Entity.normal.v=00030020
Entity.actVisible=1
AddEntity""")
blocks.append(b"""Entity.h.v=00030001
Entity.type=2000
Entity.construction=1
Entity.actVisible=1
AddEntity""")
blocks.append(b"""Entity.h.v=00030020
Entity.type=3000
Entity.construction=0
Entity.point[0].v=00030001
Entity.actNormal.w=0.500000000000000000000
Entity.actNormal.vx=-0.500000000000000000000
Entity.actNormal.vy=-0.500000000000000000000
Entity.actNormal.vz=-0.500000000000000000000
Entity.actVisible=1
AddEntity""")

# Workplane
blocks.append(b"""Entity.h.v=80020000
Entity.type=10000
Entity.construction=0
Entity.point[0].v=80020002
Entity.normal.v=80020001
Entity.actVisible=1
AddEntity""")
blocks.append(b"""Entity.h.v=80020001
Entity.type=3010
Entity.construction=0
Entity.point[0].v=80020002
Entity.actNormal.w=1.000000000000000000000
Entity.actVisible=1
AddEntity""")
blocks.append(b"""Entity.h.v=80020002
Entity.type=2012
Entity.construction=1
Entity.actVisible=1
AddEntity""")

# Line entities
for i, (x0, y0, x1, y1) in enumerate(line_coords):
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

# Constraints
ch = 1

def add_coincident(ptA, ptB):
    global ch
    blocks.append(f"""Constraint.h.v={ch:08x}
Constraint.type=20
Constraint.group.v=00000002
Constraint.workplane.v=80020000
Constraint.ptA.v={ptA}
Constraint.ptB.v={ptB}
AddConstraint""".encode())
    ch += 1

def add_horiz(ent):
    global ch
    blocks.append(f"""Constraint.h.v={ch:08x}
Constraint.type=80
Constraint.group.v=00000002
Constraint.workplane.v=80020000
Constraint.entityA.v={ent}
AddConstraint""".encode())
    ch += 1

def add_vert(ent):
    global ch
    blocks.append(f"""Constraint.h.v={ch:08x}
Constraint.type=82
Constraint.group.v=00000002
Constraint.workplane.v=80020000
Constraint.entityA.v={ent}
AddConstraint""".encode())
    ch += 1

def add_where_dragged(pt):
    global ch
    blocks.append(f"""Constraint.h.v={ch:08x}
Constraint.type=200
Constraint.group.v=00000002
Constraint.workplane.v=80020000
Constraint.ptA.v={pt}
AddConstraint""".encode())
    ch += 1

def add_distance(ptA, ptB, val):
    global ch
    blocks.append(f"""Constraint.h.v={ch:08x}
Constraint.type=30
Constraint.group.v=00000002
Constraint.workplane.v=80020000
Constraint.valA={val:.6f}
Constraint.ptA.v={ptA}
Constraint.ptB.v={ptB}
AddConstraint""".encode())
    ch += 1

# Coincident constraints closing the polygon loop
# reqs 4-11, each req N: start=00{N:04x}0001, end=00{N:04x}0002
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
    add_coincident(ptA, ptB)

# H/V constraints
# Horizontal: bottom(4), step-right(6), hub-top(8), step-left(10)
for ent in ['00040000', '00060000', '00080000', '000a0000']:
    add_horiz(ent)

# Vertical: right(5), hub-right(7), hub-left(9), left(11)
for ent in ['00050000', '00070000', '00090000', '000b0000']:
    add_vert(ent)

# WHERE_DRAGGED pin at A
add_where_dragged('00040001')

# ── WRONG distance constraints (superseded values) ──
# 1. base_w=90  (correct: 120) — A to B horizontal (bottom)
add_distance('00040001', '00040002', 90.0)
# 2. base_h=8   (correct: 12)  — A to H vertical (left side height)
add_distance('00040001', '000b0002', 8.0)
# 3. hub_w=24   (correct: 36)  — G to D horizontal (hub width = 57-33=24, correct would be 78-42=36)
add_distance('00090001', '00060002', 24.0)
# 4. hub_h=40   (correct: 60)  — D to E vertical (hub height = 48-8=40, correct 72-12=60)
add_distance('00070001', '00070002', 40.0)
# 5. left_offset=33 (correct: 42) — A to G horizontal (left step = 33, correct 42)
add_distance('00040001', '000a0002', 33.0)

content = b'\n\n'.join(blocks) + b'\n'
outpath = '/home/ga/Documents/SolveSpace/flange_start.slvs'
with open(outpath, 'wb') as f:
    f.write(content)
print(f"Generated {outpath}: {os.path.getsize(outpath)} bytes")
PYEOF

chown ga:ga /home/ga/Documents/SolveSpace/flange_start.slvs

# Drop specification sheet on Desktop
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/flange_specification.txt << 'SPECEOF'
COMPONENT SPECIFICATION — PIPE SUPPORT T-FLANGE
Drawing No: PSF-2247-REV-C
Revision: C (supersedes Rev B)
Material: A105 carbon steel
Application: DN50 pipe support, process piping

DIMENSIONAL REQUIREMENTS (all in mm):
- Flange base width (A to B):    120 mm
- Flange base height (thickness): 12 mm
- Hub width (G to D):             36 mm
- Hub height (D to E):            60 mm
- Left offset (A to G):           42 mm

Note: Rev B values were WRONG and must not be used.
Tolerance: ±0.5 mm on all linear dimensions.
Issued by: Piping Design Group
SPECEOF
chown ga:ga /home/ga/Desktop/flange_specification.txt

kill_solvespace

launch_solvespace "/home/ga/Documents/SolveSpace/flange_start.slvs"
echo "Waiting for SolveSpace to load..."
wait_for_solvespace 30
sleep 5

maximize_solvespace
sleep 1

take_screenshot /tmp/pipe_support_flange_repair_start.png
echo "=== pipe_support_flange_repair setup complete ==="
echo "T-flange loaded with 5 WRONG constraints. Spec on Desktop."
