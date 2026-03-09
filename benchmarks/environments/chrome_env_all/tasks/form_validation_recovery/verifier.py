#!/usr/bin/env python3
"""
Verifier for Chrome Form Validation and Error Recovery Task
Task: Trigger validation errors, observe feedback, correct errors, submit successfully

Verification Strategy:
1. Check if form was successfully submitted (URL contains "success" or title indicates success)
2. Verify no validation error elements remain visible
3. Validate submitted data format (if accessible)
4. Detect evidence of error recovery (multiple submission attempts)

Scoring:
- 100%: All 4 criteria met (perfect error recovery and submission)
- 75-99%: 3/4 criteria met (successful submission with minor verification gaps)
- 50-74%: 2/4 criteria met (partial success)
- 0-49%: <2 criteria met (failed to complete submission)

Pass threshold: 75% (requires at least 3 out of 4 criteria)
"""

import logging
import sys
import os
import json
import re
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for form_validation_recovery@1.
    
    Args:
        traj: Trajectory data (not heavily used for this verification)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with 'passed', 'score', and 'feedback' keys
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }

    try:
        # Get verification data from container
        final_state = get_final_state(copy_from_env)
        
        # Perform multi-criteria verification
        verification_result = verify_form_submission(final_state, traj)
        
        # Clean up
        cleanup_verification_temp()
        
        return verification_result

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def get_final_state(copy_from_env) -> Dict[str, Any]:
    """
    Retrieve final browser state from container.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Dict with URL, title, DOM state, and submission status
    """
    final_state = {
        'url': '',
        'title': '',
        'dom_state': {},
        'submission_status': 'unknown',
        'tabs_data': []
    }
    
    # Copy final URL
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
        temp_file.close()
        copy_from_env("/tmp/final_url.txt", temp_file.name)
        with open(temp_file.name, 'r') as f:
            final_state['url'] = f.read().strip()
        os.unlink(temp_file.name)
        logger.info(f"Final URL: {final_state['url']}")
    except Exception as e:
        logger.warning(f"Could not get final URL: {e}")
    
    # Copy final title
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
        temp_file.close()
        copy_from_env("/tmp/final_title.txt", temp_file.name)
        with open(temp_file.name, 'r') as f:
            final_state['title'] = f.read().strip()
        os.unlink(temp_file.name)
        logger.info(f"Final Title: {final_state['title']}")
    except Exception as e:
        logger.warning(f"Could not get final title: {e}")
    
    # Copy DOM state
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_file.close()
        copy_from_env("/tmp/dom_state.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            final_state['dom_state'] = json.load(f)
        os.unlink(temp_file.name)
        logger.info(f"DOM State: {final_state['dom_state']}")
    except Exception as e:
        logger.warning(f"Could not get DOM state: {e}")
    
    # Copy submission status
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
        temp_file.close()
        copy_from_env("/tmp/submission_status.txt", temp_file.name)
        with open(temp_file.name, 'r') as f:
            final_state['submission_status'] = f.read().strip()
        os.unlink(temp_file.name)
        logger.info(f"Submission Status: {final_state['submission_status']}")
    except Exception as e:
        logger.warning(f"Could not get submission status: {e}")
    
    # Copy full tabs data
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_file.close()
        copy_from_env("/tmp/chrome_tabs.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            final_state['tabs_data'] = json.load(f)
        os.unlink(temp_file.name)
        logger.info(f"Retrieved {len(final_state['tabs_data'])} tabs data")
    except Exception as e:
        logger.warning(f"Could not get tabs data: {e}")
    
    return final_state


def verify_form_submission(final_state: Dict[str, Any], traj) -> Dict[str, Any]:
    """
    Verify form submission with error recovery.
    
    Criteria:
    1. Submission successful (URL/title indicates success page)
    2. No validation errors remain
    3. Valid form data (email, phone format check if accessible)
    4. Error recovery evidence (multiple actions, corrections visible in trajectory)
    
    Args:
        final_state: Browser final state data
        traj: Agent trajectory data
        
    Returns:
        Verification result with passed, score, and feedback
    """
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    url = final_state.get('url', '')
    title = final_state.get('title', '')
    submission_status = final_state.get('submission_status', 'unknown')
    
    # Criterion 1: Submission Successful (URL or title indicates success)
    logger.info("Checking submission success...")
    submission_successful = False
    
    if 'success.html' in url.lower():
        submission_successful = True
        feedback_parts.append("✓ Submission successful: Reached success.html page")
        logger.info("Success detected via URL")
    elif 'success' in title.lower() or 'registration successful' in title.lower():
        submission_successful = True
        feedback_parts.append("✓ Submission successful: Success message in page title")
        logger.info("Success detected via title")
    elif submission_status == 'success':
        submission_successful = True
        feedback_parts.append("✓ Submission successful: Success status confirmed")
        logger.info("Success detected via submission status")
    else:
        feedback_parts.append(f"✗ Submission failed: Still on form page or error page (URL: {url[:50]}...)")
        logger.info(f"No success detected. URL: {url}, Title: {title}")
    
    if submission_successful:
        criteria_met += 1
    
    # Criterion 2: No validation errors remain
    logger.info("Checking for remaining validation errors...")
    no_errors = True  # Assume no errors if we're on success page
    
    if not submission_successful:
        # If not on success page, check if still showing errors
        if 'registration_form.html' in url:
            no_errors = False
            feedback_parts.append("✗ Validation errors: Agent still on form page, likely has errors")
        else:
            # Uncertain state
            feedback_parts.append("⚠ Error check: Cannot verify (not on known page)")
            no_errors = None  # Neutral
    else:
        feedback_parts.append("✓ No validation errors: Successfully left form page")
    
    if no_errors is True:
        criteria_met += 1
    elif no_errors is None:
        criteria_met += 0.5  # Partial credit for uncertainty
    
    # Criterion 3: Valid form data format
    logger.info("Checking form data validity...")
    valid_data = None  # Cannot easily check without sessionStorage access
    
    # We can infer validity if submission succeeded (form has validation)
    if submission_successful:
        valid_data = True
        feedback_parts.append("✓ Valid form data: Form validation passed (inferred from successful submission)")
        criteria_met += 1
    else:
        feedback_parts.append("✗ Form data validation: Submission did not complete")
    
    # Criterion 4: Error recovery evidence
    logger.info("Checking for error recovery evidence...")
    error_recovery = False
    
    # Check trajectory for multiple actions
    if traj is not None and hasattr(traj, '__len__'):
        action_count = len(traj)
        if action_count >= 8:
            # Reasonable number of actions suggesting correction
            error_recovery = True
            feedback_parts.append(f"✓ Error recovery evidence: {action_count} actions taken (suggests error correction)")
        else:
            feedback_parts.append(f"⚠ Error recovery uncertain: Only {action_count} actions (may not have triggered/corrected errors)")
            error_recovery = None  # Uncertain
    else:
        # No trajectory data, infer from success
        if submission_successful:
            error_recovery = True
            feedback_parts.append("✓ Error recovery: Successful submission implies error handling")
        else:
            feedback_parts.append("⚠ Error recovery: Cannot verify without trajectory data")
    
    if error_recovery is True:
        criteria_met += 1
    elif error_recovery is None:
        criteria_met += 0.3  # Small partial credit
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*60}"
    feedback += f"\nCriteria met: {criteria_met:.1f}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'✅ PASSED' if passed else '❌ FAILED'}"
    
    if not passed:
        feedback += "\n\nTo pass this task, the agent must:"
        feedback += "\n1. Fill the form with invalid data and click Submit"
        feedback += "\n2. Observe validation error messages"
        feedback += "\n3. Correct each error based on the error messages"
        feedback += "\n4. Submit the form again successfully"
        feedback += "\n\nRequired formats:"
        feedback += "\n- Email: user@example.com"
        feedback += "\n- Phone: (XXX) XXX-XXXX"
        feedback += "\n- Password: 8+ chars with upper, lower, number, special char"
        feedback += "\n- Name: 3+ characters"
    
    logger.info(f"Verification complete: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "final_url": url,
            "final_title": title,
            "submission_successful": submission_successful,
            "criteria_met": criteria_met,
            "total_criteria": total_criteria
        }
    }
