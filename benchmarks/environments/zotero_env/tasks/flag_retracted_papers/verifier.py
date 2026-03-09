#!/usr/bin/env python3
"""
Verifier for flag_retracted_papers task.
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logger = logging.getLogger(__name__)

def verify_flag_retracted_papers(traj, env_info, task_info):
    """
    Verify that two specific papers have been correctly flagged as retracted.
    
    Criteria per paper:
    1. Title starts with "RETRACTED: " (20 pts)
    2. Tag "retracted" exists (15 pts)
    3. Extra field contains "Status: Retracted" (15 pts)
    
    Total: 50 pts per paper * 2 papers = 100 pts.
    Pass threshold: 70 pts.
    """
    
    # 1. Retrieve result JSON
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Database inspection failed: {result['error']}"}

    score = 0
    feedback = []
    
    papers = result.get("papers", {})
    
    # --- Check Paper 1: Generative Adversarial Nets (key: gan) ---
    p1 = papers.get("gan", {})
    if not p1.get("found"):
        feedback.append("Paper 1 (GANs) not found in library.")
    else:
        p1_score = 0
        # Title
        title = p1.get("title", "")
        if title.startswith("RETRACTED: "):
            p1_score += 20
        else:
            feedback.append(f"Paper 1 title incorrect: '{title}' (expected 'RETRACTED: ...')")
            
        # Tag
        tags = p1.get("tags", [])
        if "retracted" in tags:
            p1_score += 15
        else:
            feedback.append(f"Paper 1 missing 'retracted' tag. Found: {tags}")

        # Extra
        extra = p1.get("extra", "")
        if "Status: Retracted" in extra:
            p1_score += 15
        else:
            feedback.append(f"Paper 1 Extra field missing 'Status: Retracted'. Found: '{extra}'")
            
        score += p1_score

    # --- Check Paper 2: Deep Learning (key: dl) ---
    p2 = papers.get("dl", {})
    if not p2.get("found"):
        feedback.append("Paper 2 (Deep Learning) not found in library.")
    else:
        p2_score = 0
        # Title
        title = p2.get("title", "")
        if title.startswith("RETRACTED: "):
            p2_score += 20
        else:
            feedback.append(f"Paper 2 title incorrect: '{title}'")
            
        # Tag
        tags = p2.get("tags", [])
        if "retracted" in tags:
            p2_score += 15
        else:
            feedback.append(f"Paper 2 missing 'retracted' tag.")

        # Extra
        extra = p2.get("extra", "")
        if "Status: Retracted" in extra:
            p2_score += 15
        else:
            feedback.append(f"Paper 2 Extra field incorrect.")
            
        score += p2_score

    # Anti-gaming check (optional but recommended)
    # If scores are perfect but no modification recorded?
    # The export script didn't robustly parse date, but we can implicitly trust content changes 
    # since we know the initial state (seeded) does NOT have these values.
    # So "content change" IS proof of work here.

    passed = score >= 70
    final_feedback = "All checks passed." if not feedback else "; ".join(feedback)

    return {
        "passed": passed,
        "score": score,
        "feedback": final_feedback
    }