#!/usr/bin/env python3
"""
Verifier for radiation_tissue_atlas task.

A medical physicist creates a 3-tissue CT atlas for radiation treatment planning:
  - Brain soft tissue mask (near-zero HU: min >= -100, max <= 80)
  - Compact bone mask (high HU: min >= 600)
  - Periorbital fat mask (negative HU: max <= -20, min >= -300)
Three separate STL surface exports + >= 5 measurements + project save.

Scoring (100 points total):
  - Project file saved and valid:                    10 pts
  - Brain soft tissue mask (min >= -100, max <= 80): 20 pts
  - Compact bone mask (min >= 600):                  20 pts
  - Periorbital fat mask (max <= -20, min >= -300):  20 pts
  - All 3 STL files valid:                           15 pts
  - >= 5 measurements placed:                        15 pts

Pass threshold: 65 points

GATE: No output files → score = 0 immediately.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_radiation_tissue_atlas(traj, env_info, task_info):
    """Verify 3-tissue RT planning atlas: brain + bone + fat masks + 3 STLs + measurements."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    brain_mask_min_hu  = metadata.get("brain_mask_min_hu", -100)
    brain_mask_max_hu  = metadata.get("brain_mask_max_hu", 80)
    bone_mask_min_hu   = metadata.get("bone_mask_min_hu", 600)
    fat_mask_max_hu    = metadata.get("fat_mask_max_hu", -20)
    fat_mask_min_hu    = metadata.get("fat_mask_min_hu", -300)
    req_measurements   = metadata.get("required_measurement_count", 5)

    score = 0
    feedback_parts = []

    # ── Copy result JSON ──────────────────────────────────────────────────────
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/radiation_tissue_atlas_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read export result: {e}"}

    # ── OUTPUT-EXISTENCE GATE ─────────────────────────────────────────────────
    has_project = result.get("project_file_exists", False)
    has_any_stl = any(
        result.get(f"stl_{k}", {}).get("exists", False)
        for k in ("brain_tissue", "skull_bone", "periorbital_fat")
    )
    if not has_project and not has_any_stl:
        return {"passed": False, "score": 0, "feedback": "No output files found (do-nothing baseline)"}

    # ── Independent re-analysis of .inv3 ─────────────────────────────────────
    ind_masks_detail      = []
    ind_measurement_count = result.get("measurement_count", 0)

    try:
        import tarfile, plistlib
        tmp_inv3 = tempfile.NamedTemporaryFile(delete=False, suffix=".inv3")
        tmp_inv3.close()
        copy_from_env("/home/ga/Documents/rt_planning/rt_tissue_atlas.inv3", tmp_inv3.name)
        try:
            with tarfile.open(tmp_inv3.name, "r:gz") as t:
                mask_plists = {}
                for member in t.getmembers():
                    bname = os.path.basename(member.name)
                    if bname.startswith("mask_") and bname.endswith(".plist"):
                        f = t.extractfile(member)
                        mask_plists[bname] = plistlib.load(f)
                    elif bname == "measurements.plist":
                        f = t.extractfile(member)
                        md = plistlib.load(f)
                        if len(md) > ind_measurement_count:
                            ind_measurement_count = len(md)
                for name, mp in mask_plists.items():
                    tr = mp.get("threshold_range", [0, 0])
                    min_hu = float(tr[0]) if len(tr) >= 1 else 0.0
                    max_hu = float(tr[1]) if len(tr) >= 2 else 0.0
                    ind_masks_detail.append({"min_hu": min_hu, "max_hu": max_hu})
        finally:
            try:
                os.unlink(tmp_inv3.name)
            except Exception:
                pass
    except Exception as e:
        logger.warning(f"Independent .inv3 re-analysis failed: {e}")
        ind_masks_detail = result.get("masks_detail", [])

    if ind_masks_detail:
        result["masks_detail"] = ind_masks_detail
    if ind_measurement_count > result.get("measurement_count", 0):
        result["measurement_count"] = ind_measurement_count

    # Recompute mask flags from final masks_detail
    brain_mask_found = False
    bone_mask_found  = False
    fat_mask_found   = False
    for m in result.get("masks_detail", []):
        min_hu = m.get("min_hu", 0)
        max_hu = m.get("max_hu", 0)
        if min_hu >= brain_mask_min_hu and max_hu <= brain_mask_max_hu:
            brain_mask_found = True
        if min_hu >= bone_mask_min_hu:
            bone_mask_found = True
        if max_hu <= fat_mask_max_hu and min_hu >= fat_mask_min_hu:
            fat_mask_found = True

    # ── Criterion 1: Project file saved and valid (10 pts) ───────────────────
    try:
        if result.get("project_file_exists") and result.get("project_valid_inv3"):
            score += 10
            feedback_parts.append("Project file valid")
        elif result.get("project_file_exists"):
            score += 3
            feedback_parts.append("Project file exists but not parseable as .inv3")
        else:
            feedback_parts.append("FAIL: Project file not found")
    except Exception as e:
        feedback_parts.append(f"Project check error: {e}")

    # ── Criterion 2: Brain soft tissue mask (20 pts) ──────────────────────────
    try:
        if brain_mask_found:
            score += 20
            feedback_parts.append(
                f"Brain soft tissue mask found (near-zero HU range, min >= {brain_mask_min_hu}, max <= {brain_mask_max_hu})"
            )
        else:
            masks = result.get("masks_detail", [])
            feedback_parts.append(
                f"FAIL: No brain soft tissue mask found. "
                f"Need min_hu >= {brain_mask_min_hu} AND max_hu <= {brain_mask_max_hu}. "
                f"Masks: {[(m['min_hu'], m['max_hu']) for m in masks]}"
            )
    except Exception as e:
        feedback_parts.append(f"Brain mask check error: {e}")

    # ── Criterion 3: Compact bone mask (20 pts) ───────────────────────────────
    try:
        if bone_mask_found:
            score += 20
            feedback_parts.append(f"Compact bone mask found (min_hu >= {bone_mask_min_hu})")
        else:
            feedback_parts.append(f"FAIL: No compact bone mask found (need min_hu >= {bone_mask_min_hu})")
    except Exception as e:
        feedback_parts.append(f"Bone mask check error: {e}")

    # ── Criterion 4: Periorbital fat mask (20 pts) ────────────────────────────
    try:
        if fat_mask_found:
            score += 20
            feedback_parts.append(
                f"Periorbital fat mask found (negative HU range, max <= {fat_mask_max_hu})"
            )
        else:
            feedback_parts.append(
                f"FAIL: No periorbital fat mask found. "
                f"Need max_hu <= {fat_mask_max_hu} AND min_hu >= {fat_mask_min_hu}."
            )
    except Exception as e:
        feedback_parts.append(f"Fat mask check error: {e}")

    # ── Criterion 5: All 3 STL files valid (15 pts) ───────────────────────────
    try:
        stl_keys    = ("brain_tissue", "skull_bone", "periorbital_fat")
        valid_stls  = sum(1 for k in stl_keys if result.get(f"stl_{k}", {}).get("valid"))
        present_stls = sum(1 for k in stl_keys if result.get(f"stl_{k}", {}).get("exists"))
        if valid_stls == 3:
            score += 15
            feedback_parts.append("All 3 STL files valid")
        elif valid_stls > 0:
            pts = int(15 * valid_stls / 3)
            score += pts
            feedback_parts.append(
                f"Partial: {valid_stls}/3 STL files valid ({pts} pts)"
            )
        elif present_stls > 0:
            score += 3
            feedback_parts.append(f"{present_stls}/3 STL files present but invalid format")
        else:
            feedback_parts.append("FAIL: No STL files found")
    except Exception as e:
        feedback_parts.append(f"STL check error: {e}")

    # ── Criterion 6: >= 5 measurements (15 pts) ───────────────────────────────
    try:
        mcount = result.get("measurement_count", 0)
        if mcount >= req_measurements:
            score += 15
            feedback_parts.append(f"{mcount} measurements placed (need >= {req_measurements})")
        elif mcount > 0:
            pts = int(15 * mcount / req_measurements)
            score += pts
            feedback_parts.append(f"Partial: {mcount}/{req_measurements} measurements ({pts} pts)")
        else:
            feedback_parts.append("FAIL: No measurements found")
    except Exception as e:
        feedback_parts.append(f"Measurement check error: {e}")

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "detail": {
            "brain_mask_found": brain_mask_found,
            "bone_mask_found":  bone_mask_found,
            "fat_mask_found":   fat_mask_found,
            "masks_detail":     result.get("masks_detail", []),
            "measurement_count": result.get("measurement_count", 0),
            "stl_brain_valid":  result.get("stl_brain_tissue", {}).get("valid", False),
            "stl_bone_valid":   result.get("stl_skull_bone", {}).get("valid", False),
            "stl_fat_valid":    result.get("stl_periorbital_fat", {}).get("valid", False),
        },
    }
