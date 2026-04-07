#!/usr/bin/env python3
"""
Verifier for fix_inverted_names task.

Checks:
1. Are the names corrected in the search index (IndexNomPrenom)?
2. Are the names corrected in the patient file (fchpat)?
3. Are the original GUIDs preserved (proving Update vs Delete+Insert)?
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_inverted_names(traj, env_info, task_info):
    """
    Verify that patient names were swapped correctly using SQL updates.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata contains expected values
    metadata = task_info.get('metadata', {})
    targets = metadata.get('target_records', [])

    # Load result from container
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

    score = 0
    feedback_parts = []
    
    # Check duplicates (Agent created new records instead of updating)
    duplicates = result.get('duplicates_found', 0)
    if duplicates > 0:
        feedback_parts.append(f"WARNING: Found {duplicates} duplicate records (did you insert new ones instead of updating?)")
        # Penalty for creating mess
        score -= 10

    # Helper to check a single record
    def check_record(rec_key, expected_nom, expected_prenom):
        r_data = result.get(rec_key, {})
        index_val = r_data.get('index_val', '').strip()
        fchpat_val = r_data.get('fchpat_val', '').strip()
        
        # Parse Index Value (output is "Nom\tPrenom")
        actual_nom = ""
        actual_prenom = ""
        if index_val and '\t' in index_val:
            parts = index_val.split('\t')
            if len(parts) >= 2:
                actual_nom = parts[0]
                actual_prenom = parts[1]
        
        # Check Index correctness (Major points: 25 pts)
        index_ok = (actual_nom == expected_nom and actual_prenom == expected_prenom)
        
        # Check fchpat correctness (Consistency points: ~5 pts)
        # fchpat_val is just the NomFille
        fchpat_ok = (fchpat_val == expected_nom)
        
        # Check if record exists at all with this GUID (GUID Preservation: ~3 pts)
        guid_preserved = (index_val != "")
        
        return index_ok, fchpat_ok, guid_preserved

    # Verify Record 1: MARTIN Sophie
    r1_idx, r1_pat, r1_guid = check_record('record1', 'MARTIN', 'Sophie')
    if r1_idx:
        score += 25
        feedback_parts.append("MARTIN Sophie: Index Correct")
    else:
        feedback_parts.append("MARTIN Sophie: Index Incorrect")
        
    if r1_pat:
        score += 5
    if r1_guid:
        score += 3  # Points just for keeping the GUID alive

    # Verify Record 2: PETIT Thomas
    r2_idx, r2_pat, r2_guid = check_record('record2', 'PETIT', 'Thomas')
    if r2_idx:
        score += 25
        feedback_parts.append("PETIT Thomas: Index Correct")
    else:
        feedback_parts.append("PETIT Thomas: Index Incorrect")

    if r2_pat:
        score += 5
    if r2_guid:
        score += 3

    # Verify Record 3: DUBOIS Lucas
    r3_idx, r3_pat, r3_guid = check_record('record3', 'DUBOIS', 'Lucas')
    if r3_idx:
        score += 25
        feedback_parts.append("DUBOIS Lucas: Index Correct")
    else:
        feedback_parts.append("DUBOIS Lucas: Index Incorrect")

    if r3_pat:
        score += 5
    if r3_guid:
        score += 4 # Extra point to round up to 100 total

    # Total Score Calculation:
    # 3 records * 25 (Index) = 75
    # 3 records * 5 (fchpat) = 15
    # 3 records * ~3 (GUID) = 10
    # Total = 100

    passed = (score >= 75) # Must at least fix the index for all 3

    return {
        "passed": passed,
        "score": max(0, score), # No negative scores
        "feedback": " | ".join(feedback_parts)
    }