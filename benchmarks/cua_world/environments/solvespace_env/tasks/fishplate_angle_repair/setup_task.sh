#!/bin/bash
echo "=== Setting up fishplate_angle_repair task ==="

source /workspace/scripts/task_utils.sh

mkdir -p /home/ga/Documents/SolveSpace
chown -R ga:ga /home/ga/Documents/SolveSpace

rm -f /home/ga/Documents/SolveSpace/fishplate_corrected.slvs 2>/dev/null || true
rm -f /home/ga/Documents/SolveSpace/fishplate_corrected.dxf 2>/dev/null || true
rm -f /home/ga/Documents/SolveSpace/fishplate_start.slvs 2>/dev/null || true

date +%s > /tmp/fishplate_angle_repair_start_ts

# Generate fishplate cross-section with wrong distance and angle constraints.
# Geometry is a parallelogram. The spec on Desktop has the correct values.
python3 << 'PYEOF'
import os, math

MAGIC = b'\xb1\xb2\xb3SolveSpaceREVa'
blocks = []
blocks.append(MAGIC)

# Wrong values injected into the file (do not print these)
WRONG_ANGLE  = 25.0
WRONG_WIDTH  = 140.0
WRONG_HEIGHT = 18.0

dx_val = WRONG_HEIGHT * math.tan(math.radians(WRONG_ANGLE))
ax, ay = 0.0, 0.0
bx, by = WRONG_WIDTH, 0.0
cx, cy = WRONG_WIDTH + dx_val, WRONG_HEIGHT
dx2, dy2 = dx_val, WRONG_HEIGHT

def fmt(v):
    return '0' if v == 0.0 else f'{v:.21g}'

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

