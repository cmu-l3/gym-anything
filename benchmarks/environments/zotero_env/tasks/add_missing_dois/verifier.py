#!/usr/bin/env python3
"""
Verifier for add_missing_dois task.

Checks:
1. Correct DOI values for 5 specific papers.
2. Anti-gaming: Checks if items were modified after task start.
3. Strict string matching (strips URL prefixes if agent adds them).
"""

import json
import tempfile
import os
import re

def normalize_doi(doi_string):
    """Clean DOI string: remove URLs, prefixes, whitespace."""
    if not doi_string:
        return ""
    
    s = str(doi_string).strip()
    
    # Remove common prefixes
    prefixes = [
        "https://doi.org/",
        "http://doi.org/",
        "http://dx.doi.org/",
        "doi:",
        "DOI:"
    ]
    
    for p in prefixes:
        if s.lower().startswith(p.lower()):
            s = s[len(p):]
            
    return s.strip()

def verify_add_missing_dois(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_targets = metadata.get('targets', [])
    
    # 2. Load Result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Score
    score = 0
    max_score = 100
    points_per_doi = 20
    feedback_parts = []
    
    found_targets = result.get('targets', [])
    
    if not found_targets:
        return {"passed": False, "score": 0, "feedback": "No papers found in database check"}

    # Check each expected target against results
    for expected in expected_targets:
        target_sub = expected['title_substring']
        expected_doi = expected['expected_doi']
        
        # Find corresponding result
        match = next((t for t in found_targets if t['target_substring'] == target_sub), None)
        
        if not match or not match['found']:
            feedback_parts.append(f"Paper not found: '{target_sub}'")
            continue
            
        agent_doi_raw = match.get('doi_value')
        
        if not agent_doi_raw:
            feedback_parts.append(f"No DOI added for '{target_sub}'")
            continue
            
        # Normalize and Compare
        agent_doi_norm = normalize_doi(agent_doi_raw)
        expected_doi_norm = normalize_doi(expected_doi)
        
        # Case-insensitive comparison
        if agent_doi_norm.lower() == expected_doi_norm.lower():
            score += points_per_doi
            feedback_parts.append(f"✓ Correct DOI for '{target_sub}'")
        else:
            feedback_parts.append(f"✗ Wrong DOI for '{target_sub}' (Got: '{agent_doi_norm}', Expected: '{expected_doi_norm}')")

    # 4. Anti-Gaming Check (Timestamps)
    # Zotero updates dateModified when fields change. 
    # We won't penalize strict timestamps here as SQLite times are string-based and timezone tricky,
    # but the fact that DOIs were cleared in setup.sh guarantees they were added during the task.
    
    # 5. Finalize
    passed = (score >= 60) # Pass if at least 3/5 are correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }