#!/usr/bin/env python3
"""
Verifier for ct_cardiac_measurements task.

A hospitalist must:
1. Open chest CT in Weasis and apply cardiac window/level settings
2. Navigate to the widest cardiac level and place two line measurements
3. Export annotated image to /home/ga/DICOM/exports/cardiac_analysis.png
4. Write a report with cardiac width, thoracic width, and CTR to
   /home/ga/DICOM/exports/cardiac_report.txt

Scoring (100 points):
- 25 pts: Export image exists, is newer than task start, size >= 30KB
- 30 pts: Report file exists, is newer than task start, has content (>20 chars)
- 30 pts: Report contains a plausible CTR value (decimal 0.25-0.80)
- 15 pts: Report contains at least two distinct numerical measurements
          (cardiac width and thoracic width, both 50-250mm range)

Pass threshold: 60 points
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/ct_cardiac_measurements_result.json"
PASS_THRESHOLD = 60


def verify_ct_cardiac_measurements(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Copy result JSON from VM
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
    # Criterion 1 (25 pts): Exported PNG image exists, is new, adequate size
    # ---------------------------------------------------------------
    img_exists = result.get("image_exists", False)
    img_new = result.get("image_is_new", False)
    img_size_kb = result.get("image_size_kb", 0)
    any_new_png = result.get("any_new_png_exports", "")

    if img_exists and img_new and img_size_kb >= 30:
        score += 25
        feedback_parts.append(f"Export image OK ({img_size_kb}KB) (25/25)")
    elif any_new_png and img_size_kb >= 30:
        # Agent saved to a different filename — still gets credit
        score += 20
        feedback_parts.append(f"Alternative export found ({img_size_kb}KB) (20/25)")
    elif img_exists and img_new:
        score += 15
        feedback_parts.append(f"Export image exists+new but small ({img_size_kb}KB) (15/25)")
    elif img_exists:
        feedback_parts.append(f"Export image exists but was NOT modified after task start (0/25)")
    elif any_new_png:
        score += 10
        feedback_parts.append(f"Some new PNG exported to exports folder (10/25)")
    else:
        feedback_parts.append("No export image found (0/25)")

    # ---------------------------------------------------------------
    # Criterion 2 (30 pts): Report file exists, is new, has meaningful content
    # ---------------------------------------------------------------
    rpt_exists = result.get("report_exists", False)
    rpt_new = result.get("report_is_new", False)
    rpt_size = result.get("report_size_bytes", 0)

    if rpt_exists and rpt_new and rpt_size >= 20:
        score += 30
        feedback_parts.append(f"Report file OK ({rpt_size} bytes) (30/30)")
    elif rpt_exists and rpt_new:
        score += 15
        feedback_parts.append(f"Report exists+new but very short ({rpt_size} bytes) (15/30)")
    elif rpt_exists:
        feedback_parts.append("Report exists but was NOT modified after task start (0/30)")
    else:
        feedback_parts.append("No cardiac report file found (0/30)")

    # ---------------------------------------------------------------
    # Criterion 3 (30 pts): Report contains a plausible CTR value (0.25-0.80)
    # ---------------------------------------------------------------
    ctr_str = result.get("ctr_value_found", "")
    if ctr_str:
        try:
            ctr = float(ctr_str)
            if 0.25 <= ctr <= 0.80:
                score += 30
                feedback_parts.append(f"Valid CTR found: {ctr:.2f} (30/30)")
            elif 0.10 <= ctr <= 0.95:
                score += 15
                feedback_parts.append(f"CTR found ({ctr:.2f}) but outside typical range (15/30)")
            else:
                feedback_parts.append(f"CTR value {ctr} outside any realistic range (0/30)")
        except ValueError:
            feedback_parts.append("CTR value not parseable (0/30)")
    else:
        feedback_parts.append("No CTR decimal value found in report (0/30)")

    # ---------------------------------------------------------------
    # Criterion 4 (15 pts): Report has at least two distinct mm measurements
    # ---------------------------------------------------------------
    if rpt_exists and rpt_new:
        # Copy report text from VM for analysis
        try:
            tmp_rpt = tempfile.NamedTemporaryFile(delete=False, suffix=".txt")
            tmp_rpt.close()
            copy_from_env("/home/ga/DICOM/exports/cardiac_report.txt", tmp_rpt.name)
            with open(tmp_rpt.name, "r", errors="replace") as f:
                rpt_text = f.read()
            os.unlink(tmp_rpt.name)

            # Find all numbers that could be mm measurements (40-300mm range)
            nums = re.findall(r"\b([4-9][0-9]|[1-2][0-9]{2}|300)\b", rpt_text)
            distinct_nums = set(nums)
            if len(distinct_nums) >= 2:
                score += 15
                feedback_parts.append(
                    f"Found {len(distinct_nums)} distinct measurements in report (15/15)"
                )
            elif len(distinct_nums) == 1:
                score += 7
                feedback_parts.append("Only 1 measurement found in report (7/15)")
            else:
                feedback_parts.append("No mm measurements found in report (0/15)")
        except Exception:
            # Report text not available or agent wrote to different path
            cardiac_w = result.get("cardiac_width_mm", "")
            if cardiac_w:
                score += 10
                feedback_parts.append(f"Cardiac width detected: {cardiac_w}mm (10/15)")
            else:
                feedback_parts.append("Could not verify measurements in report (0/15)")

    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
    }