blocks += [
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

line_coords = [
    (ax, ay, bx, by),
    (bx, by, cx, cy),
    (cx, cy, dx2, dy2),
    (dx2, dy2, ax, ay),
]
for i, (x0, y0, x1, y1) in enumerate(line_coords):
    rn = i + 4
    ph = f'{rn:04x}'
    blocks.append(f"Param.h.v.=00{ph}0010\nParam.val={fmt(x0)}\nAddParam".encode())
    blocks.append(f"Param.h.v.=00{ph}0011\nParam.val={fmt(y0)}\nAddParam".encode())
    blocks.append(f"Param.h.v.=00{ph}0013\nParam.val={fmt(x1)}\nAddParam".encode())
    blocks.append(f"Param.h.v.=00{ph}0014\nParam.val={fmt(y1)}\nAddParam".encode())

for n in [1, 2, 3]:
    blocks.append(f"Request.h.v={n:08x}\nRequest.type=100\nRequest.group.v=00000001\nRequest.construction=0\nAddRequest".encode())
for n in range(4, 8):
    blocks.append(f"Request.h.v={n:08x}\nRequest.type=200\nRequest.workplane.v=80020000\nRequest.group.v=00000002\nRequest.construction=0\nAddRequest".encode())

blocks += [
    b"Entity.h.v=00010000\nEntity.type=10000\nEntity.construction=0\nEntity.point[0].v=00010001\nEntity.normal.v=00010020\nEntity.actVisible=1\nAddEntity",
    b"Entity.h.v=00010001\nEntity.type=2000\nEntity.construction=1\nEntity.actVisible=1\nAddEntity",
    b"Entity.h.v=00010020\nEntity.type=3000\nEntity.construction=0\nEntity.point[0].v=00010001\nEntity.actNormal.w=1.000000000000000000000\nEntity.actVisible=1\nAddEntity",
    b"Entity.h.v=00020000\nEntity.type=10000\nEntity.construction=0\nEntity.point[0].v=00020001\nEntity.normal.v=00020020\nEntity.actVisible=1\nAddEntity",
    b"Entity.h.v=00020001\nEntity.type=2000\nEntity.construction=1\nEntity.actVisible=1\nAddEntity",
    b"Entity.h.v=00020020\nEntity.type=3000\nEntity.construction=0\nEntity.point[0].v=00020001\nEntity.actNormal.w=0.500000000000000000000\nEntity.actNormal.vx=0.500000000000000000000\nEntity.actNormal.vy=0.500000000000000000000\nEntity.actNormal.vz=0.500000000000000000000\nEntity.actVisible=1\nAddEntity",
    b"Entity.h.v=00030000\nEntity.type=10000\nEntity.construction=0\nEntity.point[0].v=00030001\nEntity.normal.v=00030020\nEntity.actVisible=1\nAddEntity",
    b"Entity.h.v=00030001\nEntity.type=2000\nEntity.construction=1\nEntity.actVisible=1\nAddEntity",
    b"Entity.h.v=00030020\nEntity.type=3000\nEntity.construction=0\nEntity.point[0].v=00030001\nEntity.actNormal.w=0.500000000000000000000\nEntity.actNormal.vx=-0.500000000000000000000\nEntity.actNormal.vy=-0.500000000000000000000\nEntity.actNormal.vz=-0.500000000000000000000\nEntity.actVisible=1\nAddEntity",
]

blocks += [
    b"Entity.h.v=80020000\nEntity.type=10000\nEntity.construction=0\nEntity.point[0].v=80020002\nEntity.normal.v=80020001\nEntity.actVisible=1\nAddEntity",
    b"Entity.h.v=80020001\nEntity.type=3010\nEntity.construction=0\nEntity.point[0].v=80020002\nEntity.actNormal.w=1.000000000000000000000\nEntity.actVisible=1\nAddEntity",
    b"Entity.h.v=80020002\nEntity.type=2012\nEntity.construction=1\nEntity.actVisible=1\nAddEntity",
]

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

ch = 1
def add_c(s):
    global ch
    blocks.append(s.encode())
    ch += 1

def add_coincident(ptA, ptB):
    add_c(f"Constraint.h.v={ch:08x}\nConstraint.type=20\nConstraint.group.v=00000002\nConstraint.workplane.v=80020000\nConstraint.ptA.v={ptA}\nConstraint.ptB.v={ptB}\nAddConstraint")

def add_horiz(ent):
    add_c(f"Constraint.h.v={ch:08x}\nConstraint.type=80\nConstraint.group.v=00000002\nConstraint.workplane.v=80020000\nConstraint.entityA.v={ent}\nAddConstraint")

def add_where_dragged(pt):
    add_c(f"Constraint.h.v={ch:08x}\nConstraint.type=200\nConstraint.group.v=00000002\nConstraint.workplane.v=80020000\nConstraint.ptA.v={pt}\nAddConstraint")

def add_distance(ptA, ptB, val):
    add_c(f"Constraint.h.v={ch:08x}\nConstraint.type=30\nConstraint.group.v=00000002\nConstraint.workplane.v=80020000\nConstraint.valA={val:.6f}\nConstraint.ptA.v={ptA}\nConstraint.ptB.v={ptB}\nAddConstraint")

def add_angle(entA, entB, val_deg):
    add_c(f"Constraint.h.v={ch:08x}\nConstraint.type=110\nConstraint.group.v=00000002\nConstraint.workplane.v=80020000\nConstraint.valA={val_deg:.6f}\nConstraint.entityA.v={entA}\nConstraint.entityB.v={entB}\nAddConstraint")

pairs = [
    ('00040002', '00050001'),
    ('00050002', '00060001'),
    ('00060002', '00070001'),
    ('00070002', '00040001'),
]
for ptA, ptB in pairs:
    add_coincident(ptA, ptB)

add_horiz('00040000')
add_horiz('00060000')
add_where_dragged('00040001')

# Wrong constraints embedded in file
add_distance('00040001', '00040002', WRONG_WIDTH)
add_distance('00040001', '00070001', WRONG_HEIGHT)
add_angle('00050000', '00040000', WRONG_ANGLE)

content = b'\n\n'.join(blocks) + b'\n'
outpath = '/home/ga/Documents/SolveSpace/fishplate_start.slvs'
with open(outpath, 'wb') as f:
    f.write(content)
print(f"Generated {outpath}: {os.path.getsize(outpath)} bytes")
PYEOF

chown ga:ga /home/ga/Documents/SolveSpace/fishplate_start.slvs

mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/fishplate_specification.txt << 'SPECEOF'
COMPONENT SPECIFICATION — RAILWAY FISHPLATE (SPLICE BAR)
Drawing No: RW-FP-0339-REV-D
Revision: D (supersedes Rev C — do not use Rev C values)
Material: Grade 900A rail steel
Standard: EN 13153 / BS 11

CROSS-SECTION PROFILE — DIMENSIONAL REQUIREMENTS:
- Total length (base width):  160 mm
- Total height (profile depth): 22 mm
- Angle of web sides to horizontal: 30 degrees

Note: Rev C incorrectly specified 140 mm width, 18 mm height, and 25° angle.
All three values must be corrected to the Rev D values above.

Tolerance: ±0.5 mm on linear dims; ±0.5° on angle.
Approved by: Chief Track Engineer
SPECEOF
chown ga:ga /home/ga/Desktop/fishplate_specification.txt

kill_solvespace

launch_solvespace "/home/ga/Documents/SolveSpace/fishplate_start.slvs"
echo "Waiting for SolveSpace to load..."
wait_for_solvespace 30
sleep 5

maximize_solvespace
sleep 1

take_screenshot /tmp/fishplate_angle_repair_start.png
echo "=== fishplate_angle_repair setup complete ==="
