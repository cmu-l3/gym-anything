#!/usr/bin/env python3
"""
Verifier for urologist_dicom_metadata_audit task.

Error injection pattern: setup_task.sh corrupts 3 DICOM metadata tags.
The agent must discover and fix them without being told which tags are wrong.

Injected errors:
  1. PatientSex: M -> F
  2. BodyPartExamined: ABDOMEN -> HEAD
  3. ReferringPhysicianName: "Dr. Smith" -> ""

Scoring (100 points):
- 15 pts: Report file exists, is new, >= 50 chars
- 25 pts: PatientSex corrected back to M in all DICOM files
- 25 pts: BodyPartExamined corrected back to ABDOMEN (or valid body region)
- 20 pts: ReferringPhysicianName corrected to non-empty value
- 15 pts: Audit report mentions at least 2 of the 3 corrected tags

Pass threshold: 60 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/urologist_metadata_audit_result.json"
PASS_THRESHOLD = 60


def verify_urologist_dicom_metadata_audit(traj, env_info, task_info):
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
    # Criterion 1 (15 pts): Report file exists, is new, adequate size
    # ---------------------------------------------------------------
    rpt_exists = result.get("report_exists", False)
    rpt_new = result.get("report_is_new", False)
    rpt_size = result.get("report_size", 0)

    if rpt_exists and rpt_new and rpt_size >= 50:
        score += 15
        feedback_parts.append(f"Report file OK ({rpt_size} bytes) (15/15)")
    elif rpt_exists and rpt_new:
        score += 8
        feedback_parts.append(f"Report short ({rpt_size} bytes) (8/15)")
    elif rpt_exists:
        feedback_parts.append("Report exists but NOT modified after task start (0/15)")
    else:
        feedback_parts.append("No audit report found (0/15)")

    # ---------------------------------------------------------------
    # Criterion 2 (25 pts): PatientSex corrected to M
    # ---------------------------------------------------------------
    sex_corrected = result.get("sex_corrected", False)
    current_sex = result.get("current_sex_values", [])

    if sex_corrected:
        score += 25
        feedback_parts.append("PatientSex corrected to M (25/25)")
    elif "M" in current_sex:
        # Partially corrected (some files fixed)
        score += 12
        feedback_parts.append(f"PatientSex partially corrected: {current_sex} (12/25)")
    else:
        feedback_parts.append(f"PatientSex NOT corrected: {current_sex} (0/25)")

    # ---------------------------------------------------------------
    # Criterion 3 (25 pts): BodyPartExamined corrected
    # ---------------------------------------------------------------
    body_corrected = result.get("body_part_corrected", False)
    current_body = result.get("current_body_part_values", [])

    if body_corrected:
        score += 25
        feedback_parts.append("BodyPartExamined corrected (25/25)")
    elif any(v.upper() not in ["HEAD", ""] for v in current_body):
        score += 12
        feedback_parts.append(f"BodyPartExamined partially corrected: {current_body} (12/25)")
    else:
        feedback_parts.append(f"BodyPartExamined NOT corrected: {current_body} (0/25)")

    # ---------------------------------------------------------------
    # Criterion 4 (20 pts): ReferringPhysicianName restored
    # ---------------------------------------------------------------
    physician_corrected = result.get("physician_corrected", False)
    current_physician = result.get("current_physician_values", [])

    if physician_corrected:
        score += 20
        feedback_parts.append("ReferringPhysicianName restored (20/20)")
    elif any(v.strip() for v in current_physician):
        score += 10
        feedback_parts.append(f"ReferringPhysicianName partially restored (10/20)")
    else:
        feedback_parts.append("ReferringPhysicianName still empty (0/20)")

    # ---------------------------------------------------------------
    # Criterion 5 (15 pts): Report documents the corrections
    # ---------------------------------------------------------------
    mentions_sex = result.get("report_mentions_sex", False)
    mentions_body = result.get("report_mentions_body_part", False)
    mentions_physician = result.get("report_mentions_physician", False)
    tag_mentions = sum([mentions_sex, mentions_body, mentions_physician])

    if tag_mentions >= 3:
        score += 15
        feedback_parts.append("All 3 tags documented in report (15/15)")
    elif tag_mentions >= 2:
        score += 10
        feedback_parts.append(f"{tag_mentions} tags documented in report (10/15)")
    elif tag_mentions >= 1:
        score += 5
        feedback_parts.append(f"Only {tag_mentions} tag documented (5/15)")
    else:
        feedback_parts.append("No tag corrections documented (0/15)")

    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
    }
