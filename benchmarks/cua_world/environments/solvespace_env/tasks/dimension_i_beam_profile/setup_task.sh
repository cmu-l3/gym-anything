#!/bin/bash
echo "=== Setting up dimension_i_beam_profile task ==="

source /workspace/scripts/task_utils.sh

mkdir -p /home/ga/Documents/SolveSpace
chown -R ga:ga /home/ga/Documents/SolveSpace

rm -f /home/ga/Documents/SolveSpace/i_beam_constrained.slvs 2>/dev/null || true
rm -f /home/ga/Documents/SolveSpace/i_beam_profile.slvs 2>/dev/null || true

date +%s > /tmp/dimension_i_beam_profile_start_ts

# Generate an asymmetric I-beam cross-section .slvs file with geometry and
# topological constraints ONLY — no dimensional (PT_PT_DISTANCE) constraints.
# The agent must read the structural specification and add all 8 dimensional
# constraints before saving as i_beam_constrained.slvs.
#
# Profile geometry (12 lines, clockwise from bottom-left):
#   A=(0,0)   → B=(120,0)   req4:  bottom flange bottom  [120mm wide]
#   B=(120,0)  → C=(120,12)  req5:  bottom-right flange  [12mm tall]
#   C=(120,12) → D=(80,12)   req6:  right inner notch    [40mm wide]
#   D=(80,12)  → E=(80,72)   req7:  right web face       [60mm tall]
#   E=(80,72)  → F=(120,72)  req8:  right inner notch top[40mm wide]
#   F=(120,72) → G=(120,90)  req9:  top-right flange     [18mm tall]
#   G=(120,90) → H=(0,90)    req10: top flange bottom    [120mm wide]
#   H=(0,90)   → I=(0,72)    req11: top-left flange      [18mm tall]
#   I=(0,72)   → J=(30,72)   req12: left inner notch top [30mm wide]
#   J=(30,72)  → K=(30,12)   req13: left web face        [60mm tall]
#   K=(30,12)  → L=(0,12)    req14: left inner notch bot [30mm wide]
#   L=(0,12)   → A=(0,0)     req15: bottom-left flange   [12mm tall]
python3 << 'PYEOF'
import os

MAGIC = b'\xb1\xb2\xb3SolveSpaceREVa'
blocks = []
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

# ── 12-line I-beam geometry ──
i_beam_lines = [
    (0.0,   0.0, 120.0,  0.0),   # req4:  A→B bottom flange
    (120.0,  0.0, 120.0, 12.0),  # req5:  B→C bottom-right flange
    (120.0, 12.0,  80.0, 12.0),  # req6:  C→D right inner notch
    (80.0,  12.0,  80.0, 72.0),  # req7:  D→E right web face
    (80.0,  72.0, 120.0, 72.0),  # req8:  E→F right inner notch top
    (120.0, 72.0, 120.0, 90.0),  # req9:  F→G top-right flange
    (120.0, 90.0,   0.0, 90.0),  # req10: G→H top flange
    (0.0,   90.0,   0.0, 72.0),  # req11: H→I top-left flange
    (0.0,   72.0,  30.0, 72.0),  # req12: I→J left inner notch top
    (30.0,  72.0,  30.0, 12.0),  # req13: J→K left web face
    (30.0,  12.0,   0.0, 12.0),  # req14: K→L left inner notch
    (0.0,   12.0,   0.0,  0.0),  # req15: L→A bottom-left flange
]

for i, (x0, y0, x1, y1) in enumerate(i_beam_lines):
    rn = i + 4
    ph = f'{rn:04x}'
    blocks.append(f"Param.h.v.=00{ph}0010\nParam.val={fmt(x0)}\nAddParam".encode())
    blocks.append(f"Param.h.v.=00{ph}0011\nParam.val={fmt(y0)}\nAddParam".encode())
    blocks.append(f"Param.h.v.=00{ph}0013\nParam.val={fmt(x1)}\nAddParam".encode())
    blocks.append(f"Param.h.v.=00{ph}0014\nParam.val={fmt(y1)}\nAddParam".encode())

