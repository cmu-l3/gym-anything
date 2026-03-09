#!/usr/bin/env python3
"""
Verifier for allergist_series_contamination_cleanup task.

Contamination injection pattern: setup_task.sh mixes 4 MR brain DICOM files
into a CT chest directory. The agent must identify and remove the contaminants
by inspecting DICOM headers (Modality, PatientName, StudyDescription).

Scoring (100 points):
- 35 pts: At least 3 of 4 contaminant files removed from study directory
- 20 pts: Legitimate CT files preserved (not deleted by mistake)
- 15 pts: Report file exists, is new, >= 50 chars
- 15 pts: Report mentions modality difference (CT vs MR)
- 15 pts: Report mentions number of contaminating files found/removed

Pass threshold: 55 points (lower per contamination injection guidelines)
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/allergist_contamination_result.json"
PASS_THRESHOLD = 55


def verify_allergist_series_contamination_cleanup(traj, env_info, task_info):
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

    injected = result.get("contaminants_injected", 4)
    removed = result.get("contaminants_removed", 0)
    remaining = result.get("contaminants_remaining", injected)

    # ---------------------------------------------------------------
    # Criterion 1 (35 pts): Contaminant files removed
    # ---------------------------------------------------------------
    if removed >= injected:
        score += 35
        feedback_parts.append(f"All {injected} contaminants removed (35/35)")
    elif removed >= injected - 1:
        score += 28
        feedback_parts.append(f"{removed}/{injected} contaminants removed (28/35)")
    elif removed >= 2:
        score += 18
        feedback_parts.append(f"Only {removed}/{injected} contaminants removed (18/35)")
    elif removed >= 1:
        score += 8
        feedback_parts.append(f"Only {removed}/{injected} contaminant removed (8/35)")
    else:
        feedback_parts.append(f"No contaminants removed ({remaining} still present) (0/35)")

    # ---------------------------------------------------------------
    # Criterion 2 (20 pts): Legitimate CT files preserved
    # Only scored if agent took cleanup action (removed >= 1 contaminant),
    # otherwise do-nothing would score 20 pts for "preserving" files.
    # ---------------------------------------------------------------
    ct_preserved = result.get("ct_files_preserved", False)
    current_total = result.get("current_total_files", 0)
    original_ct = result.get("original_ct_count", 0)

    if removed == 0:
        feedback_parts.append("No cleanup action taken — CT preservation not scored (0/20)")
    elif ct_preserved and current_total > 0:
        score += 20
        feedback_parts.append(f"CT files preserved ({current_total} files remain) (20/20)")
    elif current_total >= original_ct * 0.8:
        score += 12
        feedback_parts.append(f"Most CT files preserved ({current_total}/{original_ct}) (12/20)")
    elif current_total > 0:
        score += 5
        feedback_parts.append(f"Some files remain but many CT files may be deleted ({current_total}/{original_ct}) (5/20)")
    else:
        feedback_parts.append("Directory empty — all files deleted including CTs (0/20)")

    # ---------------------------------------------------------------
    # Criterion 3 (15 pts): Report file exists and has content
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
        feedback_parts.append("No contamination report found (0/15)")

    # ---------------------------------------------------------------
    # Criterion 4 (15 pts): Report mentions modality difference
    # ---------------------------------------------------------------
    mentions_modality = result.get("report_mentions_modality", False)

    if mentions_modality:
        score += 15
        feedback_parts.append("Report mentions modality (CT/MR) (15/15)")
    else:
        feedback_parts.append("Report does not mention modality difference (0/15)")

    # ---------------------------------------------------------------
    # Criterion 5 (15 pts): Report mentions file count
    # ---------------------------------------------------------------
    mentions_count = result.get("report_mentions_count", False)

    if mentions_count:
        score += 15
        feedback_parts.append("Report mentions contamination count (15/15)")
    else:
        feedback_parts.append("Report does not mention number of files (0/15)")

    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
    }
