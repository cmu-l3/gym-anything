#!/usr/bin/env python3
"""
Verifier for organize_subcollection_hierarchy task.

Checks:
1. "Constitutional Law Seminar" collection exists (10 pts)
2. Subcollections "First Amendment", "Due Process", "Judicial Review" exist (15 pts)
3. Hierarchy is correct (subcollections are children of parent) (6 pts)
4. Specific items are assigned to correct subcollections (63 pts)
5. No misassigned items (6 pts)

Total: 100 points
Pass threshold: 65 points
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_organize_subcollection_hierarchy(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load result JSON
    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp.close()
        try:
            copy_from_env("/tmp/task_result.json", temp.name)
            with open(temp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp.name):
                os.unlink(temp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"DB Error: {result['error']}"}

    score = 0
    feedback = []
    
    collections = result.get("collections", [])
    assignments = result.get("assignments", {}) # Dict[CollectionName, List[Titles]]
    
    # Metadata expectations
    PARENT_NAME = "Constitutional Law Seminar"
    SUBS = ["First Amendment", "Due Process", "Judicial Review"]
    
    # Check 1: Parent Collection Exists (10 pts)
    parent_coll = next((c for c in collections if c['name'] == PARENT_NAME), None)
    if parent_coll:
        score += 10
        feedback.append(f"Parent '{PARENT_NAME}' created (+10)")
    else:
        feedback.append(f"Parent '{PARENT_NAME}' NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Check 2 & 3: Subcollections Exist and are Children (15 + 6 pts)
    subs_found = 0
    hierarchy_correct = 0
    
    for sub_name in SUBS:
        sub_coll = next((c for c in collections if c['name'] == sub_name), None)
        if sub_coll:
            subs_found += 1
            # Check parent ID
            if sub_coll.get('parent_id') == parent_coll['id']:
                hierarchy_correct += 1
            else:
                feedback.append(f"'{sub_name}' exists but is not inside '{PARENT_NAME}'")
        else:
            feedback.append(f"Subcollection '{sub_name}' NOT found")
            
    score += (subs_found * 5) # Max 15
    if subs_found > 0:
        feedback.append(f"{subs_found}/3 subcollections found (+{subs_found*5})")
        
    score += (hierarchy_correct * 2) # Max 6
    if hierarchy_correct == 3:
        feedback.append("Hierarchy structure correct (+6)")
        
    # Check 4: Item Assignments (Total 63 pts)
    # Define partial matching helpers (Title in DB might be full string, we look for substrings)
    
    def check_items(collection_name, expected_substrings, points_per_item):
        actual_items = assignments.get(collection_name, [])
        local_score = 0
        found_count = 0
        
        for expected in expected_substrings:
            # Check if any actual item contains the expected substring
            match = any(expected.lower() in actual.lower() for actual in actual_items)
            if match:
                local_score += points_per_item
                found_count += 1
        
        return local_score, found_count, len(expected_substrings)

    # First Amendment (15 pts total -> 7.5 per item)
    s1, c1, t1 = check_items("First Amendment", 
                             ["New York Times", "Tinker"], 
                             7.5)
    score += s1
    feedback.append(f"First Amendment: {c1}/{t1} items (+{s1})")

    # Due Process (30 pts total -> 6 per item)
    s2, c2, t2 = check_items("Due Process", 
                             ["Brown v. Board", "Miranda", "Gideon", "Obergefell", "Due Process Clause and the Substantive"], 
                             6)
    score += s2
    feedback.append(f"Due Process: {c2}/{t2} items (+{s2})")

    # Judicial Review (18 pts total -> 6 per item)
    s3, c3, t3 = check_items("Judicial Review", 
                             ["Marbury", "Path of the Law", "Constitutional Fact Review"], 
                             6)
    score += s3
    feedback.append(f"Judicial Review: {c3}/{t3} items (+{s3})")
    
    # Check 5: Misassigned Items (6 pts)
    # Check if items are in wrong collections (simple check)
    misassigned = False
    
    # Check First Amendment doesn't have Due Process items
    if any("brown" in i.lower() for i in assignments.get("First Amendment", [])): misassigned = True
    # Check Judicial Review doesn't have First Amendment items
    if any("tinker" in i.lower() for i in assignments.get("Judicial Review", [])): misassigned = True
    
    if not misassigned:
        score += 6
        feedback.append("No obvious misassignments (+6)")
    else:
        feedback.append("Some items appear misassigned")

    passed = score >= 65
    
    return {
        "passed": passed,
        "score": min(round(score), 100),
        "feedback": " | ".join(feedback),
        "details": result
    }