# ── Requests ──
for n in [1, 2, 3]:
    blocks.append(f"Request.h.v={n:08x}\nRequest.type=100\nRequest.group.v=00000001\nRequest.construction=0\nAddRequest".encode())
for n in range(4, 16):
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
for i, (x0, y0, x1, y1) in enumerate(i_beam_lines):
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

# COINCIDENT: close the 12-line I-beam loop
pairs = [
    ('00040002', '00050001'),  # B
    ('00050002', '00060001'),  # C
    ('00060002', '00070001'),  # D
    ('00070002', '00080001'),  # E
    ('00080002', '00090001'),  # F
    ('00090002', '000a0001'),  # G
    ('000a0002', '000b0001'),  # H
    ('000b0002', '000c0001'),  # I
    ('000c0002', '000d0001'),  # J
    ('000d0002', '000e0001'),  # K
    ('000e0002', '000f0001'),  # L
    ('000f0002', '00040001'),  # back to A
]
for ptA, ptB in pairs:
    add_c(20, f"Constraint.ptA.v={ptA}\nConstraint.ptB.v={ptB}\n")

# HORIZONTAL: req4 (A→B), req6 (C→D), req8 (E→F), req10 (G→H), req12 (I→J), req14 (K→L)
for ent in ['00040000', '00060000', '00080000', '000a0000', '000c0000', '000e0000']:
    add_c(80, f"Constraint.entityA.v={ent}\n")

# VERTICAL: req5 (B→C), req7 (D→E), req9 (F→G), req11 (H→I), req13 (J→K), req15 (L→A)
for ent in ['00050000', '00070000', '00090000', '000b0000', '000d0000', '000f0000']:
    add_c(82, f"Constraint.entityA.v={ent}\n")

# WHERE_DRAGGED: pin A=(0,0) so sketch is fully located
add_c(200, "Constraint.ptA.v=00040001\n")

# ── Write file ──
content = b'\n\n'.join(blocks) + b'\n'
outpath = '/home/ga/Documents/SolveSpace/i_beam_profile.slvs'
with open(outpath, 'wb') as f:
    f.write(content)
print(f"Generated {outpath}: {os.path.getsize(outpath)} bytes")
PYEOF

chown ga:ga /home/ga/Documents/SolveSpace/i_beam_profile.slvs

# ── Structural specification on desktop ──
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/i_beam_specification.txt << 'SPECEOF'
STRUCTURAL CROSS-SECTION SCHEDULE
Project: Warehouse Extension — Bay 4 to Bay 7
Drawing Reference: STE-2024-047-REV-C
Prepared by: Structural Engineering Department
Approved: 2024-09-12

SECTION TYPE: Asymmetric I-beam (custom fabricated)
Material: S275JR structural steel
Application: Secondary purlin support — roof frame

CROSS-SECTION DIMENSIONS (all in mm):
  Overall flange width:         120 mm
  Overall section height:        90 mm
  Bottom flange thickness:       12 mm
  Top flange thickness:          18 mm
  Right flange overhang:         40 mm  (outer face to right web edge)
  Left flange overhang:          30 mm  (outer face to left web edge)
  Web clear height:              60 mm  (inner, flange-to-flange)
  Web thickness:                 50 mm

NOTE: All eight dimensional constraints listed above must be applied to the
open sketch before the file can be submitted to the structural analysis team.

Save the constrained file as:  i_beam_constrained.slvs

Tolerance: ±0.5 mm per BS EN 10034
SPECEOF
chown ga:ga /home/ga/Desktop/i_beam_specification.txt

kill_solvespace
launch_solvespace "/home/ga/Documents/SolveSpace/i_beam_profile.slvs"

echo "Waiting for SolveSpace to load i_beam_profile.slvs..."
wait_for_solvespace 30
sleep 5

maximize_solvespace
sleep 1

take_screenshot /tmp/dimension_i_beam_profile_start.png
echo "=== dimension_i_beam_profile setup complete ==="
echo "Asymmetric I-beam loaded: 12 lines, H/V/coincident constraints only, NO dimensional constraints."
echo "Structural specification at /home/ga/Desktop/i_beam_specification.txt"
