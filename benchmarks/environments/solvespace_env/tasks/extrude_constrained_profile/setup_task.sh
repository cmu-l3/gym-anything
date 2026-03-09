#!/bin/bash
echo "=== Setting up extrude_constrained_profile task ==="

source /workspace/scripts/task_utils.sh

mkdir -p /home/ga/Documents/SolveSpace
chown -R ga:ga /home/ga/Documents/SolveSpace

rm -f /home/ga/Documents/SolveSpace/profile_extruded.slvs 2>/dev/null || true
rm -f /home/ga/Documents/SolveSpace/profile_sketch.slvs 2>/dev/null || true

date +%s > /tmp/extrude_constrained_profile_start_ts

# Generate a T-profile 2D sketch with full dimension constraints.
# The profile is a union of:
#   Bottom rect: (0,0)→(60,0)→(60,40)→(0,40) — 60mm wide, 40mm tall
#   Top protrusion: (20,40)→(40,40)→(40,55)→(20,55) — 20mm wide, 15mm tall
# Total: 10 line segments (req 4-13)
# All dimension constraints are pre-applied so agent only needs to extrude.
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

# Reference params
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

# T-profile: 10 lines (req 4-13)
# Bottom rect: corners at (0,0),(60,0),(60,40),(0,40)
# Top protrusion: corners at (20,40),(40,40),(40,55),(20,55)
# Connected as one closed profile (T-shape, 10 vertices)
# Going clockwise from bottom-left:
# (0,0)→(60,0)→(60,40)→(40,40)→(40,55)→(20,55)→(20,40)→(0,40)→(0,0)
# That's 8 line segments (req 4-11)
t_lines = [
    (0.0,  0.0,  60.0,  0.0),   # req4: bottom
    (60.0, 0.0,  60.0, 40.0),   # req5: right
    (60.0,40.0,  40.0, 40.0),   # req6: step-right
    (40.0,40.0,  40.0, 55.0),   # req7: tab-right
    (40.0,55.0,  20.0, 55.0),   # req8: tab-top
    (20.0,55.0,  20.0, 40.0),   # req9: tab-left
    (20.0,40.0,   0.0, 40.0),   # req10: step-left
    (0.0, 40.0,   0.0,  0.0),   # req11: left
]

for i, (x0, y0, x1, y1) in enumerate(t_lines):
    rn = i + 4
    ph = f'{rn:04x}'
    blocks.append(f"Param.h.v.=00{ph}0010\nParam.val={fmt(x0)}\nAddParam".encode())
    blocks.append(f"Param.h.v.=00{ph}0011\nParam.val={fmt(y0)}\nAddParam".encode())
    blocks.append(f"Param.h.v.=00{ph}0013\nParam.val={fmt(x1)}\nAddParam".encode())
    blocks.append(f"Param.h.v.=00{ph}0014\nParam.val={fmt(y1)}\nAddParam".encode())

# Requests
for n in [1, 2, 3]:
    blocks.append(f"Request.h.v={n:08x}\nRequest.type=100\nRequest.group.v=00000001\nRequest.construction=0\nAddRequest".encode())
for n in range(4, 12):
    blocks.append(f"Request.h.v={n:08x}\nRequest.type=200\nRequest.workplane.v=80020000\nRequest.group.v=00000002\nRequest.construction=0\nAddRequest".encode())

# Reference entities
for e in [
    b"""Entity.h.v=00010000\nEntity.type=10000\nEntity.construction=0\nEntity.point[0].v=00010001\nEntity.normal.v=00010020\nEntity.actVisible=1\nAddEntity""",
    b"""Entity.h.v=00010001\nEntity.type=2000\nEntity.construction=1\nEntity.actVisible=1\nAddEntity""",
    b"""Entity.h.v=00010020\nEntity.type=3000\nEntity.construction=0\nEntity.point[0].v=00010001\nEntity.actNormal.w=1.000000000000000000000\nEntity.actVisible=1\nAddEntity""",
    b"""Entity.h.v=00020000\nEntity.type=10000\nEntity.construction=0\nEntity.point[0].v=00020001\nEntity.normal.v=00020020\nEntity.actVisible=1\nAddEntity""",
    b"""Entity.h.v=00020001\nEntity.type=2000\nEntity.construction=1\nEntity.actVisible=1\nAddEntity""",
    b"""Entity.h.v=00020020\nEntity.type=3000\nEntity.construction=0\nEntity.point[0].v=00020001\nEntity.actNormal.w=0.500000000000000000000\nEntity.actNormal.vx=0.500000000000000000000\nEntity.actNormal.vy=0.500000000000000000000\nEntity.actNormal.vz=0.500000000000000000000\nEntity.actVisible=1\nAddEntity""",
    b"""Entity.h.v=00030000\nEntity.type=10000\nEntity.construction=0\nEntity.point[0].v=00030001\nEntity.normal.v=00030020\nEntity.actVisible=1\nAddEntity""",
    b"""Entity.h.v=00030001\nEntity.type=2000\nEntity.construction=1\nEntity.actVisible=1\nAddEntity""",
    b"""Entity.h.v=00030020\nEntity.type=3000\nEntity.construction=0\nEntity.point[0].v=00030001\nEntity.actNormal.w=0.500000000000000000000\nEntity.actNormal.vx=-0.500000000000000000000\nEntity.actNormal.vy=-0.500000000000000000000\nEntity.actNormal.vz=-0.500000000000000000000\nEntity.actVisible=1\nAddEntity""",
    b"""Entity.h.v=80020000\nEntity.type=10000\nEntity.construction=0\nEntity.point[0].v=80020002\nEntity.normal.v=80020001\nEntity.actVisible=1\nAddEntity""",
    b"""Entity.h.v=80020001\nEntity.type=3010\nEntity.construction=0\nEntity.point[0].v=80020002\nEntity.actNormal.w=1.000000000000000000000\nEntity.actVisible=1\nAddEntity""",
    b"""Entity.h.v=80020002\nEntity.type=2012\nEntity.construction=1\nEntity.actVisible=1\nAddEntity""",
]:
    blocks.append(e)

# Line entities
for i, (x0, y0, x1, y1) in enumerate(t_lines):
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

def add_c(ctype, extra=''):
    global ch
    blocks.append(f"Constraint.h.v={ch:08x}\nConstraint.type={ctype}\nConstraint.group.v=00000002\nConstraint.workplane.v=80020000\n{extra}AddConstraint".encode())
    ch += 1

# COINCIDENT: close the 8-vertex T-profile loop
# Line i pt1 = Line i+1 pt0
req_seq = list(range(4, 12))  # 4..11
for i in range(len(req_seq)):
    curr = req_seq[i]
    nxt  = req_seq[(i + 1) % len(req_seq)]
    ph_c = f'{curr:04x}'
    ph_n = f'{nxt:04x}'
    add_c(20, f"Constraint.ptA.v=00{ph_c}0002\nConstraint.ptB.v=00{ph_n}0001\n")

# HORIZONTAL: bottom (req4), step-right (req6), tab-top (req8), step-left (req10)
for ent in ['00040000','00060000','00080000','000a0000']:
    add_c(80, f"Constraint.entityA.v={ent}\n")

# VERTICAL: right (req5), tab-right (req7), tab-left (req9), left (req11)
for ent in ['00050000','00070000','00090000','000b0000']:
    add_c(82, f"Constraint.entityA.v={ent}\n")

# Pin origin
add_c(200, "Constraint.ptA.v=00040001\n")

# Dimension constraints (pre-applied so sketch is fully defined)
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

# Overall width 60mm: bottom-left (00040001) to bottom-right (00040002)
add_dist('00040001', '00040002', 60.0)
# Right-side height 40mm: bottom-right (00050001) to shoulder-right (00050002)
add_dist('00050001', '00050002', 40.0)
# Tab width 20mm: tab-right-top (00070002) to tab-left-top (00090001)
add_dist('00080001', '00080002', 20.0)
# Tab height 15mm: shoulder-level to tab-top
add_dist('00070001', '00070002', 15.0)

content = b'\n\n'.join(blocks) + b'\n'
outpath = '/home/ga/Documents/SolveSpace/profile_sketch.slvs'
with open(outpath, 'wb') as f:
    f.write(content)
print(f"Generated {outpath}: {os.path.getsize(outpath)} bytes")
PYEOF

chown ga:ga /home/ga/Documents/SolveSpace/profile_sketch.slvs

# Drop the manufacturing order on the desktop
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/manufacturing_order.txt << 'SPECEOF'
MANUFACTURING ORDER — T-PROFILE EXTRUSION
Order No: MFG-2024-0847
Part: Structural T-rail for equipment rack
Material: 6061-T6 aluminium extrusion

EXTRUSION SPECIFICATION:
- Profile: T-section (see open drawing)
- Extrusion length: 100 mm
- Tolerance: +/-1 mm

Process notes: Create 3D solid model for NC programming.
Route to: CNC Machining Cell 3
Issued by: Production Engineering
SPECEOF
chown ga:ga /home/ga/Desktop/manufacturing_order.txt

kill_solvespace
launch_solvespace "/home/ga/Documents/SolveSpace/profile_sketch.slvs"

echo "Waiting for SolveSpace to load profile_sketch.slvs..."
wait_for_solvespace 30
sleep 5

maximize_solvespace
sleep 1

take_screenshot /tmp/extrude_constrained_profile_start.png
echo "=== extrude_constrained_profile setup complete ==="
echo "T-profile 2D sketch loaded, fully constrained. Manufacturing order at /home/ga/Desktop/manufacturing_order.txt"
