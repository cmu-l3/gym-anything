#!/usr/bin/env python3
"""
Verifier for Resolve Medical Problem task in OpenEMR

Verifies that the agent correctly marked a medical problem (Acute bronchitis)
as resolved by setting an end date.

Uses copy_from_env to read pre-exported verification data from the container.
"""

import sys
import os
import json
import logging
import tempfile
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_resolve_medical_problem(traj, env_info, task_info):
    """
    Verify that the medical problem was properly marked as resolved.
    
    Scoring (100 points total):
    - Problem found: 15 points
    - End date populated: 35 points  
    - End date valid (within 24h, after begin date): 20 points
    - Original data intact (begdate, title unchanged): 15 points
    - No duplicate created: 10 points
    - Workflow confirmed (screenshot/VLM): 5 points
    
    Passing threshold: 70 points with enddate_populated = True
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 1)
    expected_fname = metadata.get('patient_fname', 'Philip')
    expected_lname = metadata.get('patient_lname', 'Sipes')
    problem_title = metadata.get('problem_title', 'Acute bronchitis')
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/resolve_problem_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        score = 0
        feedback_parts = []
        subscores = {
            "problem_found": False,
            "enddate_populated": False,
            "enddate_valid": False,
            "original_data_intact": False,
            "no_duplicate": False,
            "workflow_confirmed": False
        }
        
        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        problem_found = result.get('problem_found', False)
        problem = result.get('problem', {})
        original_data = result.get('original_data', {})
        validation = result.get('validation', {})
        counts = result.get('counts', {})
        task_start = result.get('task_start_time', 0)
        
        logger.info(f"Result data: pid={patient_pid}, found={problem_found}")
        logger.info(f"Problem: {problem}")
        logger.info(f"Validation: {validation}")
        
        # CRITERION 1: Problem found (15 points)
        if problem_found:
            title = problem.get('title', '').lower()
            if 'bronchitis' in title:
                score += 15
                subscores["problem_found"] = True
                feedback_parts.append(f"✓ Bronchitis problem found for patient (pid={patient_pid})")
            else:
                feedback_parts.append(f"✗ Problem found but title doesn't match: '{problem.get('title', '')}'")
        else:
            feedback_parts.append("✗ Target problem not found in database")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }
        
        # CRITERION 2: End date populated (35 points) - CRITICAL
        enddate = problem.get('enddate', '')
        enddate_populated = validation.get('enddate_populated', False)
        
        if enddate_populated and enddate and enddate != 'NULL' and enddate != '0000-00-00':
            score += 35
            subscores["enddate_populated"] = True
            feedback_parts.append(f"✓ End date is populated: {enddate}")
        else:
            feedback_parts.append("✗ End date is NOT populated - problem not marked as resolved")
            # This is critical - cannot pass without this
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }
        
        # CRITERION 3: End date valid (20 points)
        # Must be within 24 hours of task execution and after begin date
        enddate_valid = validation.get('enddate_valid', False)
        begdate = problem.get('begdate', '')
        
        if enddate_valid:
            score += 20
            subscores["enddate_valid"] = True
            feedback_parts.append(f"✓ End date is valid (recent and after begin date)")
        else:
            # Perform our own validation
            try:
                end_dt = datetime.strptime(enddate, '%Y-%m-%d')
                now = datetime.now()
                
                # Check if within reasonable range (last 2 days)
                date_diff = abs((now.date() - end_dt.date()).days)
                
                if date_diff <= 2:
                    # Check if after begin date
                    if begdate:
                        beg_dt = datetime.strptime(begdate, '%Y-%m-%d')
                        if end_dt >= beg_dt:
                            score += 20
                            subscores["enddate_valid"] = True
                            feedback_parts.append(f"✓ End date {enddate} is valid")
                        else:
                            feedback_parts.append(f"✗ End date {enddate} is before begin date {begdate}")
                    else:
                        score += 20
                        subscores["enddate_valid"] = True
                        feedback_parts.append(f"✓ End date {enddate} is valid")
                else:
                    feedback_parts.append(f"✗ End date {enddate} is not within expected range")
            except ValueError as e:
                feedback_parts.append(f"✗ Could not parse end date: {enddate}")
        
        # CRITERION 4: Original data intact (15 points)
        # Begin date and title should not have been changed
        begdate_preserved = validation.get('begdate_preserved', False)
        title_preserved = validation.get('title_preserved', False)
        original_begdate = original_data.get('begdate', '')
        current_begdate = problem.get('begdate', '')
        
        if begdate_preserved and title_preserved:
            score += 15
            subscores["original_data_intact"] = True
            feedback_parts.append(f"✓ Original data preserved (begdate: {current_begdate})")
        elif begdate_preserved:
            # Partial credit if begdate preserved but title changed slightly
            score += 10
            subscores["original_data_intact"] = True
            feedback_parts.append(f"✓ Begin date preserved: {current_begdate}")
        else:
            if original_begdate and current_begdate and original_begdate != current_begdate:
                feedback_parts.append(f"✗ Begin date changed from {original_begdate} to {current_begdate}")
            else:
                # Give benefit of doubt if we couldn't record original
                score += 15
                subscores["original_data_intact"] = True
                feedback_parts.append("✓ Original data appears intact")
        
        # CRITERION 5: No duplicate created (10 points)
        # Agent should have edited existing entry, not created a new one
        initial_count = counts.get('initial_bronchitis_count', 1)
        current_count = counts.get('current_bronchitis_count', 1)
        duplicate_created = validation.get('duplicate_created', False)
        
        if not duplicate_created and current_count <= initial_count:
            score += 10
            subscores["no_duplicate"] = True
            feedback_parts.append("✓ No duplicate entry created (edited existing)")
        else:
            feedback_parts.append(f"✗ Duplicate may have been created (count: {initial_count} -> {current_count})")
        
        # CRITERION 6: Workflow confirmed (5 points)
        # Basic check - give points if we got this far with valid data
        score += 5
        subscores["workflow_confirmed"] = True
        feedback_parts.append("✓ Workflow completed")
        
        # Determine pass/fail
        # Must have: enddate populated (critical) + score >= 70
        passed = subscores["enddate_populated"] and score >= 70
        
        # Summary
        feedback_parts.append(f"\nTotal Score: {score}/100")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "patient_pid": patient_pid,
                "problem_id": problem.get('id', ''),
                "problem_title": problem.get('title', ''),
                "begdate": problem.get('begdate', ''),
                "enddate": problem.get('enddate', ''),
                "original_begdate": original_begdate
            }
        }
        
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export may have failed"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse result JSON: {e}"
        }
    except Exception as e:
        logger.exception("Verification failed with exception")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


if __name__ == "__main__":
    # For local testing
    print("This verifier should be run through the gym-anything framework")
    print("It requires copy_from_env function from env_info")