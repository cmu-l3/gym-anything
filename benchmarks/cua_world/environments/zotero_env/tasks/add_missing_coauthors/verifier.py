#!/usr/bin/env python3
"""
Verifier for add_missing_coauthors task.

Scoring breakdown (100 pts total):
1. Attention Is All You Need (25 pts)
   - Shazeer (8), Parmar (8), Uszkoreit (9)
2. Deep Residual Learning (25 pts)
   - Zhang (8), Ren (8), Sun (9)
3. Molecular Structure (25 pts)
   - Crick (25)
4. Generative Adversarial Nets (25 pts)
   - Pouget-Abadie (12), Mirza (13)

Pass threshold: 50 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_add_missing_coauthors(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    papers = result.get("papers", {})
    score = 0
    feedback_parts = []
    
    # Helper to check if a specific last name exists in author list
    def has_author(author_list, target_last_name):
        target = target_last_name.lower()
        for auth in author_list:
            # Handle potential None values in DB (though unlikely for these fields)
            lname = (auth.get("lastName") or "").lower()
            if target in lname:
                return True
        return False

    # --- Paper 1: Attention Is All You Need ---
    p1 = papers.get("Attention Is All You Need", {})
    if p1.get("found"):
        authors = p1.get("authors", [])
        p1_score = 0
        if has_author(authors, "Shazeer"): p1_score += 8
        if has_author(authors, "Parmar"): p1_score += 8
        if has_author(authors, "Uszkoreit"): p1_score += 9
        score += p1_score
        if p1_score > 0:
            feedback_parts.append(f"Attention paper: +{p1_score}pts")
    else:
        feedback_parts.append("Attention paper not found")

    # --- Paper 2: Deep Residual Learning ---
    p2 = papers.get("Deep Residual Learning for Image Recognition", {})
    if p2.get("found"):
        authors = p2.get("authors", [])
        p2_score = 0
        if has_author(authors, "Zhang"): p2_score += 8
        if has_author(authors, "Ren"): p2_score += 8
        if has_author(authors, "Sun"): p2_score += 9
        score += p2_score
        if p2_score > 0:
            feedback_parts.append(f"ResNet paper: +{p2_score}pts")
    else:
        feedback_parts.append("ResNet paper not found")

    # --- Paper 3: Molecular Structure (DNA) ---
    p3 = papers.get("Molecular Structure of Nucleic Acids", {})
    if p3.get("found"):
        authors = p3.get("authors", [])
        if has_author(authors, "Crick"):
            score += 25
            feedback_parts.append("DNA paper: +25pts")
    else:
        feedback_parts.append("DNA paper not found")

    # --- Paper 4: GANs ---
    p4 = papers.get("Generative Adversarial Nets", {})
    if p4.get("found"):
        authors = p4.get("authors", [])
        p4_score = 0
        if has_author(authors, "Pouget-Abadie"): p4_score += 12
        if has_author(authors, "Mirza"): p4_score += 13
        score += p4_score
        if p4_score > 0:
            feedback_parts.append(f"GANs paper: +{p4_score}pts")
    else:
        feedback_parts.append("GANs paper not found")

    passed = score >= 50

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }