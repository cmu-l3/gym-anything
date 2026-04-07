#!/usr/bin/env python3
"""
Verifier for osw_enable_do_not_track task.
Ported from OSWorld task 030eeff7-b492-4218-b312-701ec99ee0cc.

Checks that the 'Do Not Track' feature is enabled in Chrome Preferences.
OSWorld metric: exact_match
OSWorld getter: enable_do_not_track (reads Preferences -> enable_do_not_track bool)
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env function available"}

    temp_dir = tempfile.mkdtemp()
    feedback = []

    try:
        # Try to copy Preferences from both possible Chrome profile paths
        prefs_path = os.path.join(temp_dir, "Preferences")
        prefs_data = None

        candidate_paths = [
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences",
        ]

        for candidate in candidate_paths:
            try:
                copy_from_env(candidate, prefs_path)
                if os.path.exists(prefs_path) and os.path.getsize(prefs_path) > 0:
                    with open(prefs_path, 'r', encoding='utf-8') as f:
                        prefs_data = json.load(f)
                    feedback.append(f"Loaded Preferences from {candidate}")
                    break
            except Exception as e:
                feedback.append(f"Could not load from {candidate}: {e}")
                continue

        if prefs_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to load Chrome Preferences from any known path.\n" + "\n".join(feedback)
            }

        # Check enable_do_not_track — mirrors OSWorld getter logic exactly
        # OSWorld: data.get('enable_do_not_track', {}) -> returns "true"/"false"
        # OSWorld metric: exact_match with expected "true"
        do_not_track = prefs_data.get('enable_do_not_track', False)

        if do_not_track is True:
            passed = True
            score = 100
            feedback.append("enable_do_not_track is True — PASS")
        else:
            passed = False
            score = 0
            feedback.append(f"enable_do_not_track is {do_not_track} (expected True) — FAIL")

        return {
            "passed": passed,
            "score": score,
            "feedback": "\n".join(feedback)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Error during verification: {e}"}
    finally:
        import shutil
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir)
