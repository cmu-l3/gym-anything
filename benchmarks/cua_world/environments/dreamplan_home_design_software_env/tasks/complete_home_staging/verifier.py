#!/usr/bin/env python3
"""
Verifier for complete_home_staging task.

The agent (home stager) must:
1. Place sofa + coffee table in living room
2. Place dining table + 2 chairs in dining room
3. Place bed + 1 item in bedroom
4. Export living room view → C:\\Users\\Docker\\Desktop\\staged_living_room.jpg
5. Export dining room view → C:\\Users\\Docker\\Desktop\\staged_dining_room.jpg
6. Export bedroom view → C:\\Users\\Docker\\Desktop\\staged_bedroom.jpg

Scoring (100 points total):
  - staged_living_room.jpg exists AND is new: 15 pts
  - staged_living_room.jpg size > 30 KB: 10 pts
  - staged_dining_room.jpg exists AND is new: 15 pts
  - staged_dining_room.jpg size > 30 KB: 10 pts
  - staged_bedroom.jpg exists AND is new: 15 pts
  - staged_bedroom.jpg size > 30 KB: 10 pts
  - All 3 files present and new: 25 pts bonus

Pass threshold: >= 60 points AND at least 2 room images exist and are new.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\complete_home_staging_result.json"


def verify_complete_home_staging(traj, env_info, task_info):
    """
    Verify complete home staging task.

    Reads result JSON from export_result.ps1 which contains per-file info:
      exists, size_bytes, mtime_unix, is_new
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0,
                "feedback": "copy_from_env not available"}

    # ----------------------------------------------------------------
    # Load result JSON from VM
    # ----------------------------------------------------------------
    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH, temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
        logger.info(f"Result loaded: {result}")
    except Exception as e:
        logger.warning(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0,
                "feedback": f"Could not read result file. Export may have failed: {e}"}
    finally:
        try:
            os.unlink(temp_file.name)
        except Exception:
            pass

    # ----------------------------------------------------------------
    # Scoring
    # ----------------------------------------------------------------
    score = 0
    feedback_parts = []

    def fi(key):
        v = result.get(key, {})
        if not isinstance(v, dict):
            return {}
        return v

    rliving  = fi('staged_living_room_jpg')
    rdining  = fi('staged_dining_room_jpg')
    rbedroom = fi('staged_bedroom_jpg')

    new_count = 0

    # Criterion 1a: Living room image exists and is new (15 pts)
    if rliving.get('exists') and rliving.get('is_new'):
        score += 15
        new_count += 1
        feedback_parts.append("Living room staged image exported.")
    elif rliving.get('exists') and not rliving.get('is_new'):
        feedback_parts.append("Living room image predates task start (stale).")
    else:
        feedback_parts.append("MISSING: staged_living_room.jpg not found.")

    # Criterion 1b: Living room image has real content (10 pts)
    if rliving.get('exists') and rliving.get('is_new') and rliving.get('size_bytes', 0) >= 30000:
        score += 10
        feedback_parts.append(f"Living room image has content ({rliving['size_bytes']:,} bytes).")
    elif rliving.get('exists') and rliving.get('is_new'):
        feedback_parts.append(f"Living room image too small ({rliving.get('size_bytes', 0):,} bytes).")

    # Criterion 2a: Dining room image exists and is new (15 pts)
    if rdining.get('exists') and rdining.get('is_new'):
        score += 15
        new_count += 1
        feedback_parts.append("Dining room staged image exported.")
    elif rdining.get('exists') and not rdining.get('is_new'):
        feedback_parts.append("Dining room image predates task start (stale).")
    else:
        feedback_parts.append("MISSING: staged_dining_room.jpg not found.")

    # Criterion 2b: Dining room image has real content (10 pts)
    if rdining.get('exists') and rdining.get('is_new') and rdining.get('size_bytes', 0) >= 30000:
        score += 10
        feedback_parts.append(f"Dining room image has content ({rdining['size_bytes']:,} bytes).")
    elif rdining.get('exists') and rdining.get('is_new'):
        feedback_parts.append(f"Dining room image too small ({rdining.get('size_bytes', 0):,} bytes).")

    # Criterion 3a: Bedroom image exists and is new (15 pts)
    if rbedroom.get('exists') and rbedroom.get('is_new'):
        score += 15
        new_count += 1
        feedback_parts.append("Bedroom staged image exported.")
    elif rbedroom.get('exists') and not rbedroom.get('is_new'):
        feedback_parts.append("Bedroom image predates task start (stale).")
    else:
        feedback_parts.append("MISSING: staged_bedroom.jpg not found.")

    # Criterion 3b: Bedroom image has real content (10 pts)
    if rbedroom.get('exists') and rbedroom.get('is_new') and rbedroom.get('size_bytes', 0) >= 30000:
        score += 10
        feedback_parts.append(f"Bedroom image has content ({rbedroom['size_bytes']:,} bytes).")
    elif rbedroom.get('exists') and rbedroom.get('is_new'):
        feedback_parts.append(f"Bedroom image too small ({rbedroom.get('size_bytes', 0):,} bytes).")

    # Criterion 4: All 3 rooms staged (25 pts bonus)
    if new_count == 3:
        score += 25
        feedback_parts.append("All 3 room staging images delivered — complete package.")
    else:
        feedback_parts.append(f"Only {new_count}/3 required room images delivered.")

    score = min(score, 100)

    # Pass: >= 60 points AND at least 2 room images exist and are new
    passed = score >= 60 and new_count >= 2

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
