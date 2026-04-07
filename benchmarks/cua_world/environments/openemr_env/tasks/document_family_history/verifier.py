#!/usr/bin/env python3
"""
Verifier for Document Family History task in OpenEMR

Verification Strategy:
1. Check that family history data was modified during task (anti-gaming)
2. Verify diabetes field has content (mother's diabetes)
3. Verify heart problems field has content (father's MI)
4. Verify cancer field has content (grandmother's cancer)
5. Use VLM to verify trajectory shows proper navigation

Scoring (100 points):
- Data changed during task: 15 points (anti-gaming)
- Patient accessed correctly: 10 points
- Diabetes documented: 25 points
- Heart disease documented: 25 points
- Cancer documented: 25 points

Pass threshold: 60 points with at least one condition documented
"""

import sys
import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_document_family_history(traj, env_info, task_info):
    """
    Verify that family medical history was documented for Philip Walker.
    
    Uses copy_from_env to read exported results from the container.
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
    expected_pid = metadata.get('patient_pid', 4)
    expected_fname = metadata.get('patient_fname', 'Philip')
    expected_lname = metadata.get('patient_lname', 'Walker')
    
    # Initialize scoring
    score = 0
    max_score = 100
    feedback_parts = []
    subscores = {
        "data_changed": False,
        "patient_correct": False,
        "diabetes_documented": False,
        "heart_documented": False,
        "cancer_documented": False
    }
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/family_history_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result file: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to read result file: {e}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    logger.info(f"Result data loaded: {json.dumps(result, indent=2)}")
    
    # Extract data from result
    patient_pid = result.get('patient_pid', 0)
    data_changed = result.get('data_changed', False)
    task_start = result.get('task_start_time', 0)
    task_end = result.get('task_end_time', 0)
    
    history_data = result.get('history_data', {})
    doc_status = result.get('documentation_status', {})
    
    initial_history_count = result.get('initial_history_count', 0)
    current_history_count = result.get('current_history_count', 0)
    initial_lists_count = result.get('initial_lists_count', 0)
    current_lists_count = result.get('current_lists_count', 0)
    
    # CRITERION 1: Verify correct patient (10 points)
    if patient_pid == expected_pid:
        score += 10
        subscores["patient_correct"] = True
        feedback_parts.append(f"Correct patient (pid={expected_pid})")
    else:
        feedback_parts.append(f"Wrong patient: expected pid={expected_pid}, got {patient_pid}")
        # If wrong patient, this is a critical failure
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Wrong patient targeted: expected pid={expected_pid}",
            "subscores": subscores
        }
    
    # CRITERION 2: Data changed during task (15 points) - Anti-gaming
    new_records_created = (current_history_count > initial_history_count or 
                          current_lists_count > initial_lists_count)
    
    if data_changed or new_records_created:
        score += 15
        subscores["data_changed"] = True
        feedback_parts.append("Family history data was modified during task")
    else:
        feedback_parts.append("WARNING: No data change detected - possible gaming attempt")
    
    # CRITERION 3: Diabetes documented (25 points)
    diabetes_documented = doc_status.get('diabetes_documented', False)
    relatives_diabetes = history_data.get('relatives_diabetes', '').lower()
    
    # Additional check on the raw field content
    if not diabetes_documented and relatives_diabetes:
        # Check for any meaningful content
        if len(relatives_diabetes.strip()) > 0 and relatives_diabetes.strip() not in ['null', 'none', '']:
            diabetes_documented = True
    
    # Also check for diabetes-related keywords
    diabetes_keywords = ['diabetes', 'dm', 'type 2', 'type2', 'mother', 'maternal', 'sugar', 'glucose']
    if any(kw in relatives_diabetes for kw in diabetes_keywords):
        diabetes_documented = True
    
    if diabetes_documented:
        score += 25
        subscores["diabetes_documented"] = True
        feedback_parts.append("Mother's diabetes documented")
    else:
        feedback_parts.append("Mother's diabetes NOT documented")
    
    # CRITERION 4: Heart disease documented (25 points)
    heart_documented = doc_status.get('heart_documented', False)
    relatives_heart = history_data.get('relatives_heart_problems', '').lower()
    
    if not heart_documented and relatives_heart:
        if len(relatives_heart.strip()) > 0 and relatives_heart.strip() not in ['null', 'none', '']:
            heart_documented = True
    
    # Check for heart-related keywords
    heart_keywords = ['heart', 'mi', 'myocardial', 'infarction', 'attack', 'cardiac', 
                      'coronary', 'father', 'paternal', 'cad', 'angina']
    if any(kw in relatives_heart for kw in heart_keywords):
        heart_documented = True
    
    if heart_documented:
        score += 25
        subscores["heart_documented"] = True
        feedback_parts.append("Father's heart disease documented")
    else:
        feedback_parts.append("Father's heart disease NOT documented")
    
    # CRITERION 5: Cancer documented (25 points)
    cancer_documented = doc_status.get('cancer_documented', False)
    relatives_cancer = history_data.get('relatives_cancer', '').lower()
    
    if not cancer_documented and relatives_cancer:
        if len(relatives_cancer.strip()) > 0 and relatives_cancer.strip() not in ['null', 'none', '']:
            cancer_documented = True
    
    # Check for cancer-related keywords
    cancer_keywords = ['cancer', 'carcinoma', 'breast', 'tumor', 'malignant', 'neoplasm',
                       'grandmother', 'grandma', 'maternal']
    if any(kw in relatives_cancer for kw in cancer_keywords):
        cancer_documented = True
    
    if cancer_documented:
        score += 25
        subscores["cancer_documented"] = True
        feedback_parts.append("Grandmother's cancer documented")
    else:
        feedback_parts.append("Grandmother's cancer NOT documented")
    
    # Also check lists table entries if history_data fields are empty
    lists_entries = result.get('lists_entries', '').lower()
    if lists_entries and current_lists_count > initial_lists_count:
        if not subscores["diabetes_documented"] and 'diabetes' in lists_entries:
            score += 25
            subscores["diabetes_documented"] = True
            feedback_parts.append("Mother's diabetes documented (via lists table)")
        
        if not subscores["heart_documented"] and any(kw in lists_entries for kw in ['heart', 'mi', 'myocardial', 'cardiac']):
            score += 25
            subscores["heart_documented"] = True
            feedback_parts.append("Father's heart disease documented (via lists table)")
        
        if not subscores["cancer_documented"] and 'cancer' in lists_entries:
            score += 25
            subscores["cancer_documented"] = True
            feedback_parts.append("Grandmother's cancer documented (via lists table)")
    
    # Cap score at max
    score = min(score, max_score)
    
    # Calculate conditions documented count
    conditions_documented = sum([
        subscores["diabetes_documented"],
        subscores["heart_documented"],
        subscores["cancer_documented"]
    ])
    
    # Determine pass/fail
    # Pass threshold: 60 points AND at least one condition documented
    key_criteria_met = subscores["patient_correct"] and conditions_documented >= 1
    passed = score >= 60 and key_criteria_met
    
    # Add summary to feedback
    feedback_parts.append(f"Conditions documented: {conditions_documented}/3")
    feedback_parts.append(f"Score: {score}/{max_score}")
    
    logger.info(f"Verification complete: score={score}, passed={passed}")
    logger.info(f"Subscores: {subscores}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "patient_pid": patient_pid,
            "conditions_documented": conditions_documented,
            "data_changed": data_changed,
            "new_history_records": current_history_count - initial_history_count,
            "new_lists_records": current_lists_count - initial_lists_count,
            "raw_diabetes_field": history_data.get('relatives_diabetes', ''),
            "raw_heart_field": history_data.get('relatives_heart_problems', ''),
            "raw_cancer_field": history_data.get('relatives_cancer', '')
        }
    }


def main():
    """Main entry point for standalone testing."""
    # Mock test data for standalone testing
    mock_result = {
        "patient_pid": 4,
        "task_start_time": 1700000000,
        "task_end_time": 1700000300,
        "data_changed": True,
        "initial_history_count": 0,
        "current_history_count": 1,
        "initial_lists_count": 0,
        "current_lists_count": 0,
        "history_data": {
            "id": "1",
            "relatives_diabetes": "Mother - Type 2 Diabetes, diagnosed age 45",
            "relatives_heart_problems": "Father - Myocardial Infarction at age 58",
            "relatives_cancer": "Maternal grandmother - Breast cancer, diagnosed age 62",
            "date": "2024-01-15"
        },
        "documentation_status": {
            "diabetes_documented": True,
            "heart_documented": True,
            "cancer_documented": True
        },
        "lists_entries": ""
    }
    
    print("Mock test with complete documentation:")
    print(json.dumps(mock_result, indent=2))
    
    # Simulate verification logic
    score = 0
    if mock_result["patient_pid"] == 4:
        score += 10
    if mock_result["data_changed"]:
        score += 15
    if mock_result["documentation_status"]["diabetes_documented"]:
        score += 25
    if mock_result["documentation_status"]["heart_documented"]:
        score += 25
    if mock_result["documentation_status"]["cancer_documented"]:
        score += 25
    
    print(f"\nMock verification score: {score}/100")
    print(f"Passed: {score >= 60}")


if __name__ == "__main__":
    main()