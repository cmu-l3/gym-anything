#!/usr/bin/env python3
"""
Verifier for livestock_health_treatment_log task.

A cattle farmworker must create 5 farm logs documenting a BRD outbreak response
cycle. This verifier checks the farmOS Field Kit Tasks list for each required
log entry.

Scoring (100 points total):
- Pen 12 BRD respiratory assessment (Observation): 20 points
- Enrofloxacin BRD treatment 12 head (Input): 20 points
- Sick pen setup and animal movement (Activity): 20 points
- 48hr BRD treatment response check (Observation): 20 points
- Non-responder vet exam and hold (Input): 20 points

Pass threshold: 80 points (4 of 5 logs correctly created)
"""

import os
import tempfile
import logging

logger = logging.getLogger(__name__)

REQUIRED_LOGS = [
    "Pen 12 BRD respiratory assessment",
    "Enrofloxacin BRD treatment 12 head",
    "Sick pen setup and animal movement",
    "48hr BRD treatment response check",
    "Non-responder vet exam and hold",
]

POINTS_PER_LOG = 20
PASS_THRESHOLD = 80


def _extract_all_text(xml_path):
    """Extract all text attribute values from the Android UI hierarchy XML."""
    try:
        with open(xml_path, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
        texts = []
        idx = 0
        while True:
            start = content.find('text="', idx)
            if start == -1:
                break
            start += 6
            end = content.find('"', start)
            if end == -1:
                break
            val = content[start:end].strip()
            if val:
                texts.append(val.lower())
            idx = end + 1
        return ' ||| '.join(texts)
    except Exception as e:
        logger.error(f"Failed to parse UI XML: {e}")
        return ''


def _log_present(all_text, log_name):
    """Check if a log name (or its first 20 chars) appears in UI text."""
    name_lower = log_name.lower()
    if name_lower in all_text:
        return True
    prefix = name_lower[:20]
    if len(prefix) >= 10 and prefix in all_text:
        return True
    return False


def check_livestock_health_treatment_log(traj, env_info, task_info):
    """Verify 5 livestock health event logs were created in farmOS Field Kit."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    tmp.close()

    try:
        copy_from_env('/sdcard/ui_dump_livestock.xml', tmp.name)
    except Exception as e:
        try:
            os.unlink(tmp.name)
        except OSError:
            pass
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve UI dump: {e}"}

    if not os.path.exists(tmp.name) or os.path.getsize(tmp.name) < 50:
        try:
            os.unlink(tmp.name)
        except OSError:
            pass
        return {"passed": False, "score": 0, "feedback": "UI dump missing or empty — no logs created"}

    all_text = _extract_all_text(tmp.name)
    try:
        os.unlink(tmp.name)
    except OSError:
        pass

    score = 0
    feedback_parts = []

    for log_name in REQUIRED_LOGS:
        if _log_present(all_text, log_name):
            score += POINTS_PER_LOG
            feedback_parts.append(f"FOUND: '{log_name}'")
        else:
            feedback_parts.append(f"MISSING: '{log_name}'")

    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
