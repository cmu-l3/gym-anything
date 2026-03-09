#!/usr/bin/env python3
"""
Verifier for oncology_lesion_measurement task.

A Radiologist must perform RECIST 1.1 tumor response assessment:
1. Load CT scan in Weasis
2. Apply soft tissue window (W:400 L:50)
3. Measure TWO target lesions (longest diameter each)
4. Export a screenshot for each lesion: recist_lesion1.png, recist_lesion2.png
5. Write a RECIST report to recist_report.txt with:
   - Lesion 1: location and longest diameter (mm)
   - Lesion 2: location and longest diameter (mm)
   - Sum of Longest Diameters (SLD)
   - Baseline assessment statement

Scoring (100 points):
- 30 pts: Two lesion images exported (15 per image: exists, new, ≥20KB)
- 15 pts: At least 2 new PNGs in exports folder (fallback for naming issues)
- 30 pts: RECIST report exists, is new, has meaningful content (>40 chars)
- 25 pts: Report contains SLD keyword + 2 distinct measurements + baseline statement

Pass threshold: 60 points
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/oncology_lesion_measurement_result.json"
PASS_THRESHOLD = 60


def verify_oncology_lesion_measurement(traj, env_info, task_info):
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
    # Criterion 1 (30 pts): Two lesion screenshot images exported
    # 15 pts per image: recist_lesion1.png and recist_lesion2.png
    # ---------------------------------------------------------------
    l1_exists = result.get("lesion1_image_exists", False)
    l1_new = result.get("lesion1_image_is_new", False)
    l1_size = result.get("lesion1_image_size_kb", 0)

    l2_exists = result.get("lesion2_image_exists", False)
    l2_new = result.get("lesion2_image_is_new", False)
    l2_size = result.get("lesion2_image_size_kb", 0)

    img_score = 0
    img_details = []

    if l1_exists and l1_new and l1_size >= 20:
        img_score += 15
        img_details.append(f"lesion1 OK ({l1_size}KB)")
    elif l1_exists and l1_new:
        img_score += 8
        img_details.append(f"lesion1 small ({l1_size}KB)")
    else:
        img_details.append("lesion1 missing")

    if l2_exists and l2_new and l2_size >= 20:
        img_score += 15
        img_details.append(f"lesion2 OK ({l2_size}KB)")
    elif l2_exists and l2_new:
        img_score += 8
        img_details.append(f"lesion2 small ({l2_size}KB)")
    else:
        img_details.append("lesion2 missing")

    score += img_score
    feedback_parts.append(f"Lesion images: {', '.join(img_details)} ({img_score}/30)")

    # ---------------------------------------------------------------
    # Criterion 2 (15 pts): Fallback — any 2 new PNGs in exports
    # ---------------------------------------------------------------
    new_png_count = result.get("new_png_count", 0)
    if new_png_count >= 2:
        score += 15
        feedback_parts.append(f"{new_png_count} new PNGs in exports directory (15/15)")
    elif new_png_count == 1:
        score += 8
        feedback_parts.append(f"Only 1 new PNG in exports (expected 2) (8/15)")
    else:
        feedback_parts.append("No new PNG exports found (0/15)")

    # ---------------------------------------------------------------
    # Criterion 3 (30 pts): RECIST report exists, new, has content
    # ---------------------------------------------------------------
    rpt_exists = result.get("report_exists", False)
    rpt_new = result.get("report_is_new", False)
    rpt_size = result.get("report_size_bytes", 0)

    if rpt_exists and rpt_new and rpt_size >= 40:
        score += 30
        feedback_parts.append(f"RECIST report OK ({rpt_size} bytes) (30/30)")
    elif rpt_exists and rpt_new and rpt_size >= 20:
        score += 20
        feedback_parts.append(f"Report exists+new but short ({rpt_size} bytes) (20/30)")
    elif rpt_exists and rpt_new:
        score += 10
        feedback_parts.append(f"Report exists+new but very short ({rpt_size} bytes) (10/30)")
    elif rpt_exists:
        feedback_parts.append("Report exists but NOT modified after task start (0/30)")
    else:
        feedback_parts.append("No RECIST report found (0/30)")

    # ---------------------------------------------------------------
    # Criterion 4 (25 pts): Report quality — SLD, measurements, baseline
    # This is the key oncology/RECIST-specific criterion
    # ---------------------------------------------------------------
    if rpt_exists and rpt_new and rpt_size >= 20:
        has_sld = result.get("has_sld_keyword", False)
        has_baseline = result.get("has_baseline_statement", False)
        has_two_lesions = result.get("has_two_lesion_mentions", False)
        meas_count = result.get("measurement_count", 0)
        sld_value = result.get("sld_value", "")

        # Try direct text verification if structured results are incomplete
        needs_direct_check = not (has_sld and has_baseline and meas_count >= 2)

        if needs_direct_check:
            try:
                tmp_rpt = tempfile.NamedTemporaryFile(delete=False, suffix=".txt")
                tmp_rpt.close()
                copy_from_env("/home/ga/DICOM/exports/recist_report.txt", tmp_rpt.name)
                with open(tmp_rpt.name, "r", errors="replace") as f:
                    rpt_text = f.read()
                os.unlink(tmp_rpt.name)

                if not has_sld:
                    has_sld = bool(re.search(
                        r"\b(SLD|sum\s+of\s+longest|sum\s+of\s+diameters)\b",
                        rpt_text, re.IGNORECASE))

                if not has_baseline:
                    has_baseline = bool(re.search(
                        r"\b(baseline|establishes|response\s+monitoring|target\s+lesion|RECIST)\b",
                        rpt_text, re.IGNORECASE))

                if not has_two_lesions:
                    has_two_lesions = bool(re.search(
                        r"\b(lesion\s*[12]|target\s*[12]|measurement\s*[12])\b",
                        rpt_text, re.IGNORECASE))

                if meas_count < 2:
                    # Find all plausible mm measurements (5-300mm range)
                    meas = re.findall(r"\b([5-9][0-9]|1[0-9]{2}|2[0-9]{2}|300)(?:\.[0-9]+)?\s*(?:mm)?\b",
                                      rpt_text)
                    distinct_meas = set(meas)
                    meas_count = len(distinct_meas)

                if not sld_value:
                    sld_match = re.search(
                        r"(SLD|sum)[^0-9]*([0-9]+(?:\.[0-9]+)?)",
                        rpt_text, re.IGNORECASE)
                    if sld_match:
                        sld_value = sld_match.group(2)
            except Exception:
                pass

        # Score the RECIST quality
        recist_score = 0
        recist_details = []

        if has_sld:
            recist_score += 10
            sld_info = f" (SLD={sld_value}mm)" if sld_value else ""
            recist_details.append(f"SLD stated{sld_info}")

        if meas_count >= 2:
            recist_score += 10
            recist_details.append(f"{meas_count} measurements found")
        elif meas_count == 1:
            recist_score += 5
            recist_details.append("only 1 measurement found")

        if has_baseline:
            recist_score += 5
            recist_details.append("baseline statement present")

        score += recist_score
        detail_str = ", ".join(recist_details) if recist_details else "none"
        feedback_parts.append(f"RECIST quality: {detail_str} ({recist_score}/25)")
    else:
        feedback_parts.append("Report unavailable for RECIST quality check (0/25)")

    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
    }
