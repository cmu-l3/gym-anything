#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Earthquake Emergency Response: Setup ==="

# ── Wait for OpenMaint ──────────────────────────────────────────────
if ! wait_for_openmaint 240; then
  echo "ERROR: OpenMaint did not become ready" >&2
  exit 1
fi
echo "OpenMaint is ready."

# ── Delete stale outputs BEFORE recording timestamp ─────────────────
rm -f /tmp/eq_baseline.json /tmp/eq_result.json /tmp/eq_final_screenshot.png
rm -f /home/ga/Desktop/earthquake_assessment.txt

# ── Seed data and record baseline via API ───────────────────────────
python3 << 'PYEOF'
import sys, json, time, os, re
sys.path.insert(0, "/workspace/scripts")
from cmdbuild_api import *

token = get_token()
if not token:
    print("ERROR: Could not authenticate to CMDBuild API", file=sys.stderr)
    with open("/tmp/eq_baseline.json", "w") as f:
        json.dump({"error": "auth_failed"}, f)
    sys.exit(0)

# ── Discover classes ────────────────────────────────────────────────
building_cls = find_class(r"^Building$", token) or find_class(r"^Buildings$", token)
floor_cls    = find_class(r"^Floor$", token) or find_class(r"^Level$", token)
room_cls     = find_class(r"^Room$", token) or find_class(r"^Space$", token)

if not building_cls or not floor_cls or not room_cls:
    print("CRITICAL: Could not find spatial classes", file=sys.stderr)
    with open("/tmp/eq_baseline.json", "w") as f:
        json.dump({"error": "missing_spatial_classes",
                    "building_cls": building_cls,
                    "floor_cls": floor_cls,
                    "room_cls": room_cls}, f)
    sys.exit(0)

# Discover reference fields by introspecting class attributes
def discover_ref_field(cls, target_keyword, token):
    """Find a reference attribute whose name contains target_keyword."""
    try:
        attrs = get_class_attributes(cls, token)
        for a in attrs:
            if target_keyword.lower() in a.get("_id", "").lower():
                return a["_id"]
    except Exception as e:
        print(f"WARNING: Could not introspect {cls}: {e}", file=sys.stderr)
    return target_keyword  # fallback: use keyword as field name

floor_ref_building = discover_ref_field(floor_cls, "Building", token)
room_ref_floor     = discover_ref_field(room_cls, "Floor", token)
print(f"Reference fields: floor->building={floor_ref_building}, room->floor={room_ref_floor}")

# Discover work order class
wo_type, wo_cls = None, None
try:
    wo_type, wo_cls = find_maintenance_class(token)
except Exception as e:
    print(f"WARNING: Could not find maintenance class: {e}", file=sys.stderr)

# ── Get buildings ───────────────────────────────────────────────────
buildings = get_buildings(token)
if len(buildings) < 3:
    print(f"WARNING: Only {len(buildings)} buildings found, need at least 3", file=sys.stderr)
    with open("/tmp/eq_baseline.json", "w") as f:
        json.dump({"error": "insufficient_buildings", "count": len(buildings)}, f)
    sys.exit(0)

print(f"Found {len(buildings)} buildings:")
for b in buildings:
    print(f"  {b.get('Code','?')} — {b.get('Description','?')}")

# ── Assign damage levels ────────────────────────────────────────────
# Deterministic assignment based on position:
#   buildings[0] = Severe
#   buildings[1] = Moderate
#   buildings[2] = Minor  (designated EOC)
#   buildings[3] = Severe  (if exists)
#   buildings[4] = Minor   (if exists)
damage_assignments = []
severity_order = ["severe", "moderate", "minor", "severe", "minor"]

for i, bld in enumerate(buildings):
    sev = severity_order[i] if i < len(severity_order) else "minor"
    is_eoc = (i == 2)  # third building is the EOC
    damage_assignments.append({
        "id":          bld["_id"],
        "code":        bld.get("Code", ""),
        "name":        bld.get("Description", ""),
        "address":     bld.get("Address", ""),
        "city":        bld.get("City", ""),
        "severity":    sev,
        "is_eoc":      is_eoc,
        "original_description": bld.get("Description", ""),
    })

