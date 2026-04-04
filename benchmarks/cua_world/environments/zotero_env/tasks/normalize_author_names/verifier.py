#!/usr/bin/env python3
"""
Verifier for normalize_author_names task.
"""

import json
import tempfile
import os

def verify_normalize_author_names(traj, env_info, task_info):
    """
    Verify that author names have been normalized to canonical forms.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    papers = result.get("papers", {})
    
    # helper to check exact match
    def check_paper(key, expected_first, expected_last, paper_name):
        authors = papers.get(key, [])
        if not authors:
            return 0, f"{paper_name}: Author not found"
        
        # Check if ANY of the authors match (in case of duplicates, though unlikely)
        for auth in authors:
            # normalize whitespace
            act_first = (auth.get("first") or "").strip()
            act_last = (auth.get("last") or "").strip()
            
            if act_first == expected_first and act_last == expected_last:
                return 20, f"{paper_name}: Correct ({act_first} {act_last})"
        
        # If we get here, no match found
        actual_str = ", ".join([f"{a.get('first')} {a.get('last')}" for a in authors])
        return 0, f"{paper_name}: Incorrect ({actual_str} vs {expected_first} {expected_last})"

    # 1. Alan Turing (2 papers)
    s1, f1 = check_paper("turing_1", "Alan M.", "Turing", "Computable Numbers")
    score += s1
    feedback_parts.append(f1)

    s2, f2 = check_paper("turing_2", "Alan M.", "Turing", "Computing Machinery")
    score += s2
    feedback_parts.append(f2)

    # 2. Claude Shannon (2 papers)
    s3, f3 = check_paper("shannon_1", "Claude E.", "Shannon", "Mathematical Theory (A)")
    score += s3
    feedback_parts.append(f3)

    s4, f4 = check_paper("shannon_2", "Claude E.", "Shannon", "Mathematical Theory (The)")
    score += s4
    feedback_parts.append(f4)

    # 3. Geoffrey Hinton (1 paper)
    s5, f5 = check_paper("hinton_1", "Geoffrey E.", "Hinton", "ImageNet")
    score += s5
    feedback_parts.append(f5)

    # Anti-gaming: Check if creator count dropped suspiciously
    # A drop suggests they might have deleted authors instead of editing, 
    # though merging might also cause a drop. We'll implement a soft warning/penalty if it's 0.
    total_creators = result.get("total_creators", 0)
    if total_creators == 0:
        score = 0
        feedback_parts.append("CRITICAL: All creators deleted?")

    passed = score >= 60  # Require at least 3/5 correct

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }