#!/usr/bin/env python3
"""
Verifier for pneumocephalus_air_segmentation task.

A trauma radiologist segments intracranial air and brain soft tissue from a
cranial CT — a task that requires working with NEGATIVE Hounsfield Unit values,
inverting the typical bone/soft-tissue segmentation approach.

Scoring (100 points total):
  - Project file saved and valid .inv3 format:          20 pts
  - Air space mask present (max HU <= -200):            25 pts
  - Soft tissue mask present (near-zero HU range):      20 pts
  - STL file exported and valid:                        20 pts
  - >= 4 measurements placed:                           15 pts

Pass threshold: 65 points

GATE: If no primary output files exist (no project AND no STL), score = 0
immediately (do-nothing baseline protection).
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_pneumocephalus_air_segmentation(traj, env_info, task_info):
    """Verify pneumocephalus documentation: air mask + soft-tissue mask + STL + measurements."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    air_mask_max_hu_threshold  = metadata.get("air_mask_max_hu", -200)
    soft_tissue_min_hu         = metadata.get("soft_tissue_mask_min_hu", -200)
    soft_tissue_max_hu_min     = metadata.get("soft_tissue_mask_max_hu_min", 50)
    required_measurements      = metadata.get("required_measurement_count", 4)

    score = 0
    feedback_parts = []

    # ── Copy result JSON from VM ──────────────────────────────────────────────
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/pneumocephalus_air_segmentation_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read export result: {e}",
        }

    # ── OUTPUT-EXISTENCE GATE ─────────────────────────────────────────────────
    if not result.get("project_file_exists") and not result.get("stl_file_exists"):
        return {
            "passed": False,
            "score": 0,
            "feedback": "No output files found — project and STL both missing (do-nothing baseline)",
        }

    # ── Independent re-analysis of .inv3 ─────────────────────────────────────
    ind_masks_detail        = []
    ind_measurement_count   = result.get("measurement_count", 0)

    try:
        import tarfile, plistlib
        tmp_inv3 = tempfile.NamedTemporaryFile(delete=False, suffix=".inv3")
        tmp_inv3.close()
        copy_from_env(
            "/home/ga/Documents/air_analysis/pneumocephalus_study.inv3",
            tmp_inv3.name,
        )
        try:
            with tarfile.open(tmp_inv3.name, "r:gz") as t:
                mask_plists = {}
                for member in t.getmembers():
                    bname = os.path.basename(member.name)
                    if bname.startswith("mask_") and bname.endswith(".plist"):
                        f = t.extractfile(member)
                        mp = plistlib.load(f)
                        mask_plists[bname] = mp
                    elif bname == "measurements.plist":
                        f = t.extractfile(member)
                        meas_dict = plistlib.load(f)
                        ind_measurement_count = max(
                            ind_measurement_count, len(meas_dict)
                        )
                for name, mp in mask_plists.items():
                    tr     = mp.get("threshold_range", [0, 0])
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

    # If independent analysis found more masks, prefer it
    if ind_masks_detail:
        result["masks_detail"] = ind_masks_detail
    if ind_measurement_count > result.get("measurement_count", 0):
        result["measurement_count"] = ind_measurement_count

    # Recompute mask flags from final masks_detail
    air_mask_found         = False
    soft_tissue_mask_found = False
    for m in result.get("masks_detail", []):
        min_hu = m.get("min_hu", 0)
        max_hu = m.get("max_hu", 0)
        if max_hu <= air_mask_max_hu_threshold:
            air_mask_found = True
        if min_hu >= soft_tissue_min_hu and max_hu >= soft_tissue_max_hu_min:
            soft_tissue_mask_found = True

    # ── Criterion 1: Project file saved and valid (20 pts) ───────────────────
    try:
        if result.get("project_file_exists") and result.get("project_valid_inv3"):
            score += 20
            feedback_parts.append("Project file saved and valid")
        elif result.get("project_file_exists"):
            score += 8
            feedback_parts.append("Project file exists but could not be parsed as .inv3")
        else:
            feedback_parts.append("FAIL: Project file not found at /home/ga/Documents/air_analysis/pneumocephalus_study.inv3")
    except Exception as e:
        feedback_parts.append(f"Project check error: {e}")

    # ── Criterion 2: Air space mask (max HU <= -200) (25 pts) ────────────────
    try:
        if air_mask_found:
            score += 25
            feedback_parts.append(
                f"Air space mask found with correct negative HU range (max <= {air_mask_max_hu_threshold} HU)"
            )
        else:
            masks = result.get("masks_detail", [])
            if masks:
                hu_ranges = [(m["min_hu"], m["max_hu"]) for m in masks]
                feedback_parts.append(
                    f"FAIL: No air mask found (need max_hu <= {air_mask_max_hu_threshold}). "
                    f"Masks found: {hu_ranges}"
                )
            else:
                feedback_parts.append("FAIL: No segmentation masks found in project")
    except Exception as e:
        feedback_parts.append(f"Air mask check error: {e}")

    # ── Criterion 3: Soft tissue mask (near-zero HU) (20 pts) ────────────────
    try:
        if soft_tissue_mask_found:
            score += 20
            feedback_parts.append("Soft tissue / brain parenchyma mask found")
        else:
            feedback_parts.append(
                f"FAIL: No soft tissue mask found (need min_hu >= {soft_tissue_min_hu} "
                f"AND max_hu >= {soft_tissue_max_hu_min})"
            )
    except Exception as e:
        feedback_parts.append(f"Soft tissue mask check error: {e}")

    # ── Criterion 4: STL file exported and valid (20 pts) ────────────────────
    try:
        if result.get("stl_valid"):
            score += 20
            tri = result.get("stl_triangle_count", 0)
            feedback_parts.append(f"STL file valid ({tri:,} triangles)")
        elif result.get("stl_file_exists"):
            score += 8
            feedback_parts.append("STL file exists but could not be validated as STL format")
        else:
            feedback_parts.append("FAIL: STL file not found at /home/ga/Documents/air_analysis/air_spaces.stl")
    except Exception as e:
        feedback_parts.append(f"STL check error: {e}")

    # ── Criterion 5: At least 4 measurements (15 pts) ────────────────────────
    try:
        measurement_count = result.get("measurement_count", 0)
        if measurement_count >= required_measurements:
            score += 15
            feedback_parts.append(f"{measurement_count} measurements placed (need >= {required_measurements})")
        elif measurement_count > 0:
            feedback_parts.append(
                f"FAIL: Only {measurement_count} measurement(s) (need >= {required_measurements})"
            )
        else:
            feedback_parts.append("FAIL: No measurements found in project")
    except Exception as e:
        feedback_parts.append(f"Measurement check error: {e}")

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "detail": {
            "air_mask_found":         air_mask_found,
            "soft_tissue_mask_found": soft_tissue_mask_found,
            "masks_detail":           result.get("masks_detail", []),
            "measurement_count":      result.get("measurement_count", 0),
            "stl_triangle_count":     result.get("stl_triangle_count", 0),
        },
    }
