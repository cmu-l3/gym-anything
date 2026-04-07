#!/bin/bash
echo "=== Setting up constrain_u_channel_profile task ==="

source /workspace/scripts/task_utils.sh

mkdir -p /home/ga/Documents/SolveSpace
chown -R ga:ga /home/ga/Documents/SolveSpace

rm -f /home/ga/Documents/SolveSpace/u_channel_constrained.slvs 2>/dev/null || true
rm -f /home/ga/Documents/SolveSpace/u_channel_profile.slvs 2>/dev/null || true

date +%s > /tmp/constrain_u_channel_profile_start_ts

# Generate a U-channel (press-formed die insert) cross-section .slvs with
# geometry and topological constraints only — NO dimensional constraints.
# The agent must read the tooling design specification and apply all 5
# dimensional constraints before saving as u_channel_constrained.slvs.
#
# U-channel profile (8 lines, clockwise from bottom-left):
#   A=(0,0)     → B=(120,0)   req4:  bottom outer          [120mm wide]
#   B=(120,0)   → C=(120,70)  req5:  right outer leg        [70mm tall]
#   C=(120,70)  → D=(105,70)  req6:  top-right flange inner [15mm wide]
#   D=(105,70)  → E=(105,15)  req7:  right inner wall       [55mm tall]
#   E=(105,15)  → F=(15,15)   req8:  inner bottom           [90mm wide]
#   F=(15,15)   → G=(15,70)   req9:  left inner wall        [55mm tall]
#   G=(15,70)   → H=(0,70)    req10: top-left flange inner  [15mm wide]
#   H=(0,70)    → A=(0,0)     req11: left outer leg         [70mm tall]
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

# ── U-channel geometry ──
u_channel_lines = [
    (0.0,   0.0, 120.0,  0.0),  # req4:  A→B bottom outer
    (120.0,  0.0, 120.0, 70.0),  # req5:  B→C right outer leg
    (120.0, 70.0, 105.0, 70.0),  # req6:  C→D top-right flange
    (105.0, 70.0, 105.0, 15.0),  # req7:  D→E right inner wall
    (105.0, 15.0,  15.0, 15.0),  # req8:  E→F inner bottom
    (15.0,  15.0,  15.0, 70.0),  # req9:  F→G left inner wall
    (15.0,  70.0,   0.0, 70.0),  # req10: G→H top-left flange
    (0.0,   70.0,   0.0,  0.0),  # req11: H→A left outer leg
]

for i, (x0, y0, x1, y1) in enumerate(u_channel_lines):
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
for i, (x0, y0, x1, y1) in enumerate(u_channel_lines):
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

# COINCIDENT: close the 8-line U-channel loop
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

# ── Write file (NO dimensional constraints — agent must add them) ──
content = b'\n\n'.join(blocks) + b'\n'
outpath = '/home/ga/Documents/SolveSpace/u_channel_profile.slvs'
with open(outpath, 'wb') as f:
    f.write(content)
print(f"Generated {outpath}: {os.path.getsize(outpath)} bytes")
PYEOF

chown ga:ga /home/ga/Documents/SolveSpace/u_channel_profile.slvs

# ── Tooling design specification on desktop ──
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/tooling_design_spec.txt << 'SPECEOF'
TOOLING DESIGN SPECIFICATION
Part No:      TD-2024-0391
Description:  Press-formed U-channel die insert
Material:     D2 tool steel, hardened to 60-62 HRC
Finish:       Ground, Ra 0.8 µm
Department:   Tooling Engineering

CHANNEL CROSS-SECTION DIMENSIONS (all in mm):
  Overall channel width:          120 mm
  Channel leg height (outer):      70 mm
  Wall thickness (uniform):        15 mm  [each wall]
  Inner clear depth:               55 mm  (from inner ledge to inner base)
  Inner clear width (base):        90 mm  (bottom of the channel cavity)

CONSTRAINT REQUIREMENT:
  The 2D profile sketch must be fully dimensionally constrained before the
  file is passed to the CNC programming workstation for die machining.
  Apply all five dimensional constraints listed above.

Save the constrained file as:  u_channel_constrained.slvs

Note: Tolerance is ±0.02 mm (die tooling — high precision).
      Ensure no underdefined or conflicting constraints remain.
Issued by: Tooling Engineering Manager
SPECEOF
chown ga:ga /home/ga/Desktop/tooling_design_spec.txt

kill_solvespace
launch_solvespace "/home/ga/Documents/SolveSpace/u_channel_profile.slvs"

echo "Waiting for SolveSpace to load u_channel_profile.slvs..."
wait_for_solvespace 30
sleep 5

maximize_solvespace
sleep 1

take_screenshot /tmp/constrain_u_channel_profile_start.png
echo "=== constrain_u_channel_profile setup complete ==="
echo "U-channel loaded: 8 lines, H/V/coincident constraints, NO dimensional constraints."
echo "Tooling specification at /home/ga/Desktop/tooling_design_spec.txt"
