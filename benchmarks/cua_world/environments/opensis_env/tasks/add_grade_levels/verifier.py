#!/usr/bin/env python3
"""
Verifier for add_grade_levels task.

Goal: Add Grade 7 and Grade 8 to OpenSIS with correct sort order.

Scoring Criteria:
1. Grade 7 exists in database (25 pts)
2. Grade 8 exists in database (25 pts)
3. Total grade levels = 6 (15 pts)
4. Sort order is correct (7 < 8 < 9) (15 pts)
5. Metadata Correctness (Titles match) (10 pts)
6. Anti-gaming (New records created) (10 pts)
"""

import json
import logging
import os
import tempfile
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_grade_levels(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "CRITICAL: Copy function not available"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    db_results = data.get("db_results", {})
    if not db_results.get("success"):
        return {"passed": False, "score": 0, "feedback": f"Database query failed in environment: {db_results.get('error')}"}

    all_grades = db_results.get("all_grades", [])
    new_grades = db_results.get("new_grades", [])
    final_count = db_results.get("total_count", 0)
    initial_count = int(data.get("initial_grade_count", 0))
    
    score = 0
    feedback = []

    # Helper to find grade by short name
    def find_grade(name_list):
        for g in new_grades:
            if g['short_name'] in name_list:
                return g
        return None

    # Criterion 1: Grade 7 Exists (25 pts)
    g7 = find_grade(['7', '07'])
    if g7:
        score += 25
        feedback.append("Grade 7 found.")
    else:
        feedback.append("Grade 7 NOT found.")

    # Criterion 2: Grade 8 Exists (25 pts)
    g8 = find_grade(['8', '08'])
    if g8:
        score += 25
        feedback.append("Grade 8 found.")
    else:
        feedback.append("Grade 8 NOT found.")

    # Criterion 3: Total Count (15 pts)
    # Expecting 6 (9, 10, 11, 12 existing + 7, 8 new)
    if final_count == 6:
        score += 15
        feedback.append("Total grade count is correct (6).")
    else:
        feedback.append(f"Total grade count is {final_count} (expected 6).")

    # Criterion 4: Sort Order (15 pts)
    # We need to verify 7 comes before 8, and 8 comes before 9
    # Build a map of short_name -> sort_order
    sort_map = {str(g['short_name']): int(g['sort_order']) for g in all_grades}
    
    s7 = sort_map.get('7') or sort_map.get('07')
    s8 = sort_map.get('8') or sort_map.get('08')
    s9 = sort_map.get('9') or sort_map.get('09')

    if s7 is not None and s8 is not None and s9 is not None:
        if s7 < s8 and s8 < s9:
            score += 15
            feedback.append("Sort order is correct (7 < 8 < 9).")
        else:
            feedback.append(f"Sort order incorrect: 7={s7}, 8={s8}, 9={s9}.")
    elif s7 is not None and s8 is not None:
        # Partial credit if 9 is missing (unlikely) but 7 < 8
        if s7 < s8:
            score += 10
            feedback.append("Sort order 7 < 8 correct (Grade 9 missing?).")
        else:
            feedback.append("Sort order 7 >= 8.")
    else:
        feedback.append("Cannot verify sort order (missing grades).")

    # Criterion 5: Metadata (Titles) (10 pts)
    # 5 pts for each correct title
    if g7 and ("Grade 7" in g7['title'] or "Seventh" in g7['title']):
        score += 5
    elif g7:
        feedback.append(f"Grade 7 title mismatch: '{g7['title']}'")
        
    if g8 and ("Grade 8" in g8['title'] or "Eighth" in g8['title']):
        score += 5
    elif g8:
        feedback.append(f"Grade 8 title mismatch: '{g8['title']}'")

    # Criterion 6: Anti-Gaming (10 pts)
    # Verify we actually added records (count increased by 2)
    if (final_count - initial_count) == 2:
        score += 10
        feedback.append("Anti-gaming passed: Exactly 2 new records detected.")
    elif (final_count - initial_count) > 0:
        score += 5
        feedback.append("Anti-gaming partial: Count increased, but not by exactly 2.")
    else:
        feedback.append("Anti-gaming failed: No net increase in records.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }