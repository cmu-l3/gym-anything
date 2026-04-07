#!/bin/bash
echo "=== Setting up hvac_duct_elbow_ecr_update task ==="

source /workspace/scripts/task_utils.sh

mkdir -p /home/ga/Documents/SolveSpace
chown -R ga:ga /home/ga/Documents/SolveSpace

rm -f /home/ga/Documents/SolveSpace/duct_elbow_updated.slvs 2>/dev/null || true
rm -f /home/ga/Documents/SolveSpace/duct_elbow_updated.dxf 2>/dev/null || true
rm -f /home/ga/Documents/SolveSpace/duct_elbow_current.slvs 2>/dev/null || true

date +%s > /tmp/hvac_duct_elbow_ecr_update_start_ts

# Generate L-shaped duct elbow cross-section with CURRENT (old) dimension values
# L-shape: horizontal duct leg + vertical duct leg, meeting at inner corner
# Current dims: outer_w=250, wall_t=50, outer_h=200, leg_w=100
# ECR dims:     outer_w=300, wall_t=70, outer_h=240, leg_w=130
#
# 12-point L-shaped elbow cross-section:
# Start at A, go clockwise:
# A=(0,0)       B=(250,0)   bottom of horizontal leg
# C=(250,200)   D=(150,200) top right of horizontal leg (inner corner area)
# E=(150,50)    F=(100,50)  inner step of elbow
# G=(100,200)   H=(0,200)   left side top of horizontal leg
# Actually a cleaner L-duct cross-section (wall cross-section showing duct wall thickness):
# Outer L rectangle minus inner L rectangle = 8-line profile
# Outer corners: A=(0,0) B=(250,0) C=(250,200) D=(0,200) — but that's just a rectangle
#
# Better: show the L-shaped duct wall cross-section profile — the actual L shape
# Outer profile (10 points):
#  A=(0,0)      B=(250,0)   C=(250,100)  D=(100,100)  E=(100,200)
#  F=(0,200)   — 6-line L-shape (outer boundary of duct leg)
#
# Then inner profile offset by wall_t=50:
#  Would need coincident constraints etc. — complex.
#
# Simplest valid approach: solid L-shaped cross-section (no inner cutout)
# 6 lines, 6 corners:
# A=(0,0) B=(250,0) C=(250,100) D=(100,100) E=(100,200) F=(0,200)
# Dims: total_width=250(B.x), total_height=200(E.y), leg_height=100(C.y), leg_width=100(D.x)

python3 << 'PYEOF'
import os

MAGIC = b'\xb1\xb2\xb3SolveSpaceREVa'
blocks = []
blocks.append(MAGIC)

# CURRENT (old) dimension values
CUR_TOTAL_W = 250.0   # ECR: 300
CUR_TOTAL_H = 200.0   # ECR: 240
CUR_LEG_H   = 100.0   # ECR: 130 (height of horizontal leg / step)
CUR_WALL_T  =  50.0   # ECR:  70 (leg width of vertical duct leg)

# L-shape: A=(0,0) B=(250,0) C=(250,100) D=(100,100) E=(100,200) F=(0,200)
# (using current dims)
ax, ay   = 0.0,        0.0
bx, by   = CUR_TOTAL_W, 0.0
cx, cy   = CUR_TOTAL_W, CUR_LEG_H
dx2, dy2 = CUR_WALL_T + CUR_TOTAL_W - CUR_TOTAL_W + CUR_WALL_T, CUR_LEG_H
# Actually D.x = total_w - (inner_step) ... Let's think:
# The L consists of:
#   - Horizontal arm: from x=0 to x=total_w=250, height from y=0 to y=leg_h=100
#   - Vertical arm: from x=0 to x=wall_t=50, height from y=0 to y=total_h=200
# So the 6-point outline is:
#   A=(0,0) -> B=(250,0) -> C=(250,100) -> D=(50,100) -> E=(50,200) -> F=(0,200) -> back to A
dx2, dy2 = CUR_WALL_T, CUR_LEG_H
ex, ey   = CUR_WALL_T, CUR_TOTAL_H
fx, fy   = 0.0,        CUR_TOTAL_H

line_coords = [
    (ax, ay,   bx, by),    # req 4: A→B bottom
    (bx, by,   cx, cy),    # req 5: B→C right
    (cx, cy,   dx2, dy2),  # req 6: C→D step right-to-inner
    (dx2, dy2, ex, ey),    # req 7: D→E inner vertical
    (ex, ey,   fx, fy),    # req 8: E→F top
    (fx, fy,   ax, ay),    # req 9: F→A left
]

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

def fmt(v):
    return '0' if v == 0.0 else f'{v:.21g}'

for i, (x0, y0, x1, y1) in enumerate(line_coords):
    rn = i + 4
    ph = f'{rn:04x}'
    blocks.append(f"Param.h.v.=00{ph}0010\nParam.val={fmt(x0)}\nAddParam".encode())
    blocks.append(f"Param.h.v.=00{ph}0011\nParam.val={fmt(y0)}\nAddParam".encode())
    blocks.append(f"Param.h.v.=00{ph}0013\nParam.val={fmt(x1)}\nAddParam".encode())
    blocks.append(f"Param.h.v.=00{ph}0014\nParam.val={fmt(y1)}\nAddParam".encode())

# Requests
for n in [1, 2, 3]:
    blocks.append(f"Request.h.v={n:08x}\nRequest.type=100\nRequest.group.v=00000001\nRequest.construction=0\nAddRequest".encode())
