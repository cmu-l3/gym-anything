#!/bin/bash
# Export result for neurosurgical_case_conference_package task

echo "=== Exporting neurosurgical_case_conference_package result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
export TASK_START

python3 << 'PYEOF'
import struct, os, json, tarfile, plistlib, re, hashlib

output_dir       = "/home/ga/Documents/case_conference"
stl_path         = os.path.join(output_dir, "cortical_bone.stl")
ply_path         = os.path.join(output_dir, "soft_tissue.ply")
anterior_path    = os.path.join(output_dir, "anterior_view.png")
lateral_path     = os.path.join(output_dir, "lateral_view.png")
cross_section_path = os.path.join(output_dir, "cross_section.png")
inv3_path        = os.path.join(output_dir, "case_package.inv3")

task_start = int(os.environ.get("TASK_START", "0"))

result = {
    # STL (cortical bone)
    "stl_exists":           False,
    "stl_valid":            False,
    "stl_triangle_count":   0,
    "stl_size_bytes":       0,

    # PLY (soft tissue)
    "ply_exists":           False,
    "ply_valid":            False,
    "ply_vertex_count":     0,
    "ply_face_count":       0,
    "ply_size_bytes":       0,

    # PNG screenshots
    "anterior_png_exists":      False,
    "anterior_png_valid":       False,
    "anterior_png_size_bytes":  0,
    "lateral_png_exists":       False,
    "lateral_png_valid":        False,
    "lateral_png_size_bytes":   0,
    "cross_section_png_exists":     False,
    "cross_section_png_valid":      False,
    "cross_section_png_size_bytes": 0,

    # PNG uniqueness (anti-gaming)
    "png_hashes":           [],
    "pngs_distinct":        True,

    # Project
    "project_file_exists":  False,
    "project_valid_inv3":   False,
    "mask_count":           0,
    "surface_count":        0,
    "measurement_count":    0,
    "measurements":         [],
    "masks_detail":         [],
    "surfaces_detail":      [],

    # Angular measurement detection
    "angular_measurement_count": 0,
    "angular_values":       [],
}


# ── Helper: analyse binary STL ──────────────────────────────────────────────
def analyse_stl(path, res):
    if not os.path.isfile(path):
        return
    res["stl_exists"] = True
    res["stl_size_bytes"] = os.path.getsize(path)

    # Try binary STL
    if res["stl_size_bytes"] >= 84:
        try:
            with open(path, "rb") as f:
                f.read(80)
                cb = f.read(4)
                if len(cb) == 4:
                    count = struct.unpack("<I", cb)[0]
                    if abs((80 + 4 + count * 50) - res["stl_size_bytes"]) <= 512:
                        res["stl_valid"] = True
                        res["stl_triangle_count"] = count
        except Exception:
            pass

    # Fallback: ASCII STL
    if not res["stl_valid"]:
        try:
            with open(path, "r", errors="replace") as f:
                first = f.readline().strip().lower()
            if first.startswith("solid"):
                count = sum(
                    1 for ln in open(path, "r", errors="replace")
                    if ln.strip().lower().startswith("facet normal")
                )
                if count > 0:
                    res["stl_valid"] = True
                    res["stl_triangle_count"] = count
        except Exception:
            pass


# ── Helper: analyse PLY ─────────────────────────────────────────────────────
def analyse_ply(path, res):
    if not os.path.isfile(path):
        return
    res["ply_exists"] = True
    res["ply_size_bytes"] = os.path.getsize(path)
    try:
        with open(path, "rb") as f:
            header_raw = f.read(4096)
        header_text = header_raw.decode("ascii", errors="replace")
        lines = header_text.splitlines()
        if lines and lines[0].strip().lower().startswith("ply"):
            res["ply_valid"] = True
            for line in lines:
                line = line.strip()
                vm = re.match(r"element\s+vertex\s+(\d+)", line, re.IGNORECASE)
                if vm:
                    res["ply_vertex_count"] = int(vm.group(1))
                fm = re.match(r"element\s+face\s+(\d+)", line, re.IGNORECASE)
                if fm:
                    res["ply_face_count"] = int(fm.group(1))
    except Exception:
        pass


