#!/bin/bash
echo "=== Setting up repair_bracket_constraints task ==="

source /workspace/scripts/task_utils.sh

# Ensure workspace directory exists
mkdir -p /home/ga/Documents/SolveSpace
chown -R ga:ga /home/ga/Documents/SolveSpace

# Remove any previous output file
rm -f /home/ga/Documents/SolveSpace/bracket_constrained.slvs 2>/dev/null || true
rm -f /home/ga/Documents/SolveSpace/bracket_start.slvs 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/repair_bracket_constraints_start_ts

# Generate the L-bracket .slvs file with geometry but NO distance constraints
# The bracket is an L-shape: horizontal arm 85mm wide × 10mm thick,
# vertical arm 60mm tall × 10mm thick (shared thickness)
# Points: A=(0,0), B=(85,0), C=(85,10), D=(10,10), E=(10,60), F=(0,60)
python3 << 'PYEOF'
import os

MAGIC = b'\xb1\xb2\xb3SolveSpaceREVa'

def make_block(text):
    return text.encode('utf-8')

blocks = []

# Binary magic header
blocks.append(MAGIC)

# ── Group 1: #references ──
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

# ── Group 2: sketch-in-plane (XY) ──
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

# ── Params for reference group 1 (XY axis / normal) ──
ref_params = [
    b"Param.h.v.=00010010\nAddParam",
    b"Param.h.v.=00010011\nAddParam",
    b"Param.h.v.=00010012\nAddParam",
    b"Param.h.v.=00010020\nParam.val=1.000000000000000000000\nAddParam",
    b"Param.h.v.=00010021\nAddParam",
    b"Param.h.v.=00010022\nAddParam",
    b"Param.h.v.=00010023\nAddParam",
    # Y-axis reference (req 2)
    b"Param.h.v.=00020010\nAddParam",
    b"Param.h.v.=00020011\nAddParam",
    b"Param.h.v.=00020012\nAddParam",
    b"Param.h.v.=00020020\nParam.val=0.500000000000000000000\nAddParam",
    b"Param.h.v.=00020021\nParam.val=0.500000000000000000000\nAddParam",
    b"Param.h.v.=00020022\nParam.val=0.500000000000000000000\nAddParam",
    b"Param.h.v.=00020023\nParam.val=0.500000000000000000000\nAddParam",
    # Z-axis reference (req 3)
    b"Param.h.v.=00030010\nAddParam",
    b"Param.h.v.=00030011\nAddParam",
    b"Param.h.v.=00030012\nAddParam",
    b"Param.h.v.=00030020\nParam.val=0.500000000000000000000\nAddParam",
    b"Param.h.v.=00030021\nParam.val=-0.500000000000000000000\nAddParam",
    b"Param.h.v.=00030022\nParam.val=-0.500000000000000000000\nAddParam",
    b"Param.h.v.=00030023\nParam.val=-0.500000000000000000000\nAddParam",
]
blocks.extend(ref_params)

# ── Geometry: 6 line segments forming the L-bracket ──
# Request handles 4–9, entity groups 0004–0009
# (x0,y0) -> (x1,y1) for each line
line_coords = [
    (0.0,   0.0,  85.0,  0.0),   # req 4: bottom  A→B
    (85.0,  0.0,  85.0, 10.0),   # req 5: right   B→C
    (85.0, 10.0,  10.0, 10.0),   # req 6: step    C→D
    (10.0, 10.0,  10.0, 60.0),   # req 7: vert    D→E
    (10.0, 60.0,   0.0, 60.0),   # req 8: top     E→F
    (0.0,  60.0,   0.0,  0.0),   # req 9: left    F→A
]

for i, (x0, y0, x1, y1) in enumerate(line_coords):
    rn = i + 4      # request number 4–9
    ph = f'{rn:04x}'  # param/entity hex prefix: '0004'–'0009'
    def fmt(v):
        if v == 0.0:
            return '0'
        return f'{v:.21g}'
    blocks.append(f"Param.h.v.=00{ph}0010\nParam.val={fmt(x0)}\nAddParam".encode())
    blocks.append(f"Param.h.v.=00{ph}0011\nParam.val={fmt(y0)}\nAddParam".encode())
    blocks.append(f"Param.h.v.=00{ph}0013\nParam.val={fmt(x1)}\nAddParam".encode())
    blocks.append(f"Param.h.v.=00{ph}0014\nParam.val={fmt(y1)}\nAddParam".encode())

# ── Requests ──
# Reference axes (group 1)
for n in [1, 2, 3]:
    blocks.append(f"Request.h.v={n:08x}\nRequest.type=100\nRequest.group.v=00000001\nRequest.construction=0\nAddRequest".encode())
