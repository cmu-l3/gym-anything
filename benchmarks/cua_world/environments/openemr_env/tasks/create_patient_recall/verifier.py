#!/usr/bin/env python3
"""
Verifier for Create Patient Recall task in OpenEMR

Verifies that a patient recall entry was correctly created for preventive care tracking.
Uses copy_from_env to read pre-exported verification data from the container.

Scoring (100 points total):
- Recall entry exists: 30 points
- Correct patient linked (pid=3): 20 points  
- Future date in valid range (150-210 days): 20 points
- Reason contains wellness/annual keywords: 15 points
- Entry created during task (not pre-existing): 10 points
- Provider assigned: 5 points

Pass threshold: 70 points with recall exists + correct patient
"""

import sys
import os
import json
import logging
import tempfile
import re
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_patient_recall(traj, env_info, task_info):
    """
    Verify that a patient recall entry was correctly created.
    
    Args:
        traj: Trajectory data with frames and episode info
        env_info: Environment info with copy_from_env function
        task_info: Task info with metadata
        
    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 3)
    expected_fname = metadata.get('patient_fname', 'Jayson')
    expected_lname = metadata.get('patient_lname', 'Fadel')
    recall_days_min = metadata.get('recall_days_min', 150)
    recall_days_max = metadata.get('recall_days_max', 210)
    reason_keywords = metadata.get('reason_keywords', ['wellness', 'annual', 'exam', 'physical', 'checkup', 'preventive'])
    
    # Scoring weights from metadata
    score_recall_exists = metadata.get('score_recall_exists', 30)
    score_correct_patient = metadata.get('score_correct_patient', 20)
    score_future_date = metadata.get('score_future_date', 20)
    score_reason_documented = metadata.get('score_reason_documented', 15)
    score_created_during_task = metadata.get('score_created_during_task', 10)
    score_provider_assigned = metadata.get('score_provider_assigned', 5)
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/create_recall_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        score = 0
        feedback_parts = []
        subscores = {
            "recall_exists": False,
            "correct_patient": False,
            "future_date_valid": False,
            "reason_documented": False,
            "created_during_task": False,
            "provider_assigned": False
        }
        
        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        recall_found = result.get('recall_found', False)
        recall_source = result.get('recall_source', 'none')
        recall = result.get('recall', {})
        validation = result.get('validation', {})
        counts = result.get('counts', {})
        
        task_start = result.get('task_start_timestamp', 0)
        task_end = result.get('task_end_timestamp', 0)
        
        logger.info(f"Result data: pid={patient_pid}, found={recall_found}, source={recall_source}")
        logger.info(f"Recall data: {recall}")
        logger.info(f"Counts: {counts}")
        
        # CRITERION 1: Recall entry exists (30 points)
        if recall_found:
            score += score_recall_exists
            subscores["recall_exists"] = True
            feedback_parts.append(f"✅ Recall entry found (source: {recall_source})")
        else:
            feedback_parts.append("❌ No recall entry found in database")
            # Check if any new entries were added at all
            new_reminders = counts.get('current_reminders', 0) - counts.get('initial_reminders', 0)
            new_recalls = counts.get('current_recalls', 0) - counts.get('initial_recalls', 0)
            new_calendar = counts.get('current_calendar', 0) - counts.get('initial_calendar', 0)
            
            if new_reminders > 0 or new_recalls > 0 or new_calendar > 0:
                feedback_parts.append(f"Note: Some entries added (reminders: +{new_reminders}, recalls: +{new_recalls}, calendar: +{new_calendar})")
            else:
                feedback_parts.append("No entries added to any recall-related tables")
            
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }
        
        # CRITERION 2: Correct patient (20 points)
        if patient_pid == expected_pid:
            score += score_correct_patient
            subscores["correct_patient"] = True
            feedback_parts.append(f"✅ Correct patient (pid={expected_pid}, {expected_fname} {expected_lname})")
        else:
            feedback_parts.append(f"❌ Wrong patient: expected pid={expected_pid}, got {patient_pid}")
            # Critical failure - wrong patient means task fundamentally failed
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }
        
        # CRITERION 3: Future date in valid range (20 points)
        recall_date_str = recall.get('date', '')
        if recall_date_str:
            try:
                recall_date = datetime.strptime(recall_date_str, '%Y-%m-%d').date()
                today = datetime.now().date()
                days_ahead = (recall_date - today).days
                
                if recall_days_min <= days_ahead <= recall_days_max:
                    score += score_future_date
                    subscores["future_date_valid"] = True
                    feedback_parts.append(f"✅ Recall date valid: {recall_date_str} ({days_ahead} days ahead)")
                elif days_ahead > 0:
                    # Give partial credit for any future date
                    partial_score = score_future_date // 2
                    score += partial_score
                    feedback_parts.append(f"⚠️ Recall date {recall_date_str} is {days_ahead} days ahead (expected {recall_days_min}-{recall_days_max} days)")
                else:
                    feedback_parts.append(f"❌ Recall date {recall_date_str} is not in the future")
            except ValueError as e:
                feedback_parts.append(f"⚠️ Could not parse recall date: {recall_date_str}")
        else:
            # Check validation data as fallback
            if validation.get('date_valid', False):
                score += score_future_date
                subscores["future_date_valid"] = True
                feedback_parts.append("✅ Recall date validated (from export)")
            else:
                feedback_parts.append("❌ No valid recall date found")
        
        # CRITERION 4: Reason mentions wellness/annual (15 points)
        recall_reason = recall.get('reason', '').lower()
        if recall_reason:
            keywords_found = [kw for kw in reason_keywords if kw.lower() in recall_reason]
            if keywords_found:
                score += score_reason_documented
                subscores["reason_documented"] = True
                feedback_parts.append(f"✅ Reason contains keywords: {', '.join(keywords_found)}")
            else:
                # Give partial credit if reason is documented but doesn't match keywords
                partial_score = score_reason_documented // 2
                score += partial_score
                feedback_parts.append(f"⚠️ Reason documented but missing expected keywords: '{recall_reason[:50]}'")
        else:
            # Check validation data as fallback
            if validation.get('reason_valid', False):
                score += score_reason_documented
                subscores["reason_documented"] = True
                feedback_parts.append("✅ Reason validated (from export)")
            else:
                feedback_parts.append("❌ No recall reason documented")
        
        # CRITERION 5: Created during task (10 points) - anti-gaming check
        # Check if counts increased during task execution
        new_entries = False
        if recall_source == 'patient_reminders':
            new_entries = counts.get('current_reminders', 0) > counts.get('initial_reminders', 0)
        elif recall_source == 'patient_recall':
            new_entries = counts.get('current_recalls', 0) > counts.get('initial_recalls', 0)
        elif recall_source == 'calendar':
            new_entries = counts.get('current_calendar', 0) > counts.get('initial_calendar', 0)
        
        if new_entries:
            score += score_created_during_task
            subscores["created_during_task"] = True
            feedback_parts.append("✅ Entry created during task execution")
        else:
            feedback_parts.append("⚠️ Could not verify entry was created during task (may be pre-existing)")
        
        # CRITERION 6: Provider assigned (5 points)
        provider = recall.get('provider', '')
        if provider and provider.strip() and provider.lower() not in ['null', 'none', '']:
            score += score_provider_assigned
            subscores["provider_assigned"] = True
            feedback_parts.append(f"✅ Provider assigned: {provider}")
        else:
            feedback_parts.append("⚠️ No provider explicitly assigned")
        
        # Determine pass/fail
        # Must have recall exists AND correct patient to pass
        key_criteria_met = subscores["recall_exists"] and subscores["correct_patient"]
        passed = score >= 70 and key_criteria_met
        
        # Add summary
        feedback_parts.insert(0, f"Score: {score}/100")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "recall_source": recall_source,
                "recall_date": recall.get('date', ''),
                "recall_reason": recall.get('reason', '')[:100] if recall.get('reason') else '',
                "counts": counts
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
            "feedback": f"Failed to parse result JSON: {str(e)}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def verify_with_vlm_fallback(traj, env_info, task_info):
    """
    Extended verification that includes VLM-based trajectory analysis.
    Falls back to VLM if database verification is inconclusive.
    """
    # First try database verification
    db_result = verify_create_patient_recall(traj, env_info, task_info)
    
    # If database verification passed or has reasonable score, return it
    if db_result.get('passed', False) or db_result.get('score', 0) >= 50:
        return db_result
    
    # Try VLM verification as fallback
    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        return db_result
    
    try:
        # Import trajectory sampling utility
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        # Sample frames from trajectory to verify workflow
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        
        if not frames and not final:
            return db_result
        
        # Use all available frames
        all_frames = frames + ([final] if final else [])
        
        vlm_prompt = """You are verifying if a computer agent successfully created a patient recall entry in OpenEMR.