# ── Helper: analyse PNG ─────────────────────────────────────────────────────
def analyse_png(path, prefix, res):
    exists_key = f"{prefix}_exists"
    valid_key  = f"{prefix}_valid"
    size_key   = f"{prefix}_size_bytes"

    if not os.path.isfile(path):
        return
    res[exists_key] = True
    res[size_key] = os.path.getsize(path)
    try:
        with open(path, "rb") as f:
            header = f.read(8)
            if header[:4] == b"\x89PNG":
                res[valid_key] = True
            # Hash for uniqueness check
            f.seek(0)
            file_hash = hashlib.md5(f.read()).hexdigest()
            res["png_hashes"].append(file_hash)
    except Exception:
        pass


# ── Helper: analyse InVesalius project (.inv3) ───────────────────────────────
def analyse_inv3(path, res):
    if not os.path.isfile(path):
        return
    res["project_file_exists"] = True
    try:
        with tarfile.open(path, "r:gz") as t:
            res["project_valid_inv3"] = True
            mask_plists = {}
            surface_plists = {}

            for member in t.getmembers():
                bname = os.path.basename(member.name)

                if bname == "main.plist":
                    f = t.extractfile(member)
                    main = plistlib.load(f)
                    res["mask_count"] = len(main.get("masks", {}))
                    res["surface_count"] = len(main.get("surfaces", {}))

                elif bname.startswith("mask_") and bname.endswith(".plist"):
                    f = t.extractfile(member)
                    mask_plists[bname] = plistlib.load(f)

                elif bname.startswith("surface_") and bname.endswith(".plist"):
                    f = t.extractfile(member)
                    surface_plists[bname] = plistlib.load(f)

                elif bname == "measurements.plist":
                    f = t.extractfile(member)
                    meas_dict = plistlib.load(f)
                    res["measurement_count"] = len(meas_dict)
                    for idx, meas in meas_dict.items():
                        val = float(meas.get("value", 0))
                        mtype = str(meas.get("type", "")).lower()
                        points = meas.get("points", [])
                        res["measurements"].append({
                            "index": str(idx),
                            "value": val,
                            "type": mtype,
                            "point_count": len(points) if isinstance(points, list) else 0,
                        })

            # Extract mask threshold details
            for name, mp in mask_plists.items():
                tr = mp.get("threshold_range", [0, 0])
                min_hu = float(tr[0]) if len(tr) >= 1 else 0.0
                max_hu = float(tr[1]) if len(tr) >= 2 else 0.0
                res["masks_detail"].append({
                    "name": mp.get("name", name),
                    "min_hu": min_hu,
                    "max_hu": max_hu,
                })

            # Extract surface transparency details
            for name, sp in surface_plists.items():
                res["surfaces_detail"].append({
                    "name": sp.get("name", name),
                    "transparency": float(sp.get("transparency", 0.0)),
                })

    except Exception as e:
        res["project_parse_error"] = str(e)

    # Detect angular measurements
    for m in res["measurements"]:
        is_angle = False
        # Explicit type field
        if m["type"] in ("angle", "angular"):
            is_angle = True
        # Heuristic: 3-point measurements are angular
        elif m["point_count"] == 3 and "distance" not in m["type"]:
            is_angle = True
        if is_angle:
            res["angular_measurement_count"] += 1
            res["angular_values"].append(m["value"])


# ── Run all analyses ─────────────────────────────────────────────────────────
analyse_stl(stl_path, result)
analyse_ply(ply_path, result)
analyse_png(anterior_path, "anterior_png", result)
analyse_png(lateral_path, "lateral_png", result)
analyse_png(cross_section_path, "cross_section_png", result)
analyse_inv3(inv3_path, result)

# Check PNG uniqueness (anti-gaming: same file exported 3 times)
hashes = result["png_hashes"]
if len(hashes) > 1 and len(hashes) != len(set(hashes)):
    result["pngs_distinct"] = False

# Write result JSON
with open("/tmp/neurosurgical_case_conference_package_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

chmod 666 /tmp/neurosurgical_case_conference_package_result.json 2>/dev/null || true

echo "=== Export Complete ==="
