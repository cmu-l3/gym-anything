#!/usr/bin/env python3
"""
Verifier for Document Drug Allergy task in OpenEMR

Verifies that a Penicillin allergy was properly documented for patient Maria Maggio (pid=5)
with reaction (hives) and severity (moderate) information.

Uses copy_from_env to read pre-exported verification data from the container.

Scoring (100 points total):
- Allergy record exists for correct patient: 30 points
- Correct allergen name (Penicillin): 25 points
- Reaction documented (hives/rash): 15 points
- Severity documented (moderate): 15 points
- Record created during task (anti-gaming): 10 points
- VLM trajectory verification: 5 points

Pass threshold: 70 points with allergy_exists AND correct_allergen met
"""

import sys
import os
import json
import logging
import tempfile
import re
from typing import Dict, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_document_drug_allergy(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Verify that the Penicillin allergy was correctly documented.
    
    Uses multiple independent signals to prevent gaming:
    1. Database record exists with correct allergen
    2. Reaction and severity fields populated
    3. Timestamp verification (created during task)
    4. Count comparison (allergy count increased)
    5. VLM trajectory verification (optional)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Copy function not available"
        }

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 5)
    expected_allergen = metadata.get('allergen_name', 'Penicillin').lower()
    expected_reaction = metadata.get('expected_reaction', 'hives').lower()
    expected_severity = metadata.get('expected_severity', 'moderate').lower()
    
    # Score weights from metadata
    score_allergy_exists = metadata.get('score_allergy_exists', 30)
    score_correct_allergen = metadata.get('score_correct_allergen', 25)
    score_reaction = metadata.get('score_reaction_documented', 15)
    score_severity = metadata.get('score_severity_documented', 15)
    score_timestamp = metadata.get('score_timestamp_valid', 10)
    score_vlm = metadata.get('score_vlm_verification', 5)

    # Initialize results
    score = 0
    feedback_parts = []
    subscores = {
        "allergy_exists": False,
        "correct_allergen": False,
        "correct_patient": False,
        "reaction_documented": False,
        "severity_documented": False,
        "created_during_task": False,
        "new_allergy_added": False,
        "vlm_verified": False
    }

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/document_allergy_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export_result.sh may have failed",
            "subscores": subscores
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result file: {e}",
            "subscores": subscores
        }
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Error reading result: {e}",
            "subscores": subscores
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Extract data from result
    patient_pid = result.get('patient_pid', 0)
    initial_count = result.get('initial_allergy_count', 0)
    current_count = result.get('current_allergy_count', 0)
    allergy_found = result.get('allergy_found', False)
    new_allergy_added = result.get('new_allergy_added', False)
    created_during_task = result.get('created_during_task', False)
    was_pre_existing = result.get('was_pre_existing', False)
    allergy = result.get('allergy', {})
    task_start = result.get('task_start_timestamp', 0)

    logger.info(f"Result data: pid={patient_pid}, initial={initial_count}, current={current_count}")
    logger.info(f"Allergy found={allergy_found}, new_added={new_allergy_added}, during_task={created_during_task}")
    logger.info(f"Allergy data: {allergy}")

    # ================================================================
    # CRITERION 1: Correct patient (prerequisite check)
    # ================================================================
    if patient_pid != expected_pid:
        feedback_parts.append(f"CRITICAL: Wrong patient ID (expected {expected_pid}, got {patient_pid})")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }
    subscores["correct_patient"] = True

    # ================================================================
    # CRITERION 2: Allergy record exists (30 points)
    # ================================================================
    if allergy_found:
        score += score_allergy_exists
        subscores["allergy_exists"] = True
        feedback_parts.append(f"Allergy record found (id={allergy.get('id', 'N/A')})")
    else:
        feedback_parts.append("No Penicillin allergy record found in database")
        
        # Check if any new allergies were added at all
        if current_count > initial_count:
            feedback_parts.append(f"Note: {current_count - initial_count} new allergy record(s) added, but not Penicillin")
        else:
            feedback_parts.append("No new allergies were added")
        
        # Early return - no allergy found
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    # ================================================================
    # CRITERION 3: Correct allergen name (25 points)
    # ================================================================
    allergy_title = allergy.get('title', '').lower().strip()
    
    # Check for Penicillin or common variants
    penicillin_variants = ['penicillin', 'pcn', 'pen', 'penicillins']
    allergen_match = any(variant in allergy_title for variant in penicillin_variants)
    
    if allergen_match:
        score += score_correct_allergen
        subscores["correct_allergen"] = True
        feedback_parts.append(f"Correct allergen: '{allergy.get('title', '')}'")
    else:
        feedback_parts.append(f"Wrong allergen name: expected 'Penicillin', got '{allergy.get('title', '')}'")

    # ================================================================
    # CRITERION 4: Reaction documented (15 points)
    # ================================================================
    allergy_reaction = allergy.get('reaction', '').lower().strip()
    
    # Accept various terms for hives/rash
    reaction_terms = ['hive', 'hives', 'rash', 'urticaria', 'skin', 'dermatitis', 'itching', 'itchy']
    reaction_match = any(term in allergy_reaction for term in reaction_terms)
    
    if reaction_match:
        score += score_reaction
        subscores["reaction_documented"] = True
        feedback_parts.append(f"Reaction documented: '{allergy.get('reaction', '')}'")
    elif allergy_reaction:
        # Partial credit for any reaction documented
        score += score_reaction // 2
        subscores["reaction_documented"] = "partial"
        feedback_parts.append(f"Reaction documented (not hives): '{allergy.get('reaction', '')}'")
    else:
        feedback_parts.append("No reaction documented")

    # ================================================================
    # CRITERION 5: Severity documented (15 points)
    # ================================================================
    allergy_severity = allergy.get('severity', '').lower().strip()
    
    # Accept moderate or similar terms
    severity_terms = ['moderate', 'mod', 'medium', 'significant']
    severity_match = any(term in allergy_severity for term in severity_terms)
    
    if severity_match:
        score += score_severity
        subscores["severity_documented"] = True
        feedback_parts.append(f"Correct severity: '{allergy.get('severity', '')}'")
    elif allergy_severity:
        # Partial credit for any severity documented
        score += score_severity // 2
        subscores["severity_documented"] = "partial"
        feedback_parts.append(f"Severity documented (not moderate): '{allergy.get('severity', '')}'")
    else:
        feedback_parts.append("No severity documented")

    # ================================================================
    # CRITERION 6: Created during task (10 points) - anti-gaming
    # ================================================================
    if created_during_task:
        score += score_timestamp
        subscores["created_during_task"] = True
        feedback_parts.append("Record created during task execution")
    elif was_pre_existing:
        feedback_parts.append("WARNING: Allergy may have existed before task started")
    else:
        # Check via count comparison
        if new_allergy_added:
            score += score_timestamp // 2
            subscores["new_allergy_added"] = True
            feedback_parts.append("New allergy added (count increased)")
        else:
            feedback_parts.append("Could not verify record was created during task")

    # ================================================================
    # CRITERION 7: VLM trajectory verification (5 points)
    # ================================================================
    # Note: In full implementation, would use trajectory frames
    # For now, give benefit of doubt if database checks passed
    vlm_verified = False
    try:
        # Check if we have trajectory data
        if traj and len(traj) > 0:
            # Basic check: trajectory exists with multiple frames
            if len(traj) >= 3:
                vlm_verified = True
                score += score_vlm
                subscores["vlm_verified"] = True
                feedback_parts.append("Trajectory captured")
    except Exception as e:
        logger.warning(f"VLM verification skipped: {e}")

    # ================================================================
    # FINAL SCORING
    # ================================================================
    max_score = (score_allergy_exists + score_correct_allergen + 
                 score_reaction + score_severity + score_timestamp + score_vlm)
    
    # Pass requires: allergy exists AND correct allergen AND score >= 70%
    key_criteria_met = subscores["allergy_exists"] and subscores["correct_allergen"]
    passed = key_criteria_met and score >= 70

    # Calculate percentage
    score_percent = (score / max_score) * 100 if max_score > 0 else 0

    return {
        "passed": passed,
        "score": score,
        "max_score": max_score,
        "score_percent": round(score_percent, 1),
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "patient_pid": patient_pid,
            "allergy_title": allergy.get('title', ''),
            "allergy_reaction": allergy.get('reaction', ''),
            "allergy_severity": allergy.get('severity', ''),
            "initial_allergy_count": initial_count,
            "final_allergy_count": current_count,
            "key_criteria_met": key_criteria_met
        }
    }


# For standalone testing
if __name__ == "__main__":
    # Mock test
    print("Document Drug Allergy Verifier")
    print("This verifier checks for:")
    print("  - Penicillin allergy record in lists table")
    print("  - Patient pid = 5 (Maria Maggio)")
    print("  - Reaction field populated (preferably 'hives')")
    print("  - Severity field populated (preferably 'moderate')")
    print("  - Record created during task execution")
    print()
    print("Pass threshold: 70 points with allergy_exists AND correct_allergen")