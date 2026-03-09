#!/usr/bin/env python3
"""
Verifier for crop_spray_day_records task.

A Precision Agriculture Technician must create 5 farm logs documenting a full
spray application day. This verifier checks the farmOS Field Kit Tasks list
for the presence of each required log entry.

Scoring (100 points total):
- Pre-spray boom calibration check (Activity): 20 points
- Glyphosate application Field 3 North (Input): 20 points
- Azoxystrobin fungicide Field 3 South (Input): 20 points
- Post-spray drift assessment (Observation): 20 points
- Sprayer rinse and storage (Activity): 20 points

Pass threshold: 80 points (4 of 5 logs correctly created)
"""

import os
import tempfile
import logging

logger = logging.getLogger(__name__)

REQUIRED_LOGS = [
    "Pre-spray boom calibration check",
    "Glyphosate application Field 3 North",
    "Azoxystrobin fungicide Field 3 South",
    "Post-spray drift assessment",
    "Sprayer rinse and storage",
]

POINTS_PER_LOG = 20
PASS_THRESHOLD = 80


def _extract_all_text(xml_path):
    """Extract all text attribute values from the Android UI hierarchy XML."""
    try:
        with open(xml_path, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
        # Collect all text="..." values via simple string search
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
    # Fallback: check first 20 characters (handles UI truncation)
    prefix = name_lower[:20]
    if len(prefix) >= 10 and prefix in all_text:
        return True
    return False


def check_crop_spray_day_records(traj, env_info, task_info):
    """Verify 5 spray-day logs were created in farmOS Field Kit."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    tmp.close()

    try:
        copy_from_env('/sdcard/ui_dump_crop_spray.xml', tmp.name)
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
