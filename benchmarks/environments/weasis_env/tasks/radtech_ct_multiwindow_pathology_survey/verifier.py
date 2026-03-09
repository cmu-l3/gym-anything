#!/usr/bin/env python3
"""
Verifier for radtech_ct_multiwindow_pathology_survey task.

A radiologic technologist must:
1. Open a CT scan in Weasis
2. Apply FOUR different window/level presets (lung, bone, soft tissue, mediastinal)
3. At each preset: navigate to relevant anatomy, measure a structure, annotate, export PNG
4. Write a multi-window survey report with all W/L values and measurements

Scoring (100 points):
- 30 pts: At least 3 new PNG exports in /home/ga/DICOM/exports/, each >= 20KB
- 20 pts: Report file exists, is new, >= 100 chars
- 25 pts: Report mentions at least 3 of the 4 window presets (by name or W/L value)
- 25 pts: Report contains at least 3 distinct numerical measurements (5-300mm range)

Pass threshold: 60 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/radtech_multiwindow_result.json"
PASS_THRESHOLD = 60


def verify_radtech_ct_multiwindow_pathology_survey(traj, env_info, task_info):
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
    # Criterion 1 (30 pts): At least 3 new PNG exports, each >= 20KB
    # ---------------------------------------------------------------
    png_count = result.get("png_count", 0)
    png_total_kb = result.get("png_total_kb", 0)
    any_new_images = result.get("any_new_images", 0)

    if png_count >= 4 and png_total_kb >= 80:
        score += 30
        feedback_parts.append(f"4+ PNG exports ({png_count} files, {png_total_kb}KB total) (30/30)")
    elif png_count >= 3 and png_total_kb >= 60:
        score += 25
        feedback_parts.append(f"3 PNG exports ({png_count} files, {png_total_kb}KB total) (25/30)")
    elif png_count >= 2:
        score += 15
        feedback_parts.append(f"Only {png_count} PNG exports (15/30)")
    elif png_count >= 1:
        score += 8
        feedback_parts.append(f"Only 1 PNG export (8/30)")
    elif any_new_images >= 1:
        score += 5
        feedback_parts.append(f"Some new images found but too small or wrong format (5/30)")
    else:
        feedback_parts.append("No PNG exports found (0/30)")

    # ---------------------------------------------------------------
    # Criterion 2 (20 pts): Report file exists, is new, adequate size
    # ---------------------------------------------------------------
    rpt_exists = result.get("report_exists", False)
    rpt_new = result.get("report_is_new", False)
    rpt_size = result.get("report_size_bytes", 0)

    if rpt_exists and rpt_new and rpt_size >= 100:
        score += 20
        feedback_parts.append(f"Report file OK ({rpt_size} bytes) (20/20)")
    elif rpt_exists and rpt_new and rpt_size >= 20:
        score += 12
        feedback_parts.append(f"Report exists+new but short ({rpt_size} bytes) (12/20)")
    elif rpt_exists and rpt_new:
        score += 5
        feedback_parts.append(f"Report exists+new but very short ({rpt_size} bytes) (5/20)")
    elif rpt_exists:
        feedback_parts.append("Report exists but was NOT modified after task start (0/20)")
    else:
        feedback_parts.append("No survey report file found (0/20)")

    # ---------------------------------------------------------------
    # Criterion 3 (25 pts): Report mentions at least 3 window presets
    # ---------------------------------------------------------------
    window_names = result.get("window_names_found", 0)

    if window_names >= 4:
        score += 25
        feedback_parts.append(f"All 4 window presets referenced in report (25/25)")
    elif window_names >= 3:
        score += 20
        feedback_parts.append(f"3 window presets referenced in report (20/25)")
    elif window_names >= 2:
        score += 12
        feedback_parts.append(f"Only {window_names} window presets referenced (12/25)")
    elif window_names >= 1:
        score += 5
        feedback_parts.append(f"Only 1 window preset referenced (5/25)")
    else:
        feedback_parts.append("No window preset names/values found in report (0/25)")

    # ---------------------------------------------------------------
    # Criterion 4 (25 pts): Report contains >= 3 distinct measurements
    # ---------------------------------------------------------------
    meas_count = result.get("measurement_count", 0)

    if meas_count >= 4:
        score += 25
        feedback_parts.append(f"4+ distinct measurements in report ({meas_count}) (25/25)")
    elif meas_count >= 3:
        score += 20
        feedback_parts.append(f"3 distinct measurements in report (20/25)")
    elif meas_count >= 2:
        score += 12
        feedback_parts.append(f"Only {meas_count} measurements found (12/25)")
    elif meas_count >= 1:
        score += 5
        feedback_parts.append(f"Only 1 measurement found (5/25)")
    else:
        feedback_parts.append("No measurements found in report (0/25)")

    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
    }
