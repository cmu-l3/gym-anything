#!/usr/bin/env python3
"""
Verifier for interplanetary_earth_observation task.

Scoring (100 points):
- Observer Planet Set to Saturn (config.ini saved): 30 pts
- Atmosphere Disabled: 15 pts
- Landscape Disabled: 15 pts
- Screenshot Captured: 20 pts
- Exhibit Notes Written with correct info: 20 pts

Pass threshold: 70 points AND must have successfully changed planet to Saturn.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_interplanetary_earth_observation(traj, env_info, task_info):
    """
    Verify the Cassini Earth observation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "interplanetary_earth_observation"

    try:
        # Copy result JSON from VM
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name

        try:
            copy_from_env(f"/tmp/{task_name}_result.json", tmp_path)
            with open(tmp_path, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)

        score = 0
        feedback_parts = []
        subscores = {}

        # ── Criterion 1: Observer Planet (30 pts) ──────────────────────────
        home_planet = result.get('home_planet', '').lower()
        
        if 'saturn' in home_planet:
            score += 30
            subscores["planet"] = True
            feedback_parts.append("Observer planet correctly set to Saturn")
        else:
            subscores["planet"] = False
            feedback_parts.append(f"Observer planet not set to Saturn (found '{home_planet}')")

        # ── Criterion 2: Atmosphere disabled (15 pts) ────────────────────────
        flag_atmosphere = result.get('flag_atmosphere')
        if flag_atmosphere is False:
            score += 15
            subscores["atmosphere"] = True
            feedback_parts.append("Atmosphere disabled")
        else:
            subscores["atmosphere"] = False
            feedback_parts.append("Atmosphere still enabled (should be off for space view)")

        # ── Criterion 3: Landscape disabled (15 pts) ─────────────────────────
        flag_landscape = result.get('flag_landscape')
        if flag_landscape is False:
            score += 15
            subscores["landscape"] = True
            feedback_parts.append("Landscape/ground disabled")
        else:
            subscores["landscape"] = False
            feedback_parts.append("Landscape still enabled (should be off for space view)")

        # ── Criterion 4: Screenshot taken (20 pts) ───────────────────────────
        new_ss = result.get('new_screenshot_count', 0)
        if new_ss >= 1:
            score += 20
            subscores["screenshot"] = True
            feedback_parts.append(f"{new_ss} screenshots captured")
        else:
            subscores["screenshot"] = False
            feedback_parts.append("No screenshots taken")

        # ── Criterion 5: Exhibit Notes (20 pts) ──────────────────────────────
        notes_exists = result.get('notes_exists', False)
        notes_content = result.get('notes_content', '').lower()
        
        keywords_found = 0
        required_keywords = [
            "the day the earth smiled",
            "saturn",
            "earth",
            "2013"
        ]
        
        if notes_exists:
            for kw in required_keywords:
                if kw.lower() in notes_content:
                    keywords_found += 1
            
            if keywords_found == 4:
                score += 20
                subscores["notes"] = True
                feedback_parts.append("Exhibit notes contain all required keywords")
            elif keywords_found > 0:
                pts = keywords_found * 5
                score += pts
                subscores["notes"] = False
                feedback_parts.append(f"Exhibit notes missing some keywords (found {keywords_found}/4)")
            else:
                subscores["notes"] = False
                feedback_parts.append("Exhibit notes created but missing required keywords")
        else:
            subscores["notes"] = False
            feedback_parts.append("Exhibit notes file not found")

        # ── Final Determination ──────────────────────────────────────────────
        passed = score >= 70 and subscores.get("planet") is True
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": subscores
        }

    except Exception as e:
        logger.error(f"Error during verification: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification script error: {str(e)}"
        }