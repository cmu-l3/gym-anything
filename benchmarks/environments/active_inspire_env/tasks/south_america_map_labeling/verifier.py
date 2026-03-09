#!/usr/bin/env python3
"""
Verifier for south_america_map_labeling task.

Criteria:
1. File exists & valid format (15 pts)
2. Page count == 3 (10 pts)
3. Title text "South America" present (10 pts)
4. Country labels (max 25 pts)
   - 5 of 6 required for base points (20 pts)
   - Bonus for all 6 (5 pts)
5. Pointers (lines/arrows) connecting labels (15 pts)
6. Map image embedded (15 pts)
7. Practice page text "Label the Map" (10 pts)
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_south_america_map(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Load result JSON
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            copy_from_env('/tmp/task_result.json', tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
            os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load verification results: {e}"}

    score = 0
    feedback = []

    # 1. File Existence & Validity (15 pts)
    if result.get('file_found') and result.get('file_valid'):
        score += 15
        feedback.append("Valid flipchart file found (+15)")
    else:
        feedback.append("File not found or invalid (0/15)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Page Count (10 pts)
    pc = result.get('page_count', 0)
    if pc == 3:
        score += 10
        feedback.append("Correct page count (+10)")
    else:
        feedback.append(f"Incorrect page count: {pc} (expected 3)")

    # 3. Title (10 pts)
    if result.get('has_title'):
        score += 10
        feedback.append("Title found (+10)")
    else:
        feedback.append("Missing title 'South America'")

    # 4. Countries (20 + 5 pts)
    countries = result.get('countries', {})
    found_count = sum(1 for v in countries.values() if v)
    if found_count >= 6:
        score += 25
        feedback.append("All 6 countries labeled (+25)")
    elif found_count >= 5:
        score += 20
        feedback.append(f"5 countries labeled (+20) - Missing: {[k for k,v in countries.items() if not v]}")
    elif found_count > 0:
        partial = int(found_count * 3) # ~3 pts per country
        score += partial
        feedback.append(f"Only {found_count} countries found (+{partial})")
    else:
        feedback.append("No country labels found")

    # 5. Pointers (15 pts)
    pointers = result.get('pointer_count', 0)
    if pointers >= 5:
        score += 15
        feedback.append(f"Found {pointers} pointer lines/arrows (+15)")
    elif pointers > 0:
        score += 5
        feedback.append(f"Few pointers found ({pointers}) (+5)")
    else:
        feedback.append("No pointer lines/arrows found")

    # 6. Map Image (15 pts)
    if result.get('has_image'):
        score += 15
        feedback.append("Map image embedded (+15)")
    else:
        feedback.append("No map image detected")

    # 7. Practice Page Text (10 pts)
    if result.get('has_label_map_text'):
        score += 10
        feedback.append("Practice page text found (+10)")
    else:
        feedback.append("Missing practice page title 'Label the Map'")

    # Pass threshold
    passed = score >= 60 and result.get('has_image') and found_count >= 4
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }