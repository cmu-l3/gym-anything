#!/bin/bash
# Export evidence for multicriteria_suitability_mapping verification
# Collects DIMAP XML parsing, GeoTIFF inspection, file timestamps

set -e

# Source shared utilities if available
if [ -f /workspace/utils/task_utils.sh ]; then
    source /workspace/utils/task_utils.sh
fi

# Take end screenshot
echo "Taking end screenshot..."
if type take_screenshot &>/dev/null; then
    take_screenshot /tmp/suitability_task_end_screenshot.png
else
    DISPLAY=:1 scrot /tmp/suitability_task_end_screenshot.png 2>/dev/null || true
fi

# Collect evidence via Python
python3 << 'PYEOF'
import json
import os
import glob
import time

try:
    import xml.etree.ElementTree as ET
except ImportError:
    ET = None

result = {
    # DIMAP evidence
    "dimap_found": False,
    "dimap_path": "",
    "dimap_timestamp_ok": False,
    "band_names": [],
    "band_expressions": {},
    "band_count": 0,
    "processing_history_nodes": [],
    # Collocation evidence
    "has_master_suffix_bands": False,
    "has_slave_suffix_bands": False,
    "collocation_in_history": False,
    "master_band_names": [],
    "slave_band_names": [],
    # NDVI evidence
    "has_ndvi_band": False,
    "ndvi_expression": "",
    "ndvi_references_nir_red": False,
    # Suitability classification evidence
    "has_suitability_band": False,
    "suitability_expression": "",
    "suitability_has_conditional": False,
    "suitability_references_ndvi": False,
    "suitability_references_elevation": False,
    "suitability_has_classes_123": False,
    # GeoTIFF evidence
    "geotiff_found": False,
    "geotiff_path": "",
    "geotiff_size_bytes": 0,
    "geotiff_timestamp_ok": False,
    "geotiff_dimensions": [],
    "geotiff_pixel_values": [],
    # Subset evidence
    "subset_dimensions_approx_200x200": False,
}

# Read task start timestamp
task_start = 0
ts_file = "/tmp/suitability_task_start_ts"
if os.path.exists(ts_file):
    try:
        with open(ts_file) as f:
            task_start = int(f.read().strip())
    except (ValueError, IOError):
        pass

# ── Search for BEAM-DIMAP files ──
search_dirs = [
    "/home/ga/snap_projects",
    "/home/ga/Desktop",
    "/home/ga",
    "/tmp",
]
skip_dirs = {"snap_data", ".snap", ".local", ".cache"}

dim_files = []
for search_dir in search_dirs:
    if not os.path.isdir(search_dir):
        continue
    for root, dirs, files in os.walk(search_dir):
        dirs[:] = [d for d in dirs if d not in skip_dirs]
        for f in files:
            if f.endswith(".dim"):
                dim_files.append(os.path.join(root, f))

# Prioritize expected path, then any suitability-named file, then newest
expected_dim = "/home/ga/snap_projects/suitability_assessment.dim"
if os.path.exists(expected_dim):
    chosen_dim = expected_dim
elif dim_files:
    suit_files = [p for p in dim_files if "suit" in os.path.basename(p).lower()]
    if suit_files:
        chosen_dim = max(suit_files, key=os.path.getmtime)
    else:
        chosen_dim = max(dim_files, key=os.path.getmtime)
else:
    chosen_dim = None

