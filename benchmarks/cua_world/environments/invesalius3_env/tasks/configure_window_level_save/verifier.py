#!/usr/bin/env python3
"""Verifier for configure_window_level_save task.

Scoring (100 points):
- Project file exists: 20 points
- Valid .inv3 format: 15 points
- Window width changed to brain window (<=250 HU): 30 points
- Soft tissue mask created (max HU <= 300): 35 points

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

INV3_PATH = "/home/ga/Documents/brain_study.inv3"


def verify_configure_window_level_save(traj, env_info, task_info):
    """
    Verify that the agent:
    1. Adjusted window width to brain soft tissue range (<=250 HU)
    2. Created a soft tissue segmentation mask
    3. Saved the project as brain_study.inv3
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback_parts = []

    # Copy result JSON from VM
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_result.close()
        try:
            copy_from_env(
                "/tmp/configure_window_level_save_result.json",
                temp_result.name
            )
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(temp_result.name)
            except Exception:
                pass
    except Exception as e:
        logger.warning(f"Could not read export JSON: {e}")
        result = {}

    # Criterion 1: Project file exists (20 points)
    try:
        if result.get("file_exists"):
            score += 20
            feedback_parts.append("Project file exists")
        else:
            feedback_parts.append("FAIL: Project file brain_study.inv3 not found")
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }
    except Exception as e:
        logger.warning(f"file_exists check failed: {e}")
        feedback_parts.append("FAIL: Could not check project file")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Valid .inv3 format (15 points)
    try:
        if result.get("valid_inv3"):
            score += 15
            feedback_parts.append("Valid .inv3 format")
        else:
            feedback_parts.append("FAIL: File is not a valid .inv3 archive")
    except Exception as e:
        logger.warning(f"valid_inv3 check failed: {e}")
        feedback_parts.append("Could not validate .inv3 format")

    # Independent verification: copy .inv3 and re-parse it
    try:
        import tarfile
        import plistlib
        temp_inv3 = tempfile.NamedTemporaryFile(delete=False, suffix='.inv3')
        temp_inv3.close()
        try:
            copy_from_env(INV3_PATH, temp_inv3.name)
            with tarfile.open(temp_inv3.name, "r:gz") as t:
                independent_window_width = None
                independent_masks = []

                for member in t.getmembers():
                    name = os.path.basename(member.name)
                    if name == "main.plist":
                        f = t.extractfile(member)
                        main = plistlib.load(f)
                        independent_window_width = float(main.get("window_width", 406.0))
                    elif name.startswith("mask_") and name.endswith(".plist"):
                        f = t.extractfile(member)
                        mask = plistlib.load(f)
                        thresh = mask.get("threshold_range", [0, 0])
                        independent_masks.append({
                            "name": mask.get("name", ""),
                            "threshold_min": thresh[0],
                            "threshold_max": thresh[1],
                        })

                # Criterion 3: Window width changed to brain window (30 points)
                if independent_window_width is not None and independent_window_width <= 250.0:
                    score += 30
                    feedback_parts.append(
                        f"Brain window set (width={independent_window_width:.1f} HU)"
                    )
                else:
                    w = independent_window_width if independent_window_width is not None else "unknown"
                    feedback_parts.append(
                        f"FAIL: Window width not changed to brain range (got {w} HU, need <=250)"
                    )

                # Criterion 4: Soft tissue mask present with max HU <= 300 (35 points)
                has_soft_tissue = any(
                    m["threshold_max"] <= 300 for m in independent_masks
                )
                if has_soft_tissue:
                    score += 35
                    feedback_parts.append("Soft tissue mask created")
                else:
                    feedback_parts.append(
                        f"FAIL: No soft tissue mask found (need mask with max HU <= 300); "
                        f"found {len(independent_masks)} mask(s)"
                    )
        finally:
            try:
                os.unlink(temp_inv3.name)
            except Exception:
                pass

    except Exception as e:
        logger.warning(f"Independent .inv3 analysis failed: {e}")
        # Fall back to export JSON values
        try:
            if result.get("window_width_changed"):
                score += 30
                feedback_parts.append(
                    f"Brain window set (width={result.get('window_width', '?'):.1f} HU)"
                )
            else:
                feedback_parts.append(
                    f"FAIL: Window width not in brain range "
                    f"(got {result.get('window_width', '?')} HU, need <=250)"
                )

            if result.get("has_soft_tissue_mask"):
                score += 35
                feedback_parts.append("Soft tissue mask created")
            else:
                feedback_parts.append("FAIL: No soft tissue mask found")
        except Exception as e2:
            logger.warning(f"Fallback check also failed: {e2}")
            feedback_parts.append("Could not verify window/mask criteria")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) if feedback_parts else "No criteria checked"
    }
