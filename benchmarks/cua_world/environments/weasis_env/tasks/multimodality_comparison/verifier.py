#!/usr/bin/env python3
"""
Verifier for multimodality_comparison task.

A PM&R physician must:
1. Load BOTH CT and MRI series simultaneously in Weasis
2. Configure side-by-side (1×2) layout
3. Apply appropriate W/L to each modality (bone window for CT, soft tissue for MRI)
4. Measure a bony structure on CT and corresponding soft tissue on MRI
5. Export comparison view to /home/ga/DICOM/exports/comparison_view.png
6. Write correlation report to /home/ga/DICOM/exports/comparison_report.txt
   mentioning measurements from BOTH modalities

Scoring (100 points):
- 30 pts: Export comparison image exists, is newer than task start, size >= 50KB
          (larger threshold — side-by-side view should be bigger than single-image export)
- 25 pts: Report exists, is newer than task start, has content (>30 chars)
- 25 pts: Report mentions BOTH CT and MRI modalities explicitly
- 20 pts: Report contains at least two distinct numerical measurements (mm range)

Pass threshold: 60 points
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/multimodality_comparison_result.json"
PASS_THRESHOLD = 60


def verify_multimodality_comparison(traj, env_info, task_info):
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
    # Criterion 1 (30 pts): Comparison image — exists, new, ≥50KB
    # Side-by-side export of two series should be larger
    # ---------------------------------------------------------------
    img_exists = result.get("image_exists", False)
    img_new = result.get("image_is_new", False)
    img_size_kb = result.get("image_size_kb", 0)
    new_png_count = result.get("new_png_count", 0)
    any_new_png = result.get("any_new_png_exports", "")

    if img_exists and img_new and img_size_kb >= 50:
        score += 30
        feedback_parts.append(f"Comparison image OK ({img_size_kb}KB) (30/30)")
    elif img_exists and img_new and img_size_kb >= 20:
        score += 20
        feedback_parts.append(f"Comparison image exists+new ({img_size_kb}KB, expected ≥50KB) (20/30)")
    elif new_png_count >= 2:
        # Agent exported two separate images instead of a combined view — partial credit
        score += 20
        feedback_parts.append(f"{new_png_count} new PNG files found (20/30)")
    elif new_png_count == 1 and any_new_png:
        score += 15
        feedback_parts.append(f"One new PNG found (expected comparison layout) (15/30)")
    elif img_exists:
        feedback_parts.append("Export image exists but NOT modified after task start (0/30)")
    else:
        feedback_parts.append("No comparison export image found (0/30)")

    # ---------------------------------------------------------------
    # Criterion 2 (25 pts): Report exists, new, meaningful
    # ---------------------------------------------------------------
    rpt_exists = result.get("report_exists", False)
    rpt_new = result.get("report_is_new", False)
    rpt_size = result.get("report_size_bytes", 0)

    if rpt_exists and rpt_new and rpt_size >= 30:
        score += 25
        feedback_parts.append(f"Comparison report OK ({rpt_size} bytes) (25/25)")
    elif rpt_exists and rpt_new:
        score += 12
        feedback_parts.append(f"Report exists+new but very short ({rpt_size} bytes) (12/25)")
    elif rpt_exists:
        feedback_parts.append("Report exists but NOT modified after task start (0/25)")
    else:
        feedback_parts.append("No comparison report found (0/25)")

    # ---------------------------------------------------------------
    # Criterion 3 (25 pts): Report mentions BOTH CT and MRI
    # This is the key criterion — proves both series were actually loaded
    # ---------------------------------------------------------------
    ct_mentioned = result.get("ct_mentioned_in_report", False)
    mri_mentioned = result.get("mri_mentioned_in_report", False)

    if ct_mentioned and mri_mentioned:
        score += 25
        feedback_parts.append("Both CT and MRI mentioned in report (25/25)")
    elif ct_mentioned or mri_mentioned:
        score += 12
        modality = "CT" if ct_mentioned else "MRI"
        feedback_parts.append(f"Only {modality} mentioned in report (12/25)")
    else:
        # Try direct check on report text
        if rpt_exists and rpt_new:
            try:
                tmp_rpt = tempfile.NamedTemporaryFile(delete=False, suffix=".txt")
                tmp_rpt.close()
                copy_from_env("/home/ga/DICOM/exports/comparison_report.txt", tmp_rpt.name)
                with open(tmp_rpt.name, "r", errors="replace") as f:
                    rpt_text = f.read()
                os.unlink(tmp_rpt.name)
                has_ct = bool(re.search(r"\b(CT|computed tomography)\b", rpt_text, re.IGNORECASE))
                has_mri = bool(re.search(r"\b(MRI|MR|magnetic resonance)\b", rpt_text, re.IGNORECASE))
                if has_ct and has_mri:
                    score += 25
                    feedback_parts.append("Both CT and MRI in report (25/25)")
                elif has_ct or has_mri:
                    score += 12
                    feedback_parts.append("Only one modality mentioned in report (12/25)")
                else:
                    feedback_parts.append("Neither CT nor MRI mentioned in report (0/25)")
            except Exception:
                feedback_parts.append("Could not verify modality mentions (0/25)")
        else:
            feedback_parts.append("Report not available for modality check (0/25)")

    # ---------------------------------------------------------------
    # Criterion 4 (20 pts): Report has ≥2 distinct numerical measurements
    # ---------------------------------------------------------------
    if rpt_exists and rpt_new:
        try:
            tmp_rpt2 = tempfile.NamedTemporaryFile(delete=False, suffix=".txt")
            tmp_rpt2.close()
            copy_from_env("/home/ga/DICOM/exports/comparison_report.txt", tmp_rpt2.name)
            with open(tmp_rpt2.name, "r", errors="replace") as f:
                rpt_text2 = f.read()
            os.unlink(tmp_rpt2.name)
            # Look for numerical values in realistic anatomical measurement range
            nums = re.findall(r"\b([1-9][0-9]{1,2}(?:\.[0-9]+)?)\b", rpt_text2)
            distinct = set(nums)
            if len(distinct) >= 2:
                score += 20
                feedback_parts.append(f"{len(distinct)} distinct measurements in report (20/20)")
            elif len(distinct) == 1:
                score += 10
                feedback_parts.append("Only 1 measurement in report (10/20)")
            else:
                feedback_parts.append("No numerical measurements in report (0/20)")
        except Exception:
            feedback_parts.append("Could not verify measurements in report (0/20)")
    else:
        feedback_parts.append("Report unavailable for measurement check (0/20)")

    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
    }
