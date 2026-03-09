#!/usr/bin/env python3
"""
Verifier for Animal Classification Chart task.

Criteria:
1. File exists, is valid, and created during task (15 pts)
2. Page count is exactly 3 (10 pts)
3. Title "Animal Classification" present (10 pts)
4. Main groups "Vertebrates" and "Invertebrates" present (10 pts)
5. Vertebrate subcategories (>=4 of 5) present (15 pts)
6. Invertebrate subcategories (>=2 of 3) present (10 pts)
7. Tree diagram structure (>=8 shapes found) (15 pts)
8. Sorting activity title "Sort" present (5 pts)
9. Animal names (>=6 of 10) present (10 pts)

Pass Threshold: 70/100
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_animal_classification_chart(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No copy_from_env function available"
        }

    # Load result JSON
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_path = tmp.name
        tmp.close()
        try:
            copy_from_env('/tmp/task_result.json', tmp_path)
            with open(tmp_path, 'r', encoding='utf-8-sig') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read export result: {e}"
        }

    score = 0
    feedback_parts = []
    
    # 1. File Existence & Validity (15 pts)
    if not result.get('file_found'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "File not found: animal_classification.flipchart was not created"
        }
    
    if result.get('file_valid') and result.get('created_during_task'):
        score += 15
        feedback_parts.append("Valid file created during task (+15)")
    else:
        feedback_parts.append("File exists but is invalid or pre-dates task start")
        # Proceed with checks but score will likely be low

    # 2. Page Count (10 pts)
    page_count = result.get('page_count', 0)
    if page_count == 3:
        score += 10
        feedback_parts.append("Page count is 3 (+10)")
    else:
        feedback_parts.append(f"Page count is {page_count}, expected 3")

    # Prepare text for case-insensitive searching
    all_text = result.get('extracted_text', "").lower()

    # 3. Title Check (10 pts)
    if "animal classification" in all_text:
        score += 10
        feedback_parts.append("Title found (+10)")
    else:
        feedback_parts.append("Title 'Animal Classification' missing")

    # 4. Main Groups (10 pts)
    groups_found = 0
    if "vertebrate" in all_text: groups_found += 1
    if "invertebrate" in all_text: groups_found += 1
    
    if groups_found == 2:
        score += 10
        feedback_parts.append("Both main groups found (+10)")
    elif groups_found == 1:
        score += 5
        feedback_parts.append("One main group missing (+5)")
    else:
        feedback_parts.append("Main groups (Vertebrates/Invertebrates) missing")

    # 5. Vertebrate Subcategories (15 pts)
    vert_cats = ["fish", "amphibian", "reptile", "bird", "mammal"]
    vert_found = sum(1 for cat in vert_cats if cat in all_text)
    
    if vert_found >= 4:
        score += 15
        feedback_parts.append(f"Vertebrate subcategories found: {vert_found}/5 (+15)")
    elif vert_found >= 2:
        score += 7
        feedback_parts.append(f"Vertebrate subcategories found: {vert_found}/5 (+7)")
    else:
        feedback_parts.append(f"Insufficient vertebrate subcategories: {vert_found}")

    # 6. Invertebrate Subcategories (10 pts)
    invert_cats = ["insect", "arachnid", "mollusk"]
    invert_found = sum(1 for cat in invert_cats if cat in all_text)

    if invert_found >= 2:
        score += 10
        feedback_parts.append(f"Invertebrate subcategories found: {invert_found}/3 (+10)")
    elif invert_found == 1:
        score += 5
        feedback_parts.append(f"Invertebrate subcategories found: {invert_found}/3 (+5)")
    else:
        feedback_parts.append(f"Insufficient invertebrate subcategories: {invert_found}")

    # 7. Shape Count / Tree Diagram (15 pts)
    shape_count = result.get('shape_count', 0)
    if shape_count >= 8:
        score += 15
        feedback_parts.append(f"Tree diagram shapes found: {shape_count} (+15)")
    elif shape_count >= 4:
        score += 7
        feedback_parts.append(f"Tree diagram shapes found: {shape_count} (+7)")
    else:
        feedback_parts.append(f"Tree diagram shapes missing or too few: {shape_count}")

    # 8. Sort Activity Title (5 pts)
    if "sort" in all_text:
        score += 5
        feedback_parts.append("'Sort' activity title found (+5)")
    else:
        feedback_parts.append("'Sort' activity title missing")

    # 9. Animal Names (10 pts)
    animals = ["eagle", "salmon", "frog", "spider", "snail", "cobra", "butterfly", "dolphin", "beetle", "turtle"]
    animals_found = sum(1 for a in animals if a in all_text)
    
    if animals_found >= 6:
        score += 10
        feedback_parts.append(f"Animals for sorting found: {animals_found} (+10)")
    elif animals_found >= 3:
        score += 5
        feedback_parts.append(f"Animals for sorting found: {animals_found} (+5)")
    else:
        feedback_parts.append(f"Insufficient animals found: {animals_found}")

    # Final Result
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }