#!/usr/bin/env python3
"""
Verifier for boolean_mask_operations task.

Scoring (100 points total):
  - Project file exists and is valid .inv3:                    20 pts
  - At least 2 bone masks (compact + full) present:            20 pts
  - At least 3 masks total (boolean result = third mask):      25 pts
  - STL file exists at correct path:                           20 pts
  - STL is valid format with >= 500 triangles:                 15 pts

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_boolean_mask_operations(traj, env_info, task_info):
    """Verify boolean subtraction: cancellous bone isolated and exported."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    required_mask_count = metadata.get("required_mask_count", 3)
    min_triangles = metadata.get("min_stl_triangles", 500)

    score = 0
    feedback_parts = []

    # Copy result JSON from VM
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/boolean_mask_operations_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read export result: {e}",
        }

    # --- Criterion 1: Project file exists and valid .inv3 (20 pts) ---
    if result.get("project_file_exists") and result.get("project_valid_inv3"):
        score += 20
        feedback_parts.append("Project file saved and valid")
    elif result.get("project_file_exists"):
        score += 5
        feedback_parts.append("FAIL: Project exists but invalid .inv3 format")
    else:
        feedback_parts.append(
            "FAIL: Project not found at /home/ga/Documents/cancellous_study/bone_analysis.inv3"
        )

    # Independent verification: copy the .inv3 and re-parse masks
    ind_mask_count = result.get("mask_count", 0)
    ind_masks = result.get("masks", [])
    try:
        import tarfile
        import plistlib
        tmp_inv3 = tempfile.NamedTemporaryFile(delete=False, suffix=".inv3")
        tmp_inv3.close()
        try:
            copy_from_env(
                "/home/ga/Documents/cancellous_study/bone_analysis.inv3",
                tmp_inv3.name,
            )
            ind_masks_fresh = []
            with tarfile.open(tmp_inv3.name, "r:gz") as t:
                for member in t.getmembers():
                    name = os.path.basename(member.name)
                    if name == "main.plist":
                        f = t.extractfile(member)
                        main = plistlib.load(f)
                        ind_mask_count = len(main.get("masks", {}))
                    elif name.startswith("mask_") and name.endswith(".plist"):
                        f = t.extractfile(member)
                        mask = plistlib.load(f)
                        thresh = mask.get("threshold_range", [0, 0])
                        ind_masks_fresh.append({
                            "name": mask.get("name", ""),
                            "threshold_min": thresh[0],
                            "threshold_max": thresh[1],
                        })
            if ind_masks_fresh:
                ind_masks = ind_masks_fresh
                # Re-derive boolean flags
                result["has_compact_bone_mask"] = any(
                    m["threshold_min"] >= 600 and m["threshold_max"] <= 2100
                    for m in ind_masks
                )
                result["has_full_bone_mask"] = any(
                    m["threshold_min"] >= 200 and m["threshold_max"] >= 2000
                    for m in ind_masks
                )
        finally:
            try:
                os.unlink(tmp_inv3.name)
            except Exception:
                pass
    except Exception as e:
        logger.warning(f"Independent .inv3 analysis failed: {e}")

    # --- Criterion 2: At least 2 bone masks present (20 pts) ---
    has_compact = result.get("has_compact_bone_mask", False)
    has_full    = result.get("has_full_bone_mask", False)
    if has_compact and has_full:
        score += 20
        feedback_parts.append("Both compact bone mask and full bone mask found")
    elif has_compact or has_full:
        score += 10
        which = "compact bone" if has_compact else "full bone"
        feedback_parts.append(f"PARTIAL: Only {which} mask found (need both)")
    else:
        feedback_parts.append("FAIL: No valid bone masks found in project")

    # --- Criterion 3: At least 3 masks total (boolean result mask) (25 pts) ---
    if ind_mask_count >= required_mask_count:
        score += 25
        feedback_parts.append(
            f"{ind_mask_count} masks in project (indicates boolean result mask created)"
        )
    elif ind_mask_count == 2:
        feedback_parts.append(
            "FAIL: Only 2 masks (expected 3: compact bone + full bone + boolean result)"
        )
    else:
        feedback_parts.append(f"FAIL: {ind_mask_count} mask(s) found (need >= {required_mask_count})")

    # --- Criterion 4: STL file exists (20 pts) ---
    if result.get("stl_file_exists"):
        score += 20
        feedback_parts.append("cancellous_bone.stl created")
    else:
        feedback_parts.append(
            "FAIL: cancellous_bone.stl not found at /home/ga/Documents/cancellous_study/"
        )

    # --- Criterion 5: STL valid with >= 500 triangles (15 pts) ---
    triangle_count = result.get("stl_triangle_count", 0)
    if result.get("stl_valid") and triangle_count >= min_triangles:
        score += 15
        feedback_parts.append(f"STL valid: {triangle_count:,} triangles")
    elif result.get("stl_file_exists"):
        feedback_parts.append(
            f"FAIL: STL invalid or too few triangles ({triangle_count:,}, need >= {min_triangles})"
        )

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "detail": {
            "mask_count": ind_mask_count,
            "masks": ind_masks,
            "stl_triangle_count": result.get("stl_triangle_count", 0),
        },
    }
