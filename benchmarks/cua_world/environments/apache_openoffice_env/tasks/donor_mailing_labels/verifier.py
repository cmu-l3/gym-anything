#!/usr/bin/env python3
"""
Verifier for donor_mailing_labels task.

Goal: Create labels for donors with TotalDonation >= 1000.
Input: CSV with ~50 donors.
Output: ODT file with merged labels.

Verification Logic:
1. Reconstruct expected list of donors (TotalDonation >= 1000) from the exported CSV data.
2. Check if output file exists and is a valid ODT.
3. Search for expected names in the ODT text content (Recall).
4. Search for unexpected names (TotalDonation < 1000) in the ODT text content (Precision).
5. Verify basic formatting content (City/State/Zip presence).
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_donor_mailing_labels(traj, env_info, task_info):
    """Verify donor labels creation and filtering."""
    
    # 1. Setup and retrieve data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Gate Checks
    if not result.get("file_exists"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file 'golden_circle_labels.odt' was not found."
        }
    
    if not result.get("is_valid_odt"):
        return {
            "passed": False, 
            "score": 5, 
            "feedback": "Output file exists but does not appear to be a valid ODT document."
        }

    # 3. Logic Verification
    csv_data = result.get("csv_source_data", [])
    odt_text = result.get("odt_text_content", "")
    
    # Reconstruct Ground Truth
    expected_donors = [] # >= 1000
    unexpected_donors = [] # < 1000
    
    threshold = task_info.get('metadata', {}).get('threshold', 1000)

    for row in csv_data:
        try:
            amount = int(row.get("TotalDonation", 0))
            # Construct full name for searching
            full_name = f"{row.get('FirstName', '')} {row.get('LastName', '')}"
            
            if amount >= threshold:
                expected_donors.append(full_name)
            else:
                unexpected_donors.append(full_name)
        except ValueError:
            continue

    total_expected = len(expected_donors)
    total_unexpected = len(unexpected_donors)
    
    if total_expected == 0:
        return {"passed": False, "score": 0, "feedback": "Error in verification data: No expected donors found in CSV."}

    # Calculate Recall (Did we find the high value donors?)
    found_expected = 0
    missing_expected = []
    for name in expected_donors:
        if name in odt_text:
            found_expected += 1
        else:
            if len(missing_expected) < 3: missing_expected.append(name)

    recall_score = (found_expected / total_expected) * 40 # Max 40 points for recall

    # Calculate Precision (Did we exclude the low value donors?)
    found_unexpected = 0
    found_unexpected_examples = []
    for name in unexpected_donors:
        if name in odt_text:
            found_unexpected += 1
            if len(found_unexpected_examples) < 3: found_unexpected_examples.append(name)

    # Penalty logic: 
    # If found_unexpected == 0, full 40 points.
    # If found_unexpected == total_unexpected (agent dumped everyone), 0 points.
    # Linear scale in between.
    precision_score = 0
    if total_unexpected > 0:
        precision_ratio = 1.0 - (found_unexpected / total_unexpected)
        precision_score = precision_ratio * 40
    else:
        precision_score = 40 # Should not happen with generated data

    # Formatting checks (10 points)
    formatting_score = 0
    # Check for basic address components
    common_address_terms = [" St", " Ave", " Rd", " Ln", " Blvd", " Dr"]
    if any(term in odt_text for term in common_address_terms):
        formatting_score += 5
    
    # Check if created during task (anti-gaming) (10 points)
    # If file exists and valid but old, 0 here. If created now, 10.
    creation_score = 10 if result.get("created_during_task") else 0

    total_score = recall_score + precision_score + formatting_score + creation_score
    
    # Feedback generation
    feedback = f"Score: {int(total_score)}/100. "
    feedback += f"Found {found_expected}/{total_expected} high-value donors. "
    if found_unexpected > 0:
        feedback += f"Incorrectly included {found_unexpected} low-value donors (e.g., {', '.join(found_unexpected_examples)}). "
    else:
        feedback += "Correctly excluded all low-value donors. "
        
    if creation_score == 0:
        feedback += "Warning: File timestamp indicates it was not created during this task session. "

    passed = total_score >= 75

    return {
        "passed": passed,
        "score": int(total_score),
        "feedback": feedback,
        "details": {
            "found_expected": found_expected,
            "total_expected": total_expected,
            "found_unexpected": found_unexpected,
            "total_unexpected": total_unexpected
        }
    }