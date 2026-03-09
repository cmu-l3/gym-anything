#!/usr/bin/env python3
"""
Verifier for tag_short_papers task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tag_short_papers(traj, env_info, task_info):
    """
    Verify that correct papers are tagged 'short-read'.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    # Ground Truths
    # Dijkstra (3 pages), Watson/Crick (2 pages), Huffman (4 pages)
    TARGET_TITLES_PARTIAL = [
        "A Note on Two Problems in Connexion with Graphs",
        "Molecular Structure of Nucleic Acids",
        "A Method for the Construction of Minimum-Redundancy Codes"
    ]
    
    # Distractors (> 5 pages)
    # AlphaGo (6 pages), ImageNet (9 pages), Einstein (31 pages)
    
    tagged_items = result.get("tagged_items", [])
    tagged_titles = [item["title"] for item in tagged_items]
    
    score = 0
    feedback = []
    
    # 1. Check for correct papers (30 pts each)
    correct_count = 0
    for target in TARGET_TITLES_PARTIAL:
        # Fuzzy match title
        found = False
        for title in tagged_titles:
            if target in title:
                found = True
                break
        
        if found:
            score += 30
            correct_count += 1
            feedback.append(f"Correctly tagged: '{target}'")
        else:
            feedback.append(f"Missed: '{target}'")
            
    # 2. Check for False Positives (10 pts)
    # Any tagged title that DOES NOT match one of the targets is a false positive
    false_positives = []
    for title in tagged_titles:
        is_target = False
        for target in TARGET_TITLES_PARTIAL:
            if target in title:
                is_target = True
                break
        if not is_target:
            false_positives.append(title)
            
    if len(false_positives) == 0:
        score += 10
        feedback.append("No false positives (Good)")
    else:
        feedback.append(f"False positives detected: {len(false_positives)} items (e.g., '{false_positives[0]}')")

    # Anti-gaming: Ensure tag actually exists
    if not result.get("tag_exists"):
        score = 0
        feedback = ["Tag 'short-read' was not created."]

    passed = (score >= 90) # Requires all 3 correct + no false positives
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }