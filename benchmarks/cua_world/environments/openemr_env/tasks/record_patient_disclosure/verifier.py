#!/usr/bin/env python3
"""
Verifier for Record Patient Disclosure task in OpenEMR

Verifies that a HIPAA-required disclosure record was created for patient
Verla Denesik (pid=5) with appropriate recipient and description information.

Verification Criteria:
1. Disclosure record exists for correct patient (pid=5)
2. Disclosure was newly created during task (not pre-existing)
3. Recipient field contains expected keywords (Johnson, Law, etc.)
4. Description/comments are non-empty and relevant
5. VLM trajectory verification shows workflow completion
"""

import sys
import os
import json
import logging
import tempfile
import re
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import VLM utilities if available
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logger.warning("VLM utilities not available - will skip visual verification")


def verify_record_disclosure(traj, env_info, task_info):
    """
    Verify that a patient disclosure record was correctly created.

    Scoring (100 points total):
    - Disclosure record exists for correct patient: 25 points
    - Disclosure is newly created (not pre-existing): 20 points
    - Recipient contains expected keywords: 20 points
    - Description/comments are populated: 15 points
    - VLM trajectory verification: 20 points

    Passing threshold: 60 points with disclosure_found = True
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
    expected_fname = metadata.get('patient_fname', 'Verla')
    expected_lname = metadata.get('patient_lname', 'Denesik')
    expected_keywords = metadata.get('expected_keywords', ['johnson', 'law', 'attorney', 'legal'])
    description_keywords = metadata.get('description_keywords', ['medical records', 'authorization', 'personal injury'])

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/disclosure_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {
            "correct_patient": False,
            "newly_created": False,
            "recipient_valid": False,
            "description_valid": False,
            "vlm_verification": False
        }

        # Extract result data
        patient_pid = result.get('patient_pid', 0)
        initial_count = result.get('initial_disclosure_count', 0)
        current_count = result.get('current_disclosure_count', 0)
        initial_table_count = result.get('initial_disclosure_table_count', 0)
        current_table_count = result.get('current_disclosure_table_count', 0)
        disclosure_found = result.get('disclosure_found', False)
        disclosure = result.get('disclosure', {})
        validation = result.get('validation', {})
        task_start = result.get('task_start_timestamp', 0)
        task_end = result.get('task_end_timestamp', 0)

        logger.info(f"Result data: pid={patient_pid}, initial={initial_count}, current={current_count}")
        logger.info(f"Disclosure found: {disclosure_found}")
        logger.info(f"Disclosure data: {disclosure}")

        # CRITERION 1: Correct patient (25 points)
        if patient_pid == expected_pid:
            if disclosure_found:
                score += 25
                subscores["correct_patient"] = True
                feedback_parts.append(f"✅ Disclosure record found for patient {expected_fname} {expected_lname} (pid={expected_pid})")
            else:
                feedback_parts.append(f"❌ No disclosure record found for patient pid={expected_pid}")
        else:
            feedback_parts.append(f"❌ CRITICAL: Wrong patient! Expected pid={expected_pid}, got {patient_pid}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Disclosure recorded for wrong patient",
                "subscores": subscores
            }

        if not disclosure_found:
            # Check if any new records were added anywhere
            total_initial = initial_count + initial_table_count
            total_current = current_count + current_table_count
            if total_current > total_initial:
                feedback_parts.append(f"Note: {total_current - total_initial} new record(s) detected but not matching expected format")
            else:
                feedback_parts.append("No new disclosure records were created during task")
            
            # Attempt VLM verification as fallback
            vlm_score = perform_vlm_verification(traj, env_info)
            if vlm_score > 0:
                score += vlm_score
                feedback_parts.append(f"VLM verification suggests partial completion ({vlm_score} pts)")
            
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }

        # CRITERION 2: Newly created (20 points)
        # Must have more disclosures now than before task started
        total_initial = initial_count + initial_table_count
        total_current = current_count + current_table_count
        
        if total_current > total_initial:
            score += 20
            subscores["newly_created"] = True
            feedback_parts.append(f"✅ New disclosure created (count: {total_initial} → {total_current})")
        else:
            feedback_parts.append(f"⚠️ Disclosure count unchanged - may be pre-existing record")

        # CRITERION 3: Recipient validation (20 points)
        recipient = disclosure.get('recipient', '').lower()
        recipient_keywords_found = []
        
        for keyword in expected_keywords:
            if keyword.lower() in recipient:
                recipient_keywords_found.append(keyword)
        
        if recipient_keywords_found:
            score += 20
            subscores["recipient_valid"] = True
            feedback_parts.append(f"✅ Recipient contains expected keywords: {', '.join(recipient_keywords_found)}")
        elif recipient:
            # Partial credit if recipient is filled but doesn't match exactly
            score += 10
            feedback_parts.append(f"⚠️ Recipient filled but missing expected keywords: '{recipient[:50]}...'")
        else:
            feedback_parts.append("❌ Recipient field is empty or not found")

        # CRITERION 4: Description/Comments validation (15 points)
        comments = disclosure.get('comments', '').lower()
        comments_valid = validation.get('comments_nonempty', False)
        comments_keywords_found = []
        
        for keyword in description_keywords:
            if keyword.lower() in comments:
                comments_keywords_found.append(keyword)
        
        if comments_keywords_found:
            score += 15
            subscores["description_valid"] = True
            feedback_parts.append(f"✅ Description contains relevant content: {', '.join(comments_keywords_found[:3])}")
        elif comments_valid and comments:
            # Partial credit for non-empty comments
            score += 8
            feedback_parts.append(f"⚠️ Description provided but missing expected keywords")
        else:
            feedback_parts.append("❌ Description/comments field is empty")

        # CRITERION 5: VLM trajectory verification (20 points)
        vlm_score = perform_vlm_verification(traj, env_info)
        if vlm_score > 0:
            score += vlm_score
            subscores["vlm_verification"] = vlm_score >= 15
            feedback_parts.append(f"✅ VLM verification: {vlm_score}/20 points")
        else:
            feedback_parts.append("⚠️ VLM verification not available or failed")

        # Calculate pass/fail
        # Must have disclosure found + at least 60 points to pass
        passed = disclosure_found and score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "disclosure": disclosure,
                "validation": validation,
                "counts": {
                    "initial": total_initial,
                    "current": total_current
                }
            }
        }

    except FileNotFoundError:
        logger.error("Result file not found - export may have failed")
        return {
            "passed": False,
            "score": 0,
            "feedback": "Export result file not found - task may not have completed properly"
        }
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse export result: {e}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def perform_vlm_verification(traj, env_info):
    """
    Use VLM to verify the task was completed via trajectory analysis.
    
    Checks:
    - Agent navigated to patient chart
    - Agent found and opened Disclosures section
    - Agent filled out disclosure form
    - Agent saved the disclosure
    
    Returns:
        int: Score from 0-20 based on VLM verification
    """
    if not VLM_AVAILABLE:
        return 0
    
    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        return 0
    
    try:
        # Sample frames from trajectory (not just final screenshot)
        frames = sample_trajectory_frames(traj, n=5)
        final_screenshot = get_final_screenshot(traj)
        
        if not frames and not final_screenshot:
            logger.warning("No trajectory frames or final screenshot available")
            return 0
        
        # Combine frames for analysis
        all_frames = frames + ([final_screenshot] if final_screenshot else [])
        
        if not all_frames:
            return 0
        
        # VLM prompt for disclosure workflow verification
        vlm_prompt = """You are verifying if a computer agent completed a HIPAA disclosure recording task in OpenEMR (Electronic Health Records system).

