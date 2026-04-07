"""
Verifier for multicriteria_suitability_mapping task.

Stub verifier — real evaluation is done via vlm_checklist_verifier.
Basic programmatic checks are included for CI/smoke-test purposes.
"""

import json
import os
import tempfile


def verify_multicriteria_suitability_mapping(traj, env_info, task_info):
    """Verify the multicriteria suitability mapping task."""
    copy_from_env = env_info.get("copy_from_env")
    result_path = tempfile.mktemp(suffix=".json")

    try:
        copy_from_env("/tmp/suitability_task_result.json", result_path)
        with open(result_path) as f:
            result = json.load(f)
    except Exception:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Could not retrieve result JSON from environment.",
        }
    finally:
        if os.path.exists(result_path):
            os.unlink(result_path)

    score = 0
    feedback = []

    # 1. DIMAP product saved (15 pts)
    if result.get("dimap_found"):
        if result.get("dimap_timestamp_ok"):
            score += 15
            feedback.append("DIMAP product found with valid timestamp (+15)")
        else:
            score += 8
            feedback.append("DIMAP product found but timestamp not verified (+8)")
    else:
        feedback.append("No DIMAP product found (+0)")

    # 2. Collocation evidence (20 pts)
    has_m = result.get("has_master_suffix_bands", False)
    has_s = result.get("has_slave_suffix_bands", False)
    collocate_hist = result.get("collocation_in_history", False)
    if has_m and has_s and collocate_hist:
        score += 20
        feedback.append("Full collocation evidence: _M/_S bands + history (+20)")
    elif has_m and has_s:
        score += 15
        feedback.append("Collocation band suffixes found, no history entry (+15)")
    elif collocate_hist:
        score += 10
        feedback.append("Collocation in history but no _M/_S bands (+10)")
    elif result.get("band_count", 0) >= 5:
        score += 5
        feedback.append("Multiple bands suggest possible collocation (+5)")
    else:
        feedback.append("No collocation evidence (+0)")

    # 3. NDVI band (20 pts)
    if result.get("has_ndvi_band"):
        if result.get("ndvi_references_nir_red"):
            score += 20
            feedback.append("NDVI band with correct NIR/Red formula (+20)")
        else:
            score += 10
            feedback.append("NDVI band found but formula not fully verified (+10)")
    else:
        feedback.append("No NDVI band found (+0)")

    # 4. Suitability classification band (25 pts)
    if result.get("has_suitability_band"):
        has_cond = result.get("suitability_has_conditional", False)
        refs_ndvi = result.get("suitability_references_ndvi", False)
        refs_elev = result.get("suitability_references_elevation", False)
        has_classes = result.get("suitability_has_classes_123", False)
        if has_cond and refs_ndvi and refs_elev and has_classes:
            score += 25
            feedback.append(
                "Suitability band with conditional, NDVI+elevation refs, classes 1-3 (+25)"
            )
        elif has_cond and (refs_ndvi or refs_elev):
            score += 15
            feedback.append(
                "Suitability band with conditional, partial refs (+15)"
            )
        elif has_cond:
            score += 10
            feedback.append("Suitability band with conditional logic (+10)")
        else:
            score += 5
            feedback.append("Suitability band found but missing conditional logic (+5)")
    else:
        feedback.append("No suitability classification band found (+0)")

    # 5. GeoTIFF subset export (20 pts)
    if result.get("geotiff_found"):
        is_subset = result.get("subset_dimensions_approx_200x200", False)
        ts_ok = result.get("geotiff_timestamp_ok", False)
        size_ok = result.get("geotiff_size_bytes", 0) > 100
        if is_subset and ts_ok and size_ok:
            score += 20
            feedback.append("GeoTIFF subset ~200x200 with valid timestamp (+20)")
        elif size_ok and ts_ok:
            score += 12
            feedback.append("GeoTIFF found with valid timestamp, dimensions not 200x200 (+12)")
        elif size_ok:
            score += 8
            feedback.append("GeoTIFF found but timestamp not verified (+8)")
        else:
            score += 3
            feedback.append("GeoTIFF found but very small or no timestamp (+3)")
    else:
        feedback.append("No GeoTIFF export found (+0)")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback),
        "details": result,
    }