TASK: Create a recall entry for patient Jayson Fadel for an Annual Wellness Exam, scheduled approximately 6 months in the future.

Look at these screenshots from the task execution and determine:
1. Did the agent navigate to a recall/reminder module in OpenEMR?
2. Did the agent search for or select patient Jayson Fadel?
3. Did the agent fill out a recall form with:
   - A reason mentioning wellness exam or similar
   - A future date approximately 6 months out
4. Did the agent save/submit the recall entry?
5. Is there a success message or confirmation visible?

Respond in JSON format:
{
    "navigated_to_recall_module": true/false,
    "patient_selected": true/false,
    "form_filled": true/false,
    "entry_saved": true/false,
    "success_confirmation_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation of what you observed in the workflow"
}
"""
        
        vlm_result = query_vlm(
            prompt=vlm_prompt,
            images=all_frames
        )
        
        if not vlm_result.get('success', False):
            return db_result
        
        parsed = vlm_result.get('parsed', {})
        
        # Calculate VLM-based score bonus
        vlm_score_bonus = 0
        vlm_feedback_parts = []
        
        if parsed.get('navigated_to_recall_module', False):
            vlm_score_bonus += 10
            vlm_feedback_parts.append("VLM: Recall module navigation detected")
        
        if parsed.get('patient_selected', False):
            vlm_score_bonus += 10
            vlm_feedback_parts.append("VLM: Patient selection detected")
        
        if parsed.get('form_filled', False):
            vlm_score_bonus += 10
            vlm_feedback_parts.append("VLM: Form completion detected")
        
        if parsed.get('entry_saved', False) or parsed.get('success_confirmation_visible', False):
            vlm_score_bonus += 10
            vlm_feedback_parts.append("VLM: Save/confirmation detected")
        
        # Combine scores (cap at 100)
        combined_score = min(100, db_result.get('score', 0) + vlm_score_bonus)
        
        # Update result with VLM findings
        combined_feedback = db_result.get('feedback', '') + " | " + " | ".join(vlm_feedback_parts)
        
        # Re-evaluate pass criteria with VLM boost
        passed = combined_score >= 70
        
        return {
            "passed": passed,
            "score": combined_score,
            "feedback": combined_feedback,
            "subscores": db_result.get('subscores', {}),
            "vlm_analysis": parsed,
            "details": db_result.get('details', {})
        }
        
    except Exception as e:
        logger.warning(f"VLM fallback failed: {e}")
        return db_result