if chosen_dim and os.path.exists(chosen_dim):
    result["dimap_found"] = True
    result["dimap_path"] = chosen_dim
    try:
        mtime = os.path.getmtime(chosen_dim)
        result["dimap_timestamp_ok"] = mtime > task_start
    except OSError:
        pass

    # Parse DIMAP XML
    if ET is not None:
        try:
            tree = ET.parse(chosen_dim)
            root = tree.getroot()

            # Extract band information
            bands = []
            expressions = {}
            for sbi in root.iter("Spectral_Band_Info"):
                bname_el = sbi.find("BAND_NAME")
                bexpr_el = sbi.find("VIRTUAL_BAND_EXPRESSION")
                if bname_el is not None and bname_el.text:
                    bname = bname_el.text.strip()
                    bands.append(bname)
                    if bexpr_el is not None and bexpr_el.text:
                        expressions[bname] = bexpr_el.text.strip()

            result["band_names"] = bands
            result["band_expressions"] = expressions
            result["band_count"] = len(bands)

            # Check for collocation suffixes
            master_bands = [b for b in bands if b.lower().endswith("_m") or "_M" in b]
            slave_bands = [b for b in bands if b.lower().endswith("_s") or "_S" in b]
            result["master_band_names"] = master_bands
            result["slave_band_names"] = slave_bands
            result["has_master_suffix_bands"] = len(master_bands) > 0
            result["has_slave_suffix_bands"] = len(slave_bands) > 0

            # Check processing history for Collocation
            for node in root.iter("node"):
                node_id = node.get("id", "")
                if node_id:
                    result["processing_history_nodes"].append(node_id)
            # Also check Node_Id elements
            for nid in root.iter("Node_Id"):
                if nid.text:
                    result["processing_history_nodes"].append(nid.text.strip())
            # Check raw content for "Collocate" as fallback
            try:
                with open(chosen_dim, "r", errors="ignore") as rf:
                    raw = rf.read()
                    if "Collocate" in raw or "collocate" in raw.lower():
                        result["collocation_in_history"] = True
            except IOError:
                pass
            if any("collocat" in n.lower() for n in result["processing_history_nodes"]):
                result["collocation_in_history"] = True

            # ── NDVI band evidence ──
            ndvi_keywords = ["ndvi", "nir_red_index", "vegetation_index"]
            for bname in bands:
                if any(kw in bname.lower() for kw in ndvi_keywords):
                    result["has_ndvi_band"] = True
                    expr = expressions.get(bname, "")
                    result["ndvi_expression"] = expr
                    el = expr.lower().replace(" ", "")
                    # Check for normalized difference pattern with NIR and Red refs
                    has_division = "/" in el
                    has_subtraction = "-" in el
                    # Check for band references (B2_M, band_2, nir, etc.)
                    nir_refs = ["b2_m", "band_2_m", "b2", "band_2", "nir"]
                    red_refs = ["b3_m", "band_3_m", "b3", "band_3", "red"]
                    has_nir = any(r in el for r in nir_refs)
                    has_red = any(r in el for r in red_refs)
                    result["ndvi_references_nir_red"] = has_division and has_subtraction and has_nir and has_red
                    break

            # ── Suitability classification band evidence ──
            class_keywords = ["suitability", "class", "zone", "category", "land_use", "develop"]
            for bname in bands:
                if any(kw in bname.lower() for kw in class_keywords):
                    result["has_suitability_band"] = True
                    expr = expressions.get(bname, "")
                    result["suitability_expression"] = expr
                    el = expr.lower().replace(" ", "")
                    # Check for conditional logic
                    result["suitability_has_conditional"] = ("?" in el and ":" in el) or \
                        ("if" in el) or ("&&" in el and ("?" in el or "if" in el))
                    # Check for NDVI reference in expression
                    result["suitability_references_ndvi"] = "ndvi" in el
                    # Check for elevation band reference
                    elev_refs = ["elevation_s", "elevation", "band_1_s", "dem", "srtm", "height", "elev"]
                    result["suitability_references_elevation"] = any(r in el for r in elev_refs)
                    # Check for class values 1, 2, 3
                    has_1 = "1" in el
                    has_2 = "2" in el
                    has_3 = "3" in el
                    result["suitability_has_classes_123"] = has_1 and has_2 and has_3
                    break

        except ET.ParseError:
            pass
        except Exception as e:
            result["parse_error"] = str(e)

# ── Search for GeoTIFF files ──
tif_search_dirs = [
    "/home/ga/snap_exports",
    "/home/ga/Desktop",
    "/home/ga/snap_projects",
    "/home/ga",
]
tif_files = []
for search_dir in tif_search_dirs:
    if not os.path.isdir(search_dir):
        continue
    for root, dirs, files in os.walk(search_dir):
        dirs[:] = [d for d in dirs if d not in skip_dirs]
        for f in files:
            if f.endswith((".tif", ".tiff")):
                fp = os.path.join(root, f)
                try:
                    if os.path.getmtime(fp) > task_start:
                        tif_files.append(fp)
                except OSError:
                    tif_files.append(fp)

# Prioritize expected path, then subset/suitability-named, then newest
expected_tif = "/home/ga/snap_exports/suitability_subset.tif"
if os.path.exists(expected_tif):
    chosen_tif = expected_tif
elif tif_files:
    suit_tifs = [p for p in tif_files if any(k in os.path.basename(p).lower() for k in ["suit", "subset", "class"])]
    if suit_tifs:
        chosen_tif = max(suit_tifs, key=os.path.getmtime)
    else:
        chosen_tif = max(tif_files, key=os.path.getmtime)
else:
    chosen_tif = None

if chosen_tif and os.path.exists(chosen_tif):
    result["geotiff_found"] = True
    result["geotiff_path"] = chosen_tif
    try:
        result["geotiff_size_bytes"] = os.path.getsize(chosen_tif)
        mtime = os.path.getmtime(chosen_tif)
        result["geotiff_timestamp_ok"] = mtime > task_start
    except OSError:
        pass

    # Try to read GeoTIFF dimensions and sample pixel values
    try:
        from PIL import Image
        img = Image.open(chosen_tif)
        w, h = img.size
        result["geotiff_dimensions"] = [w, h]
        # Check if dimensions are approximately 200x200 (subset)
        result["subset_dimensions_approx_200x200"] = (
            abs(w - 200) <= 20 and abs(h - 200) <= 20
        )
        # Sample some pixel values to check classification range
        import numpy as np
        arr = np.array(img)
        unique_vals = sorted(set(arr.flatten().tolist()))
        # Only keep first 20 unique values to avoid huge output
        result["geotiff_pixel_values"] = unique_vals[:20]
    except ImportError:
        pass
    except Exception as e:
        result["geotiff_read_error"] = str(e)

# Write result
output_path = "/tmp/suitability_task_result.json"
with open(output_path, "w") as f:
    json.dump(result, f, indent=2)

print(f"Evidence collected -> {output_path}")
PYEOF

echo "=== Export complete ==="
