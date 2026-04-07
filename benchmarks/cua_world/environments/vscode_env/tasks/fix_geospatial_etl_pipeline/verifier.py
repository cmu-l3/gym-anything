#!/usr/bin/env python3
"""
Verifier for the fix_geospatial_etl_pipeline task.

Checks whether the agent identified and fixed 5 bugs in the geospatial
data processing pipeline used for zoning compliance analysis.

Each fix is worth 20 points (total 100).  Pass threshold: 60.
"""

import sys
import os
import json
import re
import hashlib
import logging
import tempfile
import shutil

sys.path.insert(
    0,
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../", "utils"),
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ──────────────────────────────────────────────────────────
# Helper utilities
# ──────────────────────────────────────────────────────────

def _safe_get(data, key):
    """Return file content from the result dict, or empty string."""
    val = data.get(key)
    return val if isinstance(val, str) else ""


def _md5(text):
    return hashlib.md5(text.encode("utf-8")).hexdigest()


# ──────────────────────────────────────────────────────────
# Individual bug checks (20 pts each)
# ──────────────────────────────────────────────────────────

def check_coord_order_fix(src):
    """
    Bug 1 -- Swapped lat/lng in coordinate_transform.py (20 pts)

    The original code treats coord[0] as latitude and coord[1] as longitude,
    but GeoJSON uses [longitude, latitude].  The fix should assign:
        lng/lon/longitude = coord[0]   and   lat/latitude = coord[1]
    or at minimum swap the assignments so coord[0] is NOT latitude.
    """
    if not src:
        return False, "coordinate_transform.py is missing or empty"

    # --- Check that the bug is gone ---
    # The original buggy pattern: lat = coord[0] ... lng = coord[1]
    # (with coord[0] being assigned to lat on the SAME line or near it)
    bug_pat_lat0 = re.search(r'lat\s*=\s*coord\[0\]', src)
    bug_pat_lng1 = re.search(r'lng\s*=\s*coord\[1\]', src)

    # --- Check that the fix is present ---
    # Correct: lng/lon/longitude = coord[0]  AND  lat/latitude = coord[1]
    fix_lng0 = re.search(r'(?:lng|lon|longitude)\s*=\s*coord\[0\]', src)
    fix_lat1 = re.search(r'(?:lat|latitude)\s*=\s*coord\[1\]', src)

    if fix_lng0 and fix_lat1:
        return True, "coordinate_transform.py correctly maps coord[0]->lng, coord[1]->lat"

    # Alternative: the user may have rewritten the function entirely
    # and no longer uses coord[0]/coord[1] directly.  If the old bug
    # pattern is gone and there is evidence of correct ordering, accept it.
    if not bug_pat_lat0 and not bug_pat_lng1:
        # Look for any evidence the developer addressed the coordinate order
        if re.search(r'(?:lng|lon|longitude)', src, re.IGNORECASE):
            return True, "coordinate_transform.py no longer has swapped lat/lng"

    if bug_pat_lat0 and bug_pat_lng1:
        return False, "coordinate_transform.py still has lat=coord[0], lng=coord[1] (swapped)"

    # Partial: one was fixed but not the other -- still give credit
    if fix_lng0 or fix_lat1:
        return True, "coordinate_transform.py partially corrected coordinate order"

    return False, "coordinate_transform.py coordinate order could not be verified as fixed"


def check_metric_buffer(src):
    """
    Bug 2 -- Buffer in degrees instead of meters in spatial_operations.py (20 pts)

    The original code applies distance_meters directly in degree-space.
    The fix should convert meters to degrees (using latitude-aware factor
    like 111320 m/deg) or project to a metric CRS before buffering.
    """
    if not src:
        return False, "spatial_operations.py is missing or empty"

    # The original bug: scale = (dist + distance_meters) / dist
    # where distance_meters (~500) is added to a tiny degree-based dist (~0.005)
    bug_pattern = re.search(
        r'dist\s*\+\s*distance_meters\s*\)\s*/\s*dist', src
    )

    # Patterns that indicate a correct fix
    fix_patterns = [
        r'111[,.]?3[12]\d',           # meters-per-degree constant (~111320)
        r'meters_per_degree',          # named variable
        r'deg_per_meter',              # named variable (inverse)
        r'meter.*degree|degree.*meter',# conversion mentioned
        r'UTM|utm|EPSG:326',          # projection to metric CRS
        r'project|reproject',          # reprojection
        r'math\.cos.*math\.radians',   # latitude-aware degree conversion
        r'distance_meters\s*/\s*\(',   # dividing meters by something (conversion)
        r'distance_deg',               # converted distance in degrees
        r'buffer_deg',                 # buffer converted to degrees
    ]

    has_fix = any(re.search(p, src, re.IGNORECASE) for p in fix_patterns)

    if has_fix:
        return True, "spatial_operations.py correctly converts buffer distance to metric/projected units"

    if bug_pattern:
        return False, "spatial_operations.py still adds raw meter distance to degree-based coordinates"

    # If the original pattern is gone but we can't find an explicit fix,
    # check if the function was substantially rewritten
    if 'create_buffer' in src and not bug_pattern:
        return True, "spatial_operations.py create_buffer was rewritten (original bug removed)"

    return False, "spatial_operations.py buffer fix could not be verified"


def check_projected_area(src):
    """
    Bug 3 -- Area on geographic CRS in area_calculator.py (20 pts)

    The original Shoelace formula operates on raw WGS84 degree coordinates,
    giving square-degree results.  The fix should project coordinates to
    an equal-area / metric CRS, or use a geodesic area formula (e.g.
    using Earth's radius 6371000).
    """
    if not src:
        return False, "area_calculator.py is missing or empty"

    # Patterns indicating a correct fix
    fix_patterns = [
        r'6371\d{3}',                     # Earth radius in meters
        r'6378137',                        # WGS84 semi-major axis
        r'utm|UTM|EPSG:326',             # UTM projection
        r'EPSG:6933|equal.area',          # Equal-area projection
        r'project|reproject|transform',    # Coordinate transformation
        r'math\.radians',                  # Converting degrees to radians for geodesic calc
        r'radians',                        # Radians usage in area context
        r'meters_per_degree|111[,.]?3[12]',# Degree-to-meter conversion
        r'geodesic|spherical',            # Geodesic area method
        r'cos\(.*lat',                    # Latitude-dependent scaling
    ]

    has_fix = any(re.search(p, src, re.IGNORECASE) for p in fix_patterns)

    if has_fix:
        return True, "area_calculator.py uses projected or geodesic area calculation"

    # Check if the raw Shoelace-on-degrees bug is still present
    # The original just does: area += coords[i][0] * coords[j][1]
    # without any conversion
    has_raw_shoelace = bool(re.search(
        r'polygon_coords\[i\]\[0\]\s*\*\s*polygon_coords\[j\]\[1\]', src
    ))

    if has_raw_shoelace:
        return False, "area_calculator.py still uses Shoelace formula on raw degree coordinates"

    # If the raw pattern is gone, the function was likely rewritten
    if 'calculate_area' in src and not has_raw_shoelace:
        return True, "area_calculator.py calculate_area was rewritten (original bug removed)"

    return False, "area_calculator.py area projection fix could not be verified"


def check_epsilon_comparison(src):
    """
    Bug 4 -- Exact float comparison in topology_validator.py (20 pts)

    The original code uses `d1 == 0` for collinear checks and exact
    coordinate comparisons.  The fix should use epsilon-based comparison
    such as abs(d1) < tolerance or abs(a - b) < 1e-10.
    """
    if not src:
        return False, "topology_validator.py is missing or empty"

    # The original bug: exact `== 0` for floating-point cross products
    has_exact_zero = bool(re.search(r'd[1234]\s*==\s*0(?!\.\d)', src))

    # Patterns indicating a correct fix — must be specific to
    # coordinate/cross-product tolerance, NOT generic abs() usage
    fix_patterns = [
        r'abs\s*\(\s*d[1234]',        # abs(d1), abs(d2), etc. for cross-product tolerance
        r'COORDINATE_TOLERANCE',       # Using the config tolerance
        r'[Ee]psilon\b',              # Named epsilon variable
        r'[Tt]olerance\b',            # Named tolerance variable
        r'<\s*1e-',                    # Comparison with small epsilon
        r'<=\s*1e-',                   # Comparison with small epsilon
        r'math\.isclose',             # Python's isclose function
        r'numpy\.isclose|np\.isclose', # numpy isclose
    ]

    has_fix = any(re.search(p, src) for p in fix_patterns)

    if has_fix and not has_exact_zero:
        return True, "topology_validator.py uses epsilon-based floating-point comparison"

    if has_fix and has_exact_zero:
        # Partial fix: some comparisons fixed, some not.
        # Count occurrences of exact == 0 vs epsilon-aware abs(d*)
        exact_count = len(re.findall(r'd[1234]\s*==\s*0', src))
        eps_abs_count = len(re.findall(r'abs\s*\(\s*d[1234]', src))
        if eps_abs_count > 0:
            return True, "topology_validator.py uses epsilon comparison (some exact checks may remain)"
        return False, "topology_validator.py still uses exact == 0 for float comparison"

    if not has_exact_zero and not has_fix:
        # The == 0 pattern is gone but no explicit epsilon either
        # The function may have been rewritten
        if 'check_self_intersection' in src or '_segments_intersect' in src:
            return True, "topology_validator.py exact float comparison removed"

    return False, "topology_validator.py still uses exact floating-point comparison"


def check_feature_collection_wrapper(src):
    """
    Bug 5 -- Invalid GeoJSON structure in geojson_exporter.py (20 pts)

    The original code outputs a bare JSON array of features instead of
    wrapping in {"type": "FeatureCollection", "features": [...]}.
    """
    if not src:
        return False, "geojson_exporter.py is missing or empty"

    # The original bug: output = features  (bare list)
    # The fix should wrap in FeatureCollection
    has_fc_type = bool(re.search(r'["\']FeatureCollection["\']', src))
    has_fc_structure = bool(re.search(
        r'["\']type["\']\s*:\s*["\']FeatureCollection["\']', src
    ))
    has_features_key = bool(re.search(
        r'["\']features["\']\s*:', src
    ))

    if has_fc_type and has_features_key:
        return True, "geojson_exporter.py correctly wraps output in FeatureCollection"

    # Check if the bare-array bug is still present
    bare_array_bug = bool(re.search(
        r'output\s*=\s*features\s*(?:#|$|\n)', src
    ))

    if bare_array_bug and not has_fc_type:
        return False, "geojson_exporter.py still outputs bare feature array without FeatureCollection wrapper"

    if has_fc_type:
        return True, "geojson_exporter.py references FeatureCollection in export logic"

    # If output = features is gone and something else is assigned
    if not bare_array_bug and 'export_features' in src:
        return True, "geojson_exporter.py export_features was rewritten (bare array bug removed)"

    return False, "geojson_exporter.py FeatureCollection wrapper fix could not be verified"


# ──────────────────────────────────────────────────────────
# Anti-gaming: verify files were actually changed
# ──────────────────────────────────────────────────────────

def _files_were_modified(data, copy_from_env, temp_dir):
    """
    Compare current file contents against baseline hashes recorded
    during setup.  Returns True if at least one file was modified.
    """
    try:
        hashes_local = os.path.join(temp_dir, "initial_hashes.txt")
        copy_from_env("/tmp/geospatial_pipeline_initial_hashes.txt", hashes_local)
        if not os.path.exists(hashes_local):
            return True  # can't verify, assume modified

        with open(hashes_local, "r") as fh:
            original_hashes = {}
            for line in fh:
                parts = line.strip().split()
                if len(parts) >= 2:
                    h, path = parts[0], parts[-1]
                    for key in data:
                        if path.endswith(key) or path.endswith(key.replace("/", os.sep)):
                            original_hashes[key] = h

        for key, orig_hash in original_hashes.items():
            content = data.get(key, "")
            if content and _md5(content) != orig_hash:
                return True

        return False
    except Exception as e:
        logger.warning(f"Could not verify file modification: {e}")
        return True  # fail open


# ──────────────────────────────────────────────────────────
# Main verifier entry point
# ──────────────────────────────────────────────────────────

def verify_geospatial_pipeline(traj, env_info, task_info):
    """
    Verify that the agent fixed the 5 bugs in the geospatial ETL pipeline.

    Returns
    -------
    dict
        {"passed": bool, "score": int, "feedback": str}
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    temp_dir = tempfile.mkdtemp(prefix="verify_geospatial_")

    try:
        # ── Retrieve exported result JSON ───────────────
        result_local = os.path.join(temp_dir, "geospatial_pipeline_result.json")
        try:
            copy_from_env("/tmp/geospatial_pipeline_result.json", result_local)
        except Exception as e:
            logger.error(f"Could not copy result file: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not retrieve result file: {e}",
            }

        if not os.path.exists(result_local):
            return {
                "passed": False,
                "score": 0,
                "feedback": "Result file not found after export",
            }

        with open(result_local, "r", encoding="utf-8") as fh:
            data = json.load(fh)

        # ── Extract file contents ───────────────────────
        coord_src = _safe_get(data, "transforms/coordinate_transform.py")
        spatial_src = _safe_get(data, "transforms/spatial_operations.py")
        area_src = _safe_get(data, "transforms/area_calculator.py")
        topo_src = _safe_get(data, "transforms/topology_validator.py")
        export_src = _safe_get(data, "exporters/geojson_exporter.py")

        # ── Anti-gaming check ───────────────────────────
        if not _files_were_modified(data, copy_from_env, temp_dir):
            return {
                "passed": False,
                "score": 0,
                "feedback": "No files appear to have been modified from the original.",
            }

        # ── Run the five checks ─────────────────────────
        checks = [
            ("Lat/lng coordinate order fix", 20, check_coord_order_fix(coord_src)),
            ("Metric buffer conversion", 20, check_metric_buffer(spatial_src)),
            ("Projected area calculation", 20, check_projected_area(area_src)),
            ("Epsilon float comparison", 20, check_epsilon_comparison(topo_src)),
            ("FeatureCollection wrapper", 20, check_feature_collection_wrapper(export_src)),
        ]

        score = 0
        feedback_lines = []

        for label, points, (ok, msg) in checks:
            if ok:
                score += points
                feedback_lines.append(f"PASS [{points}pts] {label}: {msg}")
            else:
                feedback_lines.append(f"FAIL [ 0pts] {label}: {msg}")

        passed = score >= 60
        feedback_lines.insert(
            0,
            f"{'PASSED' if passed else 'FAILED'}: {score}/100 "
            f"(threshold 60, {sum(1 for _, _, (ok, _) in checks if ok)}/5 bugs fixed)",
        )

        logger.info(f"Score: {score}/100, passed={passed}")
        return {
            "passed": passed,
            "score": score,
            "feedback": "\n".join(feedback_lines),
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
        }

    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