TASK: Record a patient disclosure for Verla Denesik. The agent should have:
1. Logged into OpenEMR
2. Found patient Verla Denesik
3. Navigated to Disclosures section
4. Filled out a disclosure form with recipient "Law Offices of Johnson & Associates"
5. Saved the disclosure record

Examine these screenshots from the agent's workflow and determine:
1. Is this OpenEMR (medical records system with patient data)?
2. Did the agent navigate to a patient chart?
3. Is there evidence of a Disclosures or Tracking section?
4. Is there a form being filled out with recipient/description fields?
5. Is there evidence of successful form submission (save confirmation)?

Respond in JSON format:
{
    "is_openemr": true/false,
    "patient_chart_accessed": true/false,
    "disclosures_section_found": true/false,
    "form_filled": true/false,
    "save_completed": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""
        
        vlm_result = query_vlm(
            prompt=vlm_prompt,
            images=all_frames
        )
        
        if not vlm_result.get('success'):
            logger.warning(f"VLM query failed: {vlm_result.get('error')}")
            return 0
        
        parsed = vlm_result.get('parsed', {})
        
        # Calculate score based on VLM findings
        vlm_score = 0
        
        if parsed.get('is_openemr', False):
            vlm_score += 4
        if parsed.get('patient_chart_accessed', False):
            vlm_score += 4
        if parsed.get('disclosures_section_found', False):
            vlm_score += 4
        if parsed.get('form_filled', False):
            vlm_score += 4
        if parsed.get('save_completed', False):
            vlm_score += 4
        
        # Adjust for confidence
        confidence = parsed.get('confidence', 'low')
        if confidence == 'low':
            vlm_score = int(vlm_score * 0.6)
        elif confidence == 'medium':
            vlm_score = int(vlm_score * 0.8)
        
        logger.info(f"VLM verification score: {vlm_score}/20, confidence: {confidence}")
        return min(vlm_score, 20)
        
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        return 0


# For testing/debugging
if __name__ == "__main__":
    # Mock test
    print("Disclosure Verifier Module")
    print("Run via gym-anything framework for actual verification")