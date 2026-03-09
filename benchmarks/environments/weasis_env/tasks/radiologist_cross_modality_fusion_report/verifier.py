#!/usr/bin/env python3
"""
Verifier for radiologist_cross_modality_fusion_report task.

A radiologist must:
1. Open BOTH CT and MR datasets in Weasis simultaneously
2. Find corresponding anatomy across modalities
3. Apply 3 different W/L presets (CT soft tissue, CT bone, MR)
4. Measure same structure on both CT and MR
5. Calculate percentage difference between modality measurements
6. Export annotated views from both modalities
7. Write a comparative report discussing modality strengths

Scoring (100 points):
- 25 pts: At least 2 new PNGs (CT and MR), each >= 15KB
- 15 pts: Report exists, is new, >= 100 chars
- 25 pts: Report mentions both CT and MR/MRI with measurement context
- 20 pts: Report contains >= 3 distinct measurements
- 15 pts: Report contains comparative commentary (advantage/superior/etc.)

Pass threshold: 60 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/radiologist_crossmod_result.json"
PASS_THRESHOLD = 60


def verify_radiologist_cross_modality_fusion_report(traj, env_info, task_info):
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
    # Criterion 1 (25 pts): At least 2 new PNG exports (CT + MR)
    # ---------------------------------------------------------------
    ct_ok = result.get("ct_is_new", False) and result.get("ct_size_kb", 0) >= 15
    mr_ok = result.get("mr_is_new", False) and result.get("mr_size_kb", 0) >= 15
    total_new = result.get("total_new_png", 0)

    if ct_ok and mr_ok:
        score += 25
        feedback_parts.append("Both CT and MR PNGs exported (25/25)")
    elif (ct_ok or mr_ok) and total_new >= 2:
        score += 20
        feedback_parts.append(f"2+ PNGs exported, naming differs (20/25)")
    elif ct_ok or mr_ok:
        modality = "CT" if ct_ok else "MR"
        score += 12
        feedback_parts.append(f"Only {modality} PNG exported (12/25)")
    elif total_new >= 1:
        score += 8
        feedback_parts.append(f"Some new PNG found (8/25)")
    else:
        feedback_parts.append("No PNG exports found (0/25)")

    # ---------------------------------------------------------------
    # Criterion 2 (15 pts): Report exists, is new, adequate size
    # ---------------------------------------------------------------
    rpt_exists = result.get("report_exists", False)
    rpt_new = result.get("report_is_new", False)
    rpt_size = result.get("report_size_bytes", 0)

    if rpt_exists and rpt_new and rpt_size >= 100:
        score += 15
        feedback_parts.append(f"Report file OK ({rpt_size} bytes) (15/15)")
    elif rpt_exists and rpt_new and rpt_size >= 30:
        score += 8
        feedback_parts.append(f"Report short ({rpt_size} bytes) (8/15)")
    elif rpt_exists:
        feedback_parts.append("Report exists but NOT modified after task start (0/15)")
    else:
        feedback_parts.append("No comparative report found (0/15)")

    # ---------------------------------------------------------------
    # Criterion 3 (25 pts): Report mentions both CT and MR
    # ---------------------------------------------------------------
    has_ct = result.get("has_ct_mention", False)
    has_mr = result.get("has_mr_mention", False)

    if has_ct and has_mr:
        score += 25
        feedback_parts.append("Both CT and MR mentioned in report (25/25)")
    elif has_ct or has_mr:
        modality = "CT" if has_ct else "MR"
        score += 12
        feedback_parts.append(f"Only {modality} mentioned in report (12/25)")
    else:
        feedback_parts.append("Neither CT nor MR mentioned in report (0/25)")

    # ---------------------------------------------------------------
    # Criterion 4 (20 pts): >= 3 distinct measurements
    # ---------------------------------------------------------------
    meas_count = result.get("measurement_count", 0)

    if meas_count >= 4:
        score += 20
        feedback_parts.append(f"4+ measurements ({meas_count}) (20/20)")
    elif meas_count >= 3:
        score += 16
        feedback_parts.append(f"3 measurements (16/20)")
    elif meas_count >= 2:
        score += 10
        feedback_parts.append(f"Only {meas_count} measurements (10/20)")
    elif meas_count >= 1:
        score += 5
        feedback_parts.append(f"Only 1 measurement (5/20)")
    else:
        feedback_parts.append("No measurements found (0/20)")

    # ---------------------------------------------------------------
    # Criterion 5 (15 pts): Comparative commentary
    # ---------------------------------------------------------------
    has_comp = result.get("has_comparative", False)

    if has_comp:
        score += 15
        feedback_parts.append("Comparative commentary present (15/15)")
    else:
        feedback_parts.append("No comparative commentary found (0/15)")

    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
    }
