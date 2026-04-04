#!/bin/bash
echo "=== Setting up constrain_rectangular_frame task ==="

source /workspace/scripts/task_utils.sh

mkdir -p /home/ga/Documents/SolveSpace
chown -R ga:ga /home/ga/Documents/SolveSpace

rm -f /home/ga/Documents/SolveSpace/gasket_frame_constrained.slvs 2>/dev/null || true
rm -f /home/ga/Documents/SolveSpace/gasket_frame_start.slvs 2>/dev/null || true

date +%s > /tmp/constrain_rectangular_frame_start_ts

# Generate a two-rectangle (frame) .slvs file with NO distance constraints.
# Outer rectangle: (0,0)→(200,0)→(200,150)→(0,150)→(0,0)  [4 lines, handles 4-7]
# Inner rectangle: (10,10)→(190,10)→(190,140)→(10,140)→(10,10) [4 lines, handles 8-11]
python3 << 'PYEOF'
import os

MAGIC = b'\xb1\xb2\xb3SolveSpaceREVa'

blocks = []
blocks.append(MAGIC)

# Groups
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

# Reference params (3 axes)
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

def fmt(v):
    return '0' if v == 0.0 else f'{v:.21g}'

# Lines: outer rectangle (requests 4-7) + inner rectangle (requests 8-11)
# Outer: corners at (0,0),(200,0),(200,150),(0,150)
# Inner: corners at (10,10),(190,10),(190,140),(10,140)
all_lines = [
    # Outer rect (req 4-7)
    (0.0,   0.0,  200.0,   0.0),   # req4: bottom
    (200.0, 0.0,  200.0, 150.0),   # req5: right
    (200.0,150.0,   0.0, 150.0),   # req6: top
    (0.0,  150.0,   0.0,   0.0),   # req7: left
    # Inner rect (req 8-11)
    (10.0,  10.0, 190.0,  10.0),   # req8: bottom-inner
    (190.0, 10.0, 190.0, 140.0),   # req9: right-inner
    (190.0,140.0,  10.0, 140.0),   # req10: top-inner
    (10.0, 140.0,  10.0,  10.0),   # req11: left-inner
]

for i, (x0, y0, x1, y1) in enumerate(all_lines):
    rn = i + 4
    ph = f'{rn:04x}'
    blocks.append(f"Param.h.v.=00{ph}0010\nParam.val={fmt(x0)}\nAddParam".encode())
    blocks.append(f"Param.h.v.=00{ph}0011\nParam.val={fmt(y0)}\nAddParam".encode())
    blocks.append(f"Param.h.v.=00{ph}0013\nParam.val={fmt(x1)}\nAddParam".encode())
    blocks.append(f"Param.h.v.=00{ph}0014\nParam.val={fmt(y1)}\nAddParam".encode())

# Requests: 3 reference + 8 lines
for n in [1, 2, 3]:
    blocks.append(f"Request.h.v={n:08x}\nRequest.type=100\nRequest.group.v=00000001\nRequest.construction=0\nAddRequest".encode())
for n in range(4, 12):
    blocks.append(f"Request.h.v={n:08x}\nRequest.type=200\nRequest.workplane.v=80020000\nRequest.group.v=00000002\nRequest.construction=0\nAddRequest".encode())

# Reference group entities
ref_entities = [
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
]
blocks.extend(ref_entities)

# Line entities (8 lines)
for i, (x0, y0, x1, y1) in enumerate(all_lines):
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

# Constraints: COINCIDENT + HORIZONTAL + VERTICAL + WHERE_DRAGGED
ch = 1

def constr_block(ctype, extra=''):
    global ch
    b = f"Constraint.h.v={ch:08x}\nConstraint.type={ctype}\nConstraint.group.v=00000002\nConstraint.workplane.v=80020000\n{extra}AddConstraint".encode()
    blocks.append(b)
    ch += 1

# Outer rect coincident corners (req 4-7)
outer_pairs = [
    ('00040002','00050001'), ('00050002','00060001'),
    ('00060002','00070001'), ('00070002','00040001'),
]
# Inner rect coincident corners (req 8-11)
inner_pairs = [
    ('00080002','00090001'), ('00090002','000a0001'),
    ('000a0002','000b0001'), ('000b0002','00080001'),
]
for ptA, ptB in outer_pairs + inner_pairs:
    constr_block(20, f"Constraint.ptA.v={ptA}\nConstraint.ptB.v={ptB}\n")

# HORIZONTAL: bottom and top of each rect
for ent in ['00040000','00060000','00080000','000a0000']:
    constr_block(80, f"Constraint.entityA.v={ent}\n")

# VERTICAL: sides of each rect
for ent in ['00050000','00070000','00090000','000b0000']:
    constr_block(82, f"Constraint.entityA.v={ent}\n")

# Pin outer bottom-left corner
constr_block(200, "Constraint.ptA.v=00040001\n")

content = b'\n\n'.join(blocks) + b'\n'
outpath = '/home/ga/Documents/SolveSpace/gasket_frame_start.slvs'
with open(outpath, 'wb') as f:
    f.write(content)
print(f"Generated {outpath}: {os.path.getsize(outpath)} bytes")
PYEOF

chown ga:ga /home/ga/Documents/SolveSpace/gasket_frame_start.slvs

# Drop the project specification sheet on the desktop
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/gasket_specification.txt << 'SPECEOF'
PROJECT SPECIFICATION — HVAC DUCT EXPANSION JOINT GASKET
Job No: HV-2024-0391
Duct size: Series 5 rectangular duct per EN 1505

GASKET DIMENSIONS:
- Outer width: 200 mm
- Outer height: 150 mm
- Inner cutout width: 180 mm
- Inner cutout height: 130 mm
(Wall thickness 10 mm all sides)

Material: EPDM, 3mm thickness
Issued by: Mechanical Services Design
SPECEOF
chown ga:ga /home/ga/Desktop/gasket_specification.txt

kill_solvespace
launch_solvespace "/home/ga/Documents/SolveSpace/gasket_frame_start.slvs"

echo "Waiting for SolveSpace to load gasket_frame_start.slvs..."
wait_for_solvespace 30
sleep 5

maximize_solvespace
sleep 1

take_screenshot /tmp/constrain_rectangular_frame_start.png
echo "=== constrain_rectangular_frame setup complete ==="
echo "Two-rectangle gasket frame loaded: no distance constraints."
echo "Project specification available at /home/ga/Desktop/gasket_specification.txt"