for n in range(4, 10):
    blocks.append(f"Request.h.v={n:08x}\nRequest.type=200\nRequest.workplane.v=80020000\nRequest.group.v=00000002\nRequest.construction=0\nAddRequest".encode())

# Reference entities
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

# Workplane
blocks += [
    b"Entity.h.v=80020000\nEntity.type=10000\nEntity.construction=0\nEntity.point[0].v=80020002\nEntity.normal.v=80020001\nEntity.actVisible=1\nAddEntity",
    b"Entity.h.v=80020001\nEntity.type=3010\nEntity.construction=0\nEntity.point[0].v=80020002\nEntity.actNormal.w=1.000000000000000000000\nEntity.actVisible=1\nAddEntity",
    b"Entity.h.v=80020002\nEntity.type=2012\nEntity.construction=1\nEntity.actVisible=1\nAddEntity",
]

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
def add_c(s):
    global ch
    blocks.append(s.encode())
    ch += 1

def add_coincident(ptA, ptB):
    add_c(f"Constraint.h.v={ch:08x}\nConstraint.type=20\nConstraint.group.v=00000002\nConstraint.workplane.v=80020000\nConstraint.ptA.v={ptA}\nConstraint.ptB.v={ptB}\nAddConstraint")

def add_horiz(ent):
    add_c(f"Constraint.h.v={ch:08x}\nConstraint.type=80\nConstraint.group.v=00000002\nConstraint.workplane.v=80020000\nConstraint.entityA.v={ent}\nAddConstraint")

def add_vert(ent):
    add_c(f"Constraint.h.v={ch:08x}\nConstraint.type=82\nConstraint.group.v=00000002\nConstraint.workplane.v=80020000\nConstraint.entityA.v={ent}\nAddConstraint")

def add_where_dragged(pt):
    add_c(f"Constraint.h.v={ch:08x}\nConstraint.type=200\nConstraint.group.v=00000002\nConstraint.workplane.v=80020000\nConstraint.ptA.v={pt}\nAddConstraint")

def add_distance(ptA, ptB, val):
    add_c(f"Constraint.h.v={ch:08x}\nConstraint.type=30\nConstraint.group.v=00000002\nConstraint.workplane.v=80020000\nConstraint.valA={val:.6f}\nConstraint.ptA.v={ptA}\nConstraint.ptB.v={ptB}\nAddConstraint")

# Close loop (reqs 4-9 → 0004-0009)
pairs = [
    ('00040002', '00050001'),
    ('00050002', '00060001'),
    ('00060002', '00070001'),
    ('00070002', '00080001'),
    ('00080002', '00090001'),
    ('00090002', '00040001'),
]
for ptA, ptB in pairs:
    add_coincident(ptA, ptB)

# H/V constraints: bottom(4), step(6), top(8) horizontal; right(5), inner-vert(7), left(9) vertical
for ent in ['00040000', '00060000', '00080000']:
    add_horiz(ent)
for ent in ['00050000', '00070000', '00090000']:
    add_vert(ent)

add_where_dragged('00040001')

# Current dimension constraints (to be updated per ECR)
# 1. total_width = 250 (ECR: 300)  — A to B
add_distance('00040001', '00040002', CUR_TOTAL_W)
# 2. total_height = 200 (ECR: 240) — A to F vertical
add_distance('00040001', '00090001', CUR_TOTAL_H)
# 3. leg_height = 100 (ECR: 130)   — A to D vertical (step height = C.y)
add_distance('00040001', '00060002', CUR_LEG_H)
# 4. wall_thickness = 50 (ECR: 70) — A to D horizontal (wall width)
add_distance('00040001', '00070002', CUR_WALL_T)

content = b'\n\n'.join(blocks) + b'\n'
outpath = '/home/ga/Documents/SolveSpace/duct_elbow_current.slvs'
with open(outpath, 'wb') as f:
    f.write(content)
print(f"Generated {outpath}: {os.path.getsize(outpath)} bytes")
PYEOF

chown ga:ga /home/ga/Documents/SolveSpace/duct_elbow_current.slvs

mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/ECR_2247_duct_elbow.txt << 'ECREOF'
ENGINEERING CHANGE REQUEST
ECR Number: ECR-HVAC-2247
Project: Office Block B — Level 4 Mechanical Services
Component: Rectangular Duct Elbow Cross-Section
Drawing Reference: HVAC-DWG-0884

REASON FOR CHANGE:
Increased air volume flow rate requirement due to occupancy revision.
All duct cross-section dimensions must be updated to accommodate
increased flow velocity per ASHRAE 90.1 requirements.

CURRENT VALUES → NEW VALUES (all dimensions in mm):
  Total duct width:       250 mm  →  300 mm
  Total duct height:      200 mm  →  240 mm
  Elbow leg height:       100 mm  →  130 mm
  Wall/web thickness:      50 mm  →   70 mm

All four parametric constraints in the SolveSpace file must be updated.
Save updated file as duct_elbow_updated.slvs and export DXF.

Tolerance: ±0.5 mm on all dimensions.
Approved by: Lead HVAC Engineer
ECREOF
chown ga:ga /home/ga/Desktop/ECR_2247_duct_elbow.txt

kill_solvespace

launch_solvespace "/home/ga/Documents/SolveSpace/duct_elbow_current.slvs"
echo "Waiting for SolveSpace to load..."
wait_for_solvespace 30
sleep 5

maximize_solvespace
sleep 1

take_screenshot /tmp/hvac_duct_elbow_ecr_update_start.png
echo "=== hvac_duct_elbow_ecr_update setup complete ==="
echo "L-shaped duct elbow loaded with 4 current dimension constraints."
echo "ECR document on Desktop specifies new target values."
