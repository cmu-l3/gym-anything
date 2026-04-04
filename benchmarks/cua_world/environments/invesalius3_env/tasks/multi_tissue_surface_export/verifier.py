#!/usr/bin/env python3
"""
Verifier for multi_tissue_surface_export task.

Scoring (100 points total):
  - Project file exists and is valid .inv3:         20 pts
  - At least 3 masks in project:                    25 pts
  - bone_tissue.stl exists and is valid STL:        20 pts
  - compact_bone.stl exists and is valid STL:       20 pts
  - soft_tissue.stl exists and is valid STL:        15 pts

Pass threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_multi_tissue_surface_export(traj, env_info, task_info):
    """Verify that 3 tissue masks were created and 3 STL surfaces exported."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    required_mask_count = metadata.get("required_mask_count", 3)

    score = 0
    feedback_parts = []

    # Copy result JSON from VM
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/multi_tissue_surface_export_result.json", tmp.name)
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
        feedback_parts.append("FAIL: Project file exists but invalid .inv3 format")
    else:
        feedback_parts.append(
            "FAIL: Project file not found at /home/ga/Documents/tissue_exports/tissue_analysis.inv3"
        )

    # Independent verification: copy the .inv3 and re-count masks
    ind_mask_count = result.get("mask_count", 0)
    try:
        import tarfile
        import plistlib
        tmp_inv3 = tempfile.NamedTemporaryFile(delete=False, suffix=".inv3")
        tmp_inv3.close()
        try:
            copy_from_env(
                "/home/ga/Documents/tissue_exports/tissue_analysis.inv3",
                tmp_inv3.name,
            )
            with tarfile.open(tmp_inv3.name, "r:gz") as t:
                for member in t.getmembers():
                    if os.path.basename(member.name) == "main.plist":
                        f = t.extractfile(member)
                        main = plistlib.load(f)
                        ind_mask_count = len(main.get("masks", {}))
                        break
        finally:
            try:
                os.unlink(tmp_inv3.name)
            except Exception:
                pass
    except Exception as e:
        logger.warning(f"Independent .inv3 analysis failed: {e}")

    # --- Criterion 2: At least 3 masks present (25 pts) ---
    if ind_mask_count >= required_mask_count:
        score += 25
        feedback_parts.append(f"{ind_mask_count} masks found in project (need >= {required_mask_count})")
    elif ind_mask_count > 0:
        feedback_parts.append(
            f"FAIL: Only {ind_mask_count} mask(s) in project (need >= {required_mask_count})"
        )
    else:
        feedback_parts.append(f"FAIL: No masks found in project")

    # --- Criterion 3: bone_tissue.stl (20 pts) ---
    bone_info = result.get("stl_bone_tissue", {})
    if bone_info.get("valid"):
        score += 20
        feedback_parts.append(
            f"bone_tissue.stl valid ({bone_info.get('triangle_count', 0):,} triangles)"
        )
    elif bone_info.get("exists"):
        score += 5
        feedback_parts.append("bone_tissue.stl exists but invalid STL format")
    else:
        feedback_parts.append("FAIL: bone_tissue.stl not found")

    # --- Criterion 4: compact_bone.stl (20 pts) ---
    compact_info = result.get("stl_compact_bone", {})
    if compact_info.get("valid"):
        score += 20
        feedback_parts.append(
            f"compact_bone.stl valid ({compact_info.get('triangle_count', 0):,} triangles)"
        )
    elif compact_info.get("exists"):
        score += 5
        feedback_parts.append("compact_bone.stl exists but invalid STL format")
    else:
        feedback_parts.append("FAIL: compact_bone.stl not found")

    # --- Criterion 5: soft_tissue.stl (15 pts) ---
    soft_info = result.get("stl_soft_tissue", {})
    if soft_info.get("valid"):
        score += 15
        feedback_parts.append(
            f"soft_tissue.stl valid ({soft_info.get('triangle_count', 0):,} triangles)"
        )
    elif soft_info.get("exists"):
        score += 5
        feedback_parts.append("soft_tissue.stl exists but invalid STL format")
    else:
        feedback_parts.append("FAIL: soft_tissue.stl not found")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "detail": {
            "mask_count": ind_mask_count,
            "bone_tissue_stl": bone_info,
            "compact_bone_stl": compact_info,
            "soft_tissue_stl": soft_info,
        },
    }
