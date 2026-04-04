#!/usr/bin/env python3
"""
Verifier for neurologist_mri_ventricle_morphometry task.

A neurologist must:
1. Open brain MRI in Weasis and apply brain window/level
2. Navigate to frontal horn level, measure frontal horn width and biparietal diameter
3. Calculate Evans index (frontal horn width / biparietal diameter)
4. Navigate to third ventricle and temporal horn levels for additional measurements
5. Make clinical determination about ventriculomegaly
6. Export annotated image and structured NPH assessment report

Scoring (100 points):
- 20 pts: Export image exists, is new, size >= 20KB
- 15 pts: Report file exists, is new, >= 50 chars
- 30 pts: Report contains plausible Evans index (0.15-0.60) and mentions "Evans"
- 20 pts: Report contains >= 3 distinct mm measurements (1-200mm range)
- 15 pts: Report contains clinical determination keyword

Pass threshold: 60 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/neurologist_ventricle_result.json"
PASS_THRESHOLD = 60


def verify_neurologist_mri_ventricle_morphometry(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env(RESULT_PATH, tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export script may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    feedback_parts = []

    # ---------------------------------------------------------------
    # Criterion 1 (20 pts): Export image exists, is new, adequate size
    # ---------------------------------------------------------------
    img_exists = result.get("image_exists", False)
    img_new = result.get("image_is_new", False)
    img_size_kb = result.get("image_size_kb", 0)
    any_new_png = result.get("any_new_png", 0)

    if img_exists and img_new and img_size_kb >= 20:
        score += 20
        feedback_parts.append(f"Export image OK ({img_size_kb}KB) (20/20)")
    elif any_new_png >= 1 and img_size_kb >= 20:
        score += 15
        feedback_parts.append(f"Alternative PNG export found (15/20)")
    elif img_exists and img_new:
        score += 10
        feedback_parts.append(f"Export image exists+new but small ({img_size_kb}KB) (10/20)")
    elif any_new_png >= 1:
        score += 8
        feedback_parts.append(f"Some new PNG found (8/20)")
    else:
        feedback_parts.append("No export image found (0/20)")

    # ---------------------------------------------------------------
    # Criterion 2 (15 pts): Report exists, is new, adequate size
    # ---------------------------------------------------------------
    rpt_exists = result.get("report_exists", False)
    rpt_new = result.get("report_is_new", False)
    rpt_size = result.get("report_size_bytes", 0)

    if rpt_exists and rpt_new and rpt_size >= 50:
        score += 15
        feedback_parts.append(f"Report file OK ({rpt_size} bytes) (15/15)")
    elif rpt_exists and rpt_new:
        score += 8
        feedback_parts.append(f"Report exists+new but short ({rpt_size} bytes) (8/15)")
    elif rpt_exists:
        feedback_parts.append("Report exists but NOT modified after task start (0/15)")
    else:
        feedback_parts.append("No NPH assessment report found (0/15)")

    # ---------------------------------------------------------------
    # Criterion 3 (30 pts): Evans index value found and plausible
    # ---------------------------------------------------------------
    evans_str = result.get("evans_index", "")
    if evans_str:
        try:
            evans = float(evans_str)
            if 0.15 <= evans <= 0.60:
                score += 30
                feedback_parts.append(f"Valid Evans index: {evans:.2f} (30/30)")
            elif 0.10 <= evans <= 0.80:
                score += 15
                feedback_parts.append(
                    f"Evans index {evans:.2f} outside typical range but parseable (15/30)"
                )
            else:
                feedback_parts.append(f"Evans index {evans} unrealistic (0/30)")
        except ValueError:
            feedback_parts.append("Evans index not parseable (0/30)")
    else:
        feedback_parts.append("No Evans index found in report (0/30)")

    # ---------------------------------------------------------------
    # Criterion 4 (20 pts): Report contains >= 3 distinct measurements
    # ---------------------------------------------------------------
    meas_count = result.get("measurement_count", 0)

    if meas_count >= 4:
        score += 20
        feedback_parts.append(f"4+ measurements in report ({meas_count}) (20/20)")
    elif meas_count >= 3:
        score += 16
        feedback_parts.append(f"3 measurements in report (16/20)")
    elif meas_count >= 2:
        score += 10
        feedback_parts.append(f"Only {meas_count} measurements (10/20)")
    elif meas_count >= 1:
        score += 5
        feedback_parts.append(f"Only 1 measurement (5/20)")
    else:
        feedback_parts.append("No measurements found in report (0/20)")

    # ---------------------------------------------------------------
    # Criterion 5 (15 pts): Clinical determination present
    # ---------------------------------------------------------------
    has_determination = result.get("has_clinical_determination", False)

    if has_determination:
        score += 15
        feedback_parts.append("Clinical determination present (15/15)")
    else:
        feedback_parts.append("No clinical determination found (0/15)")

    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
    }
