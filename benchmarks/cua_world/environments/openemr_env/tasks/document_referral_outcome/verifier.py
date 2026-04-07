#!/usr/bin/env python3
"""
Verifier for Document Referral Outcome task in OpenEMR

Verifies that the agent:
1. Found the correct patient (Domingo Kiehn)
2. Located the cardiology referral
3. Updated the referral status to completed
4. Documented the consultation date
5. Recorded the specialist's recommendations with key clinical details

Uses copy_from_env to read pre-exported verification data from the container.
"""

import sys
import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_referral_outcome(traj, env_info, task_info):
    """
    Verify that the referral outcome was correctly documented.

    Scoring (100 points total):
    - Correct patient accessed: 15 points
    - Referral was accessed/modified: 15 points
    - Referral status updated to completed: 25 points
    - Consultation date documented: 15 points
    - Recommendations documented with key content: 25 points
    - Content accuracy (keywords present): 5 points

    Passing threshold: 70 points with status_updated required
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 5)
    expected_fname = metadata.get('patient_fname', 'Domingo')
    expected_lname = metadata.get('patient_lname', 'Kiehn')
    expected_referral_to = metadata.get('referral_to', 'Cardiology')
    expected_consultation_date = metadata.get('consultation_date', '2024-02-01')
    expected_keywords = metadata.get('expected_keywords', [
        'echocardiogram', 'LVH', 'left ventricular', 'aspirin', '130/80', '12 months'
    ])

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/referral_outcome_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {
            "correct_patient": False,
            "referral_accessed": False,
            "status_updated": False,
            "consultation_date": False,
            "recommendations_documented": False,
            "content_accuracy": False
        }

        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        referral_found = result.get('referral_found', False)
        referral = result.get('referral', {})
        validation = result.get('validation', {})
        task_start = result.get('task_start_timestamp', 0)

        logger.info(f"Result data: pid={patient_pid}, referral_found={referral_found}")
        logger.info(f"Referral: {referral}")
        logger.info(f"Validation: {validation}")

        # CRITERION 1: Correct patient (15 points)
        if patient_pid == expected_pid:
            score += 15
            subscores["correct_patient"] = True
            feedback_parts.append(f"✓ Correct patient (pid={expected_pid}, {expected_fname} {expected_lname})")
        else:
            feedback_parts.append(f"✗ Wrong patient: expected pid={expected_pid}, got {patient_pid}")
            # Wrong patient is critical - but don't fail entirely, might have found patient differently

        # CRITERION 2: Referral was accessed/found (15 points)
        if referral_found:
            refer_to = referral.get('refer_to', '')
            if 'cardiology' in refer_to.lower():
                score += 15
                subscores["referral_accessed"] = True
                feedback_parts.append(f"✓ Cardiology referral found (ID: {referral.get('id', 'unknown')})")
            else:
                score += 5  # Partial credit for finding any referral
                feedback_parts.append(f"⚠ Found referral but not cardiology (refer_to: {refer_to})")
        else:
            feedback_parts.append("✗ No referral found for patient")
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }

        # CRITERION 3: Status updated to completed (25 points)
        status_updated = validation.get('status_updated', False)
        reply_date = referral.get('reply_date', '')
        
        # Check if reply_date is set and valid
        if status_updated or (reply_date and reply_date not in ['', 'NULL', 'None', '0000-00-00']):
            score += 25
            subscores["status_updated"] = True
            feedback_parts.append(f"✓ Referral status updated (reply_date: {reply_date})")
        else:
            feedback_parts.append("✗ Referral status not updated to completed")

        # CRITERION 4: Consultation date documented (15 points)
        consultation_date_match = validation.get('consultation_date_match', False)
        
        # Also check reply_date directly for the expected date
        if consultation_date_match:
            score += 15
            subscores["consultation_date"] = True
            feedback_parts.append(f"✓ Consultation date documented ({expected_consultation_date})")
        elif reply_date and '2024' in reply_date:
            score += 10  # Partial credit for any 2024 date
            feedback_parts.append(f"⚠ Consultation date present but not exact match (got: {reply_date})")
        else:
            feedback_parts.append(f"✗ Consultation date not documented (expected: {expected_consultation_date})")

        # CRITERION 5: Recommendations documented (25 points)
        recommendations_added = validation.get('recommendations_added', False)
        body = referral.get('body', '')
        reply_mail = referral.get('reply_mail', '')
        
        combined_notes = f"{body} {reply_mail}".lower()
        
        if recommendations_added and len(combined_notes.strip()) > 20:
            score += 25
            subscores["recommendations_documented"] = True
            feedback_parts.append("✓ Specialist recommendations documented")
        elif len(combined_notes.strip()) > 10:
            score += 15  # Partial credit for some content
            feedback_parts.append("⚠ Some content added but may be incomplete")
        else:
            feedback_parts.append("✗ Specialist recommendations not documented")

        # CRITERION 6: Content accuracy - keywords (5 points)
        keywords = validation.get('keywords', {})
        keywords_found = keywords.get('total_found', 0)
        
        # Check each keyword
        keyword_details = []
        if keywords.get('echocardiogram', False):
            keyword_details.append('echocardiogram')
        if keywords.get('lvh', False):
            keyword_details.append('LVH')
        if keywords.get('aspirin', False):
            keyword_details.append('aspirin')
        if keywords.get('bp_target', False):
            keyword_details.append('BP target')
        if keywords.get('followup', False):
            keyword_details.append('follow-up')
        
        if keywords_found >= 3:
            score += 5
            subscores["content_accuracy"] = True
            feedback_parts.append(f"✓ Key clinical details present ({keywords_found}/5: {', '.join(keyword_details)})")
        elif keywords_found >= 1:
            score += 2  # Partial credit
            feedback_parts.append(f"⚠ Some clinical details present ({keywords_found}/5: {', '.join(keyword_details)})")
        else:
            feedback_parts.append("✗ Key clinical details missing (echocardiogram, LVH, aspirin, BP target, follow-up)")

        # Determine pass/fail
        # Must have status_updated (25 pts) and at least 70 total
        key_criteria_met = subscores["status_updated"] and subscores["referral_accessed"]
        passed = score >= 70 and key_criteria_met

        # Build final feedback
        feedback = " | ".join(feedback_parts)
        
        if passed:
            feedback = f"✓ Task completed successfully (Score: {score}/100) | " + feedback
        else:
            if not subscores["status_updated"]:
                feedback = f"✗ Task failed: Referral status must be updated to 'completed' | " + feedback
            else:
                feedback = f"✗ Task failed: Score {score}/100 (need 70) | " + feedback

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores,
            "details": {
                "patient_pid": patient_pid,
                "referral_id": referral.get('id', ''),
                "reply_date": reply_date,
                "keywords_found": keywords_found,
                "body_length": len(body),
                "reply_mail_length": len(reply_mail)
            }
        }

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export_result.sh may have failed",
            "subscores": {
                "correct_patient": False,
                "referral_accessed": False,
                "status_updated": False,
                "consultation_date": False,
                "recommendations_documented": False,
                "content_accuracy": False
            }
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse result JSON: {e}",
            "subscores": {
                "correct_patient": False,
                "referral_accessed": False,
                "status_updated": False,
                "consultation_date": False,
                "recommendations_documented": False,
                "content_accuracy": False
            }
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "subscores": {
                "correct_patient": False,
                "referral_accessed": False,
                "status_updated": False,
                "consultation_date": False,
                "recommendations_documented": False,
                "content_accuracy": False
            }
        }


def verify_with_vlm_trajectory(traj, env_info, task_info, base_result):
    """
    Optional VLM-based trajectory verification to supplement database checks.
    
    Examines trajectory frames to verify:
    1. Agent navigated to patient chart
    2. Agent accessed referrals section
    3. Agent opened/edited referral dialog
    4. Agent entered recommendations
    """
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
    except ImportError:
        logger.warning("VLM utilities not available, skipping trajectory verification")
        return base_result
    
    query_vlm_func = env_info.get('query_vlm')
    if not query_vlm_func:
        return base_result
    
    # Sample frames from trajectory
    frames = sample_trajectory_frames(traj, n=5)
    if not frames:
        return base_result
    
    # Query VLM about workflow
    vlm_prompt = """Analyze these screenshots from an OpenEMR workflow. Determine if the agent:
1. Searched for and opened a patient chart
2. Navigated to referrals or transactions section
3. Opened or edited a referral record
4. Entered text into a form (likely recommendations)
5. Saved changes

Respond in JSON:
{
    "patient_chart_opened": true/false,
    "referrals_accessed": true/false,
    "referral_edited": true/false,
    "text_entered": true/false,
    "changes_saved": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""
    
    vlm_result = query_vlm_func(
        prompt=vlm_prompt,
        images=frames
    )
    
    if vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        
        # Add VLM bonus points if trajectory shows correct workflow
        if parsed.get('referral_edited') and parsed.get('text_entered'):
            if base_result['score'] < 100:
                base_result['score'] = min(100, base_result['score'] + 5)
                base_result['feedback'] += " | ✓ VLM confirms referral editing workflow"
        
        base_result['vlm_analysis'] = parsed
    
    return base_result