#!/usr/bin/env python3
"""
Verifier for mpr_kidney_measurement task.

A urologist must:
1. Load CT urogram and activate MPR (multi-planar reconstruction) view
2. Apply soft tissue / renal window settings
3. Measure kidney craniocaudal length in the coronal view
4. Export coronal MPR view to /home/ga/DICOM/exports/mpr_renal.png
5. Write a report with kidney length and normal/abnormal assessment to
   /home/ga/DICOM/exports/renal_report.txt

Scoring (100 points):
- 25 pts: Export image exists, is newer than task start, size >= 30KB
- 30 pts: Report file exists, is newer than task start, has content (>20 chars)
- 30 pts: Report contains a plausible kidney length measurement (50-160 mm)
- 15 pts: Report contains a normal/abnormal assessment keyword

Pass threshold: 60 points
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/mpr_kidney_measurement_result.json"
PASS_THRESHOLD = 60


def verify_mpr_kidney_measurement(traj, env_info, task_info):
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
    # Criterion 1 (25 pts): MPR export image — exists, new, ≥30KB
    # A larger image suggests actual MPR rendering (not a tiny thumbnail)
    # ---------------------------------------------------------------
    img_exists = result.get("image_exists", False)
    img_new = result.get("image_is_new", False)
    img_size_kb = result.get("image_size_kb", 0)
    any_new_png = result.get("any_new_png_exports", "")

    if img_exists and img_new and img_size_kb >= 30:
        score += 25
        feedback_parts.append(f"MPR export image OK ({img_size_kb}KB) (25/25)")
    elif any_new_png and img_size_kb >= 30:
        score += 20
        feedback_parts.append(f"Alternative export found ({img_size_kb}KB) (20/25)")
    elif img_exists and img_new:
        score += 15
        feedback_parts.append(f"Export image exists+new but small ({img_size_kb}KB) (15/25)")
    elif img_exists:
        feedback_parts.append("Export image exists but NOT modified after task start (0/25)")
    elif any_new_png:
        score += 10
        feedback_parts.append("Some new PNG exported to exports folder (10/25)")
    else:
        feedback_parts.append("No MPR export image found (0/25)")

    # ---------------------------------------------------------------
    # Criterion 2 (30 pts): Report exists, new, meaningful content
    # ---------------------------------------------------------------
    rpt_exists = result.get("report_exists", False)
    rpt_new = result.get("report_is_new", False)
    rpt_size = result.get("report_size_bytes", 0)

    if rpt_exists and rpt_new and rpt_size >= 20:
        score += 30
        feedback_parts.append(f"Renal report OK ({rpt_size} bytes) (30/30)")
    elif rpt_exists and rpt_new:
        score += 15
        feedback_parts.append(f"Report exists+new but very short ({rpt_size} bytes) (15/30)")
    elif rpt_exists:
        feedback_parts.append("Report exists but NOT modified after task start (0/30)")
    else:
        feedback_parts.append("No renal report file found (0/30)")

    # ---------------------------------------------------------------
    # Criterion 3 (30 pts): Report contains plausible kidney length (50–160 mm)
    # Range-based check — agent may correctly report any realistic kidney length
    # ---------------------------------------------------------------
    kidney_len = result.get("kidney_length_mm", "")
    if kidney_len:
        try:
            kl = float(kidney_len)
            if 50.0 <= kl <= 160.0:
                score += 30
                feedback_parts.append(f"Valid kidney length: {kl:.1f}mm (30/30)")
            elif 30.0 <= kl <= 180.0:
                score += 15
                feedback_parts.append(f"Kidney length {kl:.1f}mm outside typical range (15/30)")
            else:
                feedback_parts.append(f"Kidney length {kl} implausible (0/30)")
        except ValueError:
            feedback_parts.append("Kidney length not parseable (0/30)")
    else:
        # Try to find a length from the report directly
        if rpt_exists and rpt_new:
            try:
                tmp_rpt = tempfile.NamedTemporaryFile(delete=False, suffix=".txt")
                tmp_rpt.close()
                copy_from_env("/home/ga/DICOM/exports/renal_report.txt", tmp_rpt.name)
                with open(tmp_rpt.name, "r", errors="replace") as f:
                    rpt_text = f.read()
                os.unlink(tmp_rpt.name)
                nums = re.findall(r"\b([5-9][0-9]|1[0-5][0-9]|160)(?:\.[0-9]+)?\b", rpt_text)
                if nums:
                    score += 25
                    feedback_parts.append(f"Measurement found in report: {nums[0]}mm (25/30)")
                else:
                    feedback_parts.append("No kidney length found in report (0/30)")
            except Exception:
                feedback_parts.append("No kidney length found in report (0/30)")
        else:
            feedback_parts.append("No kidney length in report (0/30)")

    # ---------------------------------------------------------------
    # Criterion 4 (15 pts): Report contains a clinical assessment
    # (normal / abnormal / within normal limits / enlarged)
    # ---------------------------------------------------------------
    normal_found = result.get("normal_assessment_found", False)
    if normal_found:
        score += 15
        feedback_parts.append("Clinical assessment present in report (15/15)")
    else:
        # Try a direct check on the report text
        if rpt_exists and rpt_new:
            try:
                tmp_rpt2 = tempfile.NamedTemporaryFile(delete=False, suffix=".txt")
                tmp_rpt2.close()
                copy_from_env("/home/ga/DICOM/exports/renal_report.txt", tmp_rpt2.name)
                with open(tmp_rpt2.name, "r", errors="replace") as f:
                    rpt_text2 = f.read()
                os.unlink(tmp_rpt2.name)
                if re.search(r"\b(normal|abnormal|enlarg|within\s+normal|WNL|limits)\b",
                             rpt_text2, re.IGNORECASE):
                    score += 15
                    feedback_parts.append("Clinical assessment found in report (15/15)")
                else:
                    feedback_parts.append("No normal/abnormal assessment in report (0/15)")
            except Exception:
                feedback_parts.append("Could not verify clinical assessment (0/15)")
        else:
            feedback_parts.append("No clinical assessment in report (0/15)")

    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
    }