severe_blds   = [d for d in damage_assignments if d["severity"] == "severe"]
moderate_blds = [d for d in damage_assignments if d["severity"] == "moderate"]
minor_blds    = [d for d in damage_assignments if d["severity"] == "minor"]
eoc_bld       = next(d for d in damage_assignments if d["is_eoc"])

# ── Discover WO attribute fields ────────────────────────────────────
# For process classes, use get_process_attributes; for card classes, use get_class_attributes
priority_field = "Priority"
building_field = "Site"
subject_field  = "ShortDescr"

if wo_cls:
    try:
        if wo_type == "process":
            attrs = get_process_attributes(wo_cls, token)
        else:
            attrs = get_class_attributes(wo_cls, token)
        for a in attrs:
            alow = a.get("_id", "").lower()
            adesc = a.get("description", "").lower()
            if "priority" in alow and a.get("_id") != "IdClass":
                priority_field = a["_id"]
            if "site" in alow or ("building" in alow and "ci" not in alow):
                building_field = a["_id"]
            if "shortdescr" in alow or "subject" in alow:
                subject_field = a["_id"]
        print(f"WO fields: priority={priority_field}, building={building_field}, subject={subject_field}")
    except Exception as e:
        print(f"WARNING: Could not get WO attributes: {e}", file=sys.stderr)

# ── Create contamination-trap work order: WO-SEISMIC-TEST ──────────
contam_wo_id = None
contam_subject = "WO-SEISMIC-TEST: Annual seismic sensor calibration"
contam_notes = "Routine quarterly check of triaxial accelerometers and data loggers — All buildings"
if wo_type and wo_cls:
    contam_data = {subject_field: contam_subject, "Notes": contam_notes}
    if priority_field:
        contam_data[priority_field] = "low"
    try:
        contam_wo_id = create_record(wo_type, wo_cls, contam_data, token)
        print(f"Created contamination trap WO-SEISMIC-TEST (id={contam_wo_id})")
    except Exception as e:
        print(f"WARNING: Could not create WO-SEISMIC-TEST: {e}", file=sys.stderr)

# ── Record baseline ─────────────────────────────────────────────────
# Existing WO IDs
existing_wo_ids = []
if wo_type and wo_cls:
    try:
        if wo_type == "process":
            existing_wos = get_process_instances(wo_cls, token, limit=500)
        else:
            existing_wos = get_cards(wo_cls, token, limit=500)
        existing_wo_ids = [w["_id"] for w in existing_wos if "_id" in w]
    except Exception:
        pass

# Existing Floor IDs
existing_floor_ids = []
try:
    existing_floors = get_cards(floor_cls, token, limit=500)
    existing_floor_ids = [f["_id"] for f in existing_floors if "_id" in f]
except Exception:
    pass

# Existing Room IDs
existing_room_ids = []
try:
    existing_rooms = get_cards(room_cls, token, limit=500)
    existing_room_ids = [r["_id"] for r in existing_rooms if "_id" in r]
except Exception:
    pass

baseline = {
    "building_cls":       building_cls,
    "floor_cls":          floor_cls,
    "room_cls":           room_cls,
    "floor_ref_building": floor_ref_building,
    "room_ref_floor":     room_ref_floor,
    "wo_type":            wo_type,
    "wo_cls":             wo_cls,
    "priority_field":     priority_field,
    "building_field":     building_field,
    "buildings":          damage_assignments,
    "eoc_building_id":    eoc_bld["id"],
    "eoc_building_code":  eoc_bld["code"],
    "contam_wo_id":       contam_wo_id,
    "contam_wo_subject":  contam_subject if contam_wo_id else "",
    "subject_field":      subject_field,
    "existing_wo_ids":    existing_wo_ids,
    "existing_floor_ids": existing_floor_ids,
    "existing_room_ids":  existing_room_ids,
}

