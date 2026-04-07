"""
Verifier stub for tissue_density_characterization task.

Full verification is performed externally via vlm_checklist_verifier.
This stub provides basic file-existence and report-content checks.
"""

import json
import os
import re
import tempfile


def verify_tissue_density_characterization(traj, env_info, task_info):
    """
    Verify tissue density characterization task completion.

    Checks:
      - Export image exists and was created during the task
      - Report file exists with parseable content
      - Basic plausibility of parsed values against metadata ranges
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # ── Pull result JSON from environment ──
    result_file = "/tmp/tissue_char_result.json"
    tmp_dir = tempfile.mkdtemp()
    local_result = os.path.join(tmp_dir, "result.json")

    try:
        copy_from_env(result_file, local_result)
        with open(local_result, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result file: {e}"}
    finally:
        try:
            os.remove(local_result)
            os.rmdir(tmp_dir)
        except OSError:
            pass

    score = 0
    feedback_parts = []
    metadata = task_info.get("metadata", {}) if task_info else {}

    # ── Criterion 1: Export image exists and is fresh (15 pts) ──
    if result.get("img_exists") and result.get("img_new"):
        img_size = result.get("img_size", 0)
        if img_size >= 20000:
            score += 15
            feedback_parts.append("Image: OK ({}KB)".format(img_size // 1024))
        elif img_size > 0:
            score += 8
            feedback_parts.append("Image: small ({}B)".format(img_size))
        else:
            feedback_parts.append("Image: empty file")
    elif result.get("img_exists"):
        score += 5
        feedback_parts.append("Image: exists but may be stale")
    else:
        feedback_parts.append("Image: NOT found")

    # ── Criterion 2: Report file exists and is fresh (10 pts) ──
    if result.get("rpt_exists") and result.get("rpt_new"):
        rpt_size = result.get("rpt_size", 0)
        if rpt_size >= 50:
            score += 10
            feedback_parts.append("Report: OK ({}B)".format(rpt_size))
        elif rpt_size > 0:
            score += 5
            feedback_parts.append("Report: short ({}B)".format(rpt_size))
        else:
            feedback_parts.append("Report: empty file")
    elif result.get("rpt_exists"):
        score += 3
        feedback_parts.append("Report: exists but may be stale")
    else:
        feedback_parts.append("Report: NOT found")

    # ── Criterion 3: Parsed report values plausibility (35 pts) ──
    parsed = result.get("parsed", {})

    # Slice number (6 pts)
    slice_num = parsed.get("slice_num")
    sl_min = metadata.get("expected_peak_slice_min", 13)
    sl_max = metadata.get("expected_peak_slice_max", 19)
    if slice_num is not None and sl_min <= slice_num <= sl_max:
        score += 6
        feedback_parts.append("Slice: {} (in range)".format(slice_num))
    elif slice_num is not None:
        score += 2
        feedback_parts.append("Slice: {} (out of expected range {}-{})".format(slice_num, sl_min, sl_max))
    else:
        feedback_parts.append("Slice: not parsed from report")

    # Diameter (6 pts)
    diameter = parsed.get("diameter_mm")
    d_min = metadata.get("expected_diameter_min_mm", 55)
    d_max = metadata.get("expected_diameter_max_mm", 125)
    if diameter is not None and d_min <= diameter <= d_max:
        score += 6
        feedback_parts.append("Diameter: {:.1f}mm (in range)".format(diameter))
    elif diameter is not None:
        score += 2
        feedback_parts.append("Diameter: {:.1f}mm (out of range)".format(diameter))
    else:
        feedback_parts.append("Diameter: not parsed from report")

    # Soft-tissue mean HU (7 pts)
    st_mean = parsed.get("st_mean_hu")
    st_min = metadata.get("expected_st_mean_hu_min", 15)
    st_max = metadata.get("expected_st_mean_hu_max", 95)
    if st_mean is not None and st_min <= st_mean <= st_max:
        score += 7
        feedback_parts.append("ST Mean HU: {:.1f} (in range)".format(st_mean))
    elif st_mean is not None:
        score += 3
        feedback_parts.append("ST Mean HU: {:.1f} (out of range)".format(st_mean))
    else:
        feedback_parts.append("ST Mean HU: not parsed from report")

    # Soft-tissue std dev (4 pts)
    st_std = parsed.get("st_std")
    if st_std is not None and st_std > 0:
        score += 4
        feedback_parts.append("ST StdDev: {:.1f}".format(st_std))
    elif st_std is not None:
        score += 1
        feedback_parts.append("ST StdDev: {} (non-positive)".format(st_std))
    else:
        feedback_parts.append("ST StdDev: not parsed from report")

    # Bone mean HU (7 pts)
    bone_mean = parsed.get("bone_mean_hu")
    b_min = metadata.get("expected_bone_mean_hu_min", 150)
    b_max = metadata.get("expected_bone_mean_hu_max", 450)
    if bone_mean is not None and b_min <= bone_mean <= b_max:
        score += 7
        feedback_parts.append("Bone Mean HU: {:.1f} (in range)".format(bone_mean))
    elif bone_mean is not None:
        score += 3
        feedback_parts.append("Bone Mean HU: {:.1f} (out of range)".format(bone_mean))
    else:
        feedback_parts.append("Bone Mean HU: not parsed from report")

    # Classification (5 pts)
    classification = parsed.get("classification")
    expected_class = metadata.get("expected_classification", "soft tissue")
    if classification is not None and expected_class in classification:
        score += 5
        feedback_parts.append("Classification: '{}' (correct)".format(classification))
    elif classification is not None:
        score += 2
        feedback_parts.append("Classification: '{}' (expected '{}')".format(classification, expected_class))
    else:
        feedback_parts.append("Classification: not parsed from report")

    # ── Determine pass/fail ──
    passed = score >= 60
    feedback = " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
    }
