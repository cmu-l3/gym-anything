#!/usr/bin/env python3
"""Verifier for configure_low_bandwidth_tor_profile task.

Verifies that the agent successfully configured three integer preferences
in Tor Browser via about:config to block images, fonts, and autoplay,
and verified the configuration by saving a screenshot of Wikipedia.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TASK_NAME = "configure_low_bandwidth_tor_profile"


def verify_low_bandwidth_profile(traj, env_info, task_info):
    """
    Scoring (100 points total):
    1. Images Blocked (permissions.default.image = 2)     - 30 pts [REQUIRED GATE]
    2. Fonts Blocked (browser.display.use_document_fonts = 0) - 20 pts
    3. Autoplay Blocked (media.autoplay.default = 5)      - 20 pts
    4. Screenshot Exists (and is new/valid size)          - 15 pts
    5. Wikipedia Visited (history_has_wikipedia = True)   - 15 pts

    Pass threshold: 70+ points AND Images Blocked (permissions.default.image = 2)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    
    try:
        try:
            copy_from_env(f"/tmp/{TASK_NAME}_result.json", tmp.name)
            with open(tmp.name, 'r', encoding='utf-8-sig') as f:
                result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to read result: {e}")
            return {"passed": False, "score": 0, "feedback": f"Result file not found: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    logger.info(f"Result: {json.dumps(result, indent=2)}")

    score = 0
    feedback_parts = []

    if not result.get('prefs_found', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Tor Browser prefs.js not found — browser was not used or configured"
        }

    # Criterion 1: Images Blocked [REQUIRED GATE]
    pref_image = result.get('pref_image', -1)
    images_blocked = (pref_image == 2)
    if images_blocked:
        score += 30
        feedback_parts.append("Images blocked (permissions.default.image=2) (30/30)")
    else:
        feedback_parts.append(f"Images NOT correctly blocked (permissions.default.image={pref_image}, expected 2) (0/30)")

    # Criterion 2: Fonts Blocked
    pref_fonts = result.get('pref_fonts', -1)
    if pref_fonts == 0:
        score += 20
        feedback_parts.append("Fonts blocked (browser.display.use_document_fonts=0) (20/20)")
    else:
        feedback_parts.append(f"Fonts NOT correctly blocked (use_document_fonts={pref_fonts}, expected 0) (0/20)")

    # Criterion 3: Autoplay Blocked
    pref_media = result.get('pref_media', -1)
    if pref_media == 5:
        score += 20
        feedback_parts.append("Media autoplay blocked (media.autoplay.default=5) (20/20)")
    else:
        feedback_parts.append(f"Media autoplay NOT correctly blocked (autoplay.default={pref_media}, expected 5) (0/20)")

    # Criterion 4: Screenshot Exists & is new
    file_exists = result.get('file_exists', False)
    file_is_new = result.get('file_is_new', False)
    file_size = result.get('file_size', 0)
    
    if file_exists and file_is_new and file_size > 1024:
        score += 15
        feedback_parts.append("Screenshot saved correctly during task (15/15)")
    elif file_exists and file_size > 1024:
        # Exists but predates task
        score += 5
        feedback_parts.append("Screenshot found but predates task start (5/15)")
    else:
        feedback_parts.append("Screenshot missing, empty, or not saved correctly (0/15)")

    # Criterion 5: Wikipedia Visited
    if result.get('history_has_wikipedia', False):
        score += 15
        feedback_parts.append("Wikipedia visited via Tor (15/15)")
    else:
        feedback_parts.append("Wikipedia NOT found in browsing history (0/15)")

    # Check passing conditions
    passed = (score >= 70) and images_blocked
    
    if passed:
        feedback_parts.insert(0, "SUCCESS:")
    else:
        if not images_blocked:
            feedback_parts.insert(0, "FAIL (Required gate 'permissions.default.image=2' not met):")
        else:
            feedback_parts.insert(0, "FAIL (Score below 70):")

    feedback = " | ".join(feedback_parts)
    logger.info(f"Score: {score}/100, Passed: {passed}")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": feedback,
        "subscores": {
            "images_blocked": 30 if images_blocked else 0,
            "fonts_blocked": 20 if pref_fonts == 0 else 0,
            "autoplay_blocked": 20 if pref_media == 5 else 0,
            "screenshot_saved": 15 if (file_exists and file_is_new and file_size > 1024) else (5 if file_exists else 0),
            "wikipedia_visited": 15 if result.get('history_has_wikipedia') else 0
        }
    }