# Line segments (group 2)
for n in range(4, 10):
    blocks.append(f"Request.h.v={n:08x}\nRequest.type=200\nRequest.workplane.v=80020000\nRequest.group.v=00000002\nRequest.construction=0\nAddRequest".encode())

# ── Entities: reference group ──
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

# ── Entities: sketch workplane ──
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

# ── Entities: line segments ──
for i, (x0, y0, x1, y1) in enumerate(line_coords):
    rn = i + 4
    ph = f'{rn:04x}'
    def fmt(v):
        if v == 0.0:
            return '0'
        return f'{v:.21g}'
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
ch = 1  # constraint handle counter

def add_coincident(ptA, ptB):
    global ch
    b = f"""Constraint.h.v={ch:08x}
Constraint.type=20
Constraint.group.v=00000002
Constraint.workplane.v=80020000
Constraint.ptA.v={ptA}
Constraint.ptB.v={ptB}
AddConstraint""".encode()
    blocks.append(b)
    ch += 1

def add_horiz(ent):
    global ch
    b = f"""Constraint.h.v={ch:08x}
Constraint.type=80
Constraint.group.v=00000002
Constraint.workplane.v=80020000
Constraint.entityA.v={ent}
AddConstraint""".encode()
    blocks.append(b)
    ch += 1

def add_vert(ent):
    global ch
    b = f"""Constraint.h.v={ch:08x}
Constraint.type=82
Constraint.group.v=00000002
Constraint.workplane.v=80020000
Constraint.entityA.v={ent}
AddConstraint""".encode()
    blocks.append(b)
    ch += 1

def add_where_dragged(pt):
    global ch
    b = f"""Constraint.h.v={ch:08x}
Constraint.type=200
Constraint.group.v=00000002
Constraint.workplane.v=80020000
Constraint.ptA.v={pt}
AddConstraint""".encode()
    blocks.append(b)
    ch += 1

# POINTS_COINCIDENT: close the L-bracket loop
# Line N pt1 = Line N+1 pt0 (using entity handles)
pairs = [
    ('00040002', '00050001'),  # B
    ('00050002', '00060001'),  # C
    ('00060002', '00070001'),  # D
    ('00070002', '00080001'),  # E
    ('00080002', '00090001'),  # F
    ('00090002', '00040001'),  # back to A
]
for ptA, ptB in pairs:
    add_coincident(ptA, ptB)

# HORIZONTAL: lines 4, 6, 8 (bottom, step, top)
for ent in ['00040000', '00060000', '00080000']:
    add_horiz(ent)

# VERTICAL: lines 5, 7, 9 (right, inner vert, left)
for ent in ['00050000', '00070000', '00090000']:
    add_vert(ent)

# WHERE_DRAGGED: pin point A at origin so sketch doesn't drift
add_where_dragged('00040001')

# ── Write file ──
content = b'\n\n'.join(blocks) + b'\n'
outpath = '/home/ga/Documents/SolveSpace/bracket_start.slvs'
with open(outpath, 'wb') as f:
    f.write(content)
print(f"Generated {outpath}: {os.path.getsize(outpath)} bytes")
PYEOF

chown ga:ga /home/ga/Documents/SolveSpace/bracket_start.slvs

# Drop the component specification sheet on the desktop
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/bracket_specification.txt << 'SPECEOF'
COMPONENT SPECIFICATION — L-BRACKET SHELF MOUNT
Revision: REV-B
Drawing No: SHM-0047
Material: 3mm mild steel sheet

DIMENSIONAL REQUIREMENTS:
- Horizontal arm total length: 85 mm
- Vertical arm total height: 60 mm
- Material thickness (both arms): 10 mm

Tolerance: ±0.5 mm unless noted
Issued by: Design Department
SPECEOF
chown ga:ga /home/ga/Desktop/bracket_specification.txt

# Kill any existing SolveSpace instance
kill_solvespace

# Launch SolveSpace with the bracket file
launch_solvespace "/home/ga/Documents/SolveSpace/bracket_start.slvs"

echo "Waiting for SolveSpace to load bracket_start.slvs..."
wait_for_solvespace 30
sleep 5

maximize_solvespace
sleep 1

take_screenshot /tmp/repair_bracket_constraints_start.png
echo "=== repair_bracket_constraints setup complete ==="
echo "L-bracket loaded: 6 lines with H/V/coincident constraints, NO distance constraints."
echo "Component specification available at /home/ga/Desktop/bracket_specification.txt"
