#!/usr/bin/env python3
"""
Verifier for correct_author_metadata task.

Task: Correct author names for Vaswani, LeCun, and Goodfellow.

Scoring (100 points):
  - Vaswani First Name = "Ashish": 30 pts
  - LeCun First Name = "Yann": 15 pts
  - LeCun Last Name = "LeCun": 15 pts
  - Goodfellow First Name = "Ian J.": 30 pts
  - Anti-gaming (DB modified during task): 10 pts

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_correct_author_metadata(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Copy/parse error: {e}"}

    score = 0
    feedback_parts = []
    
    # 1. Check Vaswani (30 pts)
    # Expected: First="Ashish"
    vas_first = result.get("vaswani", {}).get("first", "").strip()
    if vas_first == "Ashish":
        score += 30
        feedback_parts.append("Vaswani corrected (Ashish)")
    else:
        feedback_parts.append(f"Vaswani incorrect ('{vas_first}' vs 'Ashish')")

    # 2. Check LeCun (30 pts total)
    # Expected: First="Yann", Last="LeCun"
    lec_first = result.get("lecun", {}).get("first", "").strip()
    lec_last = result.get("lecun", {}).get("last", "").strip()
    
    if lec_first == "Yann":
        score += 15
        feedback_parts.append("LeCun first name corrected")
    else:
        feedback_parts.append(f"LeCun first name incorrect ('{lec_first}')")
        
    if lec_last == "LeCun":
        score += 15
        feedback_parts.append("LeCun last name capitalization corrected")
    else:
        feedback_parts.append(f"LeCun last name incorrect ('{lec_last}')")

    # 3. Check Goodfellow (30 pts)
    # Expected: First="Ian J."
    gf_first = result.get("goodfellow", {}).get("first", "").strip()
    if gf_first == "Ian J.":
        score += 30
        feedback_parts.append("Goodfellow middle initial added")
    elif gf_first == "Ian":
        feedback_parts.append("Goodfellow missing initial")
    else:
        feedback_parts.append(f"Goodfellow incorrect ('{gf_first}')")

    # 4. Anti-gaming check (10 pts)
    # Did the user actually modify items during the task window?
    mod_count = result.get("modified_count", 0)
    if mod_count > 0:
        score += 10
    else:
        if score > 0:
            feedback_parts.append("Warning: Database timestamp check failed (possible gaming or clock skew)")

    # Pass threshold
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }