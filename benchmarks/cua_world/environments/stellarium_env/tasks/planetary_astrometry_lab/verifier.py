#!/usr/bin/env python3
"""
Verifier for planetary_astrometry_lab task.

Scoring System (100 points total):
- Atmosphere Disabled (flag_atmosphere = false): 15 pts
- Landscape Disabled (flag_landscape = false): 15 pts
- Equatorial Grid Enabled (flag_equatorial_grid = true): 20 pts
- Telescopic Screenshots (2+ new images): 25 pts
- Lab Key Generated with 5 specific keywords: 25 pts (5 pts per keyword)

Pass Threshold: 75 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_planetary_astrometry_lab(traj, env_info, task_info):
    """
    Verify the planetary astrometry lab task.
    Reads the JSON result exported from the VM.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    task_name = "planetary_astrometry_lab"

    try:
        # Securely copy the result file from the environment
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
        
        # 1. Check Atmosphere (15 points)
        flag_atm = result.get('flag_atmosphere')
        if flag_atm is False:
            score += 15
            feedback_parts.append("Atmosphere disabled (+15)")
        else:
            feedback_parts.append(f"Atmosphere still enabled (flag={flag_atm})")

        # 2. Check Landscape (15 points)
        flag_landscape = result.get('flag_landscape')
        if flag_landscape is False:
            score += 15
            feedback_parts.append("Landscape/Ground disabled (+15)")
        else:
            feedback_parts.append(f"Landscape still enabled (flag={flag_landscape})")

        # 3. Check Equatorial Grid (20 points)
        flag_grid = result.get('flag_equatorial_grid')
        if flag_grid is True:
            score += 20
            feedback_parts.append("Equatorial grid enabled (+20)")
        else:
            feedback_parts.append(f"Equatorial grid not enabled (flag={flag_grid})")

        # 4. Check Screenshots (25 points)
        new_ss = result.get('new_screenshot_count', 0)
        if new_ss >= 2:
            score += 25
            feedback_parts.append(f"Telescopic screenshots taken ({new_ss} captured) (+25)")
        elif new_ss == 1:
            score += 12
            feedback_parts.append(f"Only 1 screenshot captured (expected 2+) (+12)")
        else:
            feedback_parts.append("No new screenshots taken")

        # 5. Check Lab Key Text File (25 points)
        lab_key_exists = result.get('lab_key_exists', False)
        lab_key_content = result.get('lab_key_content', '').lower()
        
        keywords = ["io", "europa", "ganymede", "callisto", "titan"]
        found_keywords = 0
        
        if lab_key_exists:
            for kw in keywords:
                if kw in lab_key_content:
                    found_keywords += 1
            
            pts_per_kw = 5
            kw_score = found_keywords * pts_per_kw
            score += kw_score
            
            if found_keywords == len(keywords):
                feedback_parts.append(f"Lab key generated successfully with all moons (+{kw_score})")
            else:
                feedback_parts.append(f"Lab key generated but missing moons (found {found_keywords}/5) (+{kw_score})")
        else:
            feedback_parts.append("Lab key file (astrometry_key.txt) not found")

        # Evaluate Pass/Fail
        passed = score >= 75
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result JSON not found. The agent may not have completed the task."}
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Error during verification: {e}"}