with open("/tmp/eq_baseline.json", "w") as f:
    json.dump(baseline, f, indent=2, default=str)
print("Baseline saved to /tmp/eq_baseline.json")

# ── Generate the earthquake assessment report ───────────────────────
# Build damage findings per severity
findings_severe = [
    "Visible diagonal cracking in load-bearing masonry walls. Partial spalling\n   of concrete column caps in parking structure. Foundation settlement detected\n   (8mm differential). Building deemed UNSAFE for occupancy.\n   Required Action: Structural engineering assessment and column shoring.",
    "Curtain wall glass fracture on east facade. Fire suppression riser cracked\n   with active water leak in mechanical room. Electrical switchgear shifted off\n   mounting bolts in basement. Building deemed UNSAFE for occupancy.\n   Required Action: Immediate structural and fire protection assessment."
]
findings_moderate = [
    "HVAC ductwork separation on rooftop units. Elevator safety switch tripped\n   (car stuck between floors). Sprinkler branch line fracture in server room\n   causing minor water ingress. No structural damage observed.\n   Required Action: MEP systems inspection and restoration by licensed contractors."
]
findings_minor = [
    "Cosmetic ceiling tile displacement in conference room. No structural,\n   mechanical, or electrical damage detected.\n   Required Action: None. Visual inspection cleared.",
    "Hairline cosmetic crack in stairwell plaster. All systems operational.\n   Required Action: None. Visual inspection cleared."
]

report_lines = []
report_lines.append("STRUCTURAL ASSESSMENT REPORT — POST-EARTHQUAKE")
report_lines.append("Magnitude 5.4 | March 22, 2026 at 03:00 AM")
report_lines.append("Prepared by: Martinez Engineering, P.E. | Report #: SA-2026-0322")
report_lines.append("=" * 73)
report_lines.append("")
report_lines.append("BUILDING ASSESSMENTS")
report_lines.append("-" * 20)
report_lines.append("")

sev_idx = 0
mod_idx = 0
min_idx = 0
for i, da in enumerate(damage_assignments):
    n = i + 1
    name = da["name"]
    city = da["city"]
    label = name
    if city:
        label = f"{name} ({city})"

    sev_upper = da["severity"].upper()

    if da["severity"] == "severe":
        finding = findings_severe[sev_idx % len(findings_severe)]
        sev_idx += 1
    elif da["severity"] == "moderate":
        finding = findings_moderate[mod_idx % len(findings_moderate)]
        mod_idx += 1
    else:
        finding = findings_minor[min_idx % len(findings_minor)]
        min_idx += 1

    report_lines.append(f"{n}. {label}")
    report_lines.append(f"   DAMAGE CLASSIFICATION: {sev_upper}")
    report_lines.append(f"   Findings: {finding}")

    if da["is_eoc"]:
        report_lines.append("")
        report_lines.append("   ** DESIGNATED EMERGENCY OPERATIONS CENTER (EOC) **")
        report_lines.append("   Establish temporary EOC floor with: Command Room, Communications Hub,")
        report_lines.append("   and Supply Staging area.")

    report_lines.append("")

report_text = "\n".join(report_lines)

report_path = "/home/ga/Desktop/earthquake_assessment.txt"
with open(report_path, "w") as f:
    f.write(report_text)
os.chmod(report_path, 0o644)
try:
    import subprocess
    subprocess.run(["chown", "ga:ga", report_path], check=False)
except Exception:
    pass

print(f"Assessment report written to {report_path}")
PYEOF

echo "Python setup complete."

# ── Record start timestamp ──────────────────────────────────────────
rm -f /tmp/eq_start_ts
date +%s > /tmp/eq_start_ts
chmod 666 /tmp/eq_start_ts

# ── Relaunch Firefox at OpenMaint ───────────────────────────────────
pkill -f firefox || true
sleep 2
su - ga -c "DISPLAY=:1 firefox --no-remote '$OPENMAINT_URL' &"
sleep 5
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

echo "=== Setup complete ==="
