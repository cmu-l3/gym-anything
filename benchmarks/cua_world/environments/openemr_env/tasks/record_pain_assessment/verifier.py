#!/usr/bin/env python3
"""
Verifier for Record Pain Assessment task in OpenEMR

Verifies that a pain assessment was properly documented for the target patient.
Uses copy_from_env to read pre-exported verification data from the container.

Scoring criteria:
- Correct patient selected: 20 points
- Encounter created/opened: 15 points
- Pain score recorded: 25 points
- Pain score is correct (7): 15 points
- Location documented: 15 points
- Recent timestamp: 10 points

Total: 100 points
Pass threshold: 60 points with pain_score_recorded criterion met
"""

import sys
import os
import json
import logging
import tempfile
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_pain_assessment(traj, env_info, task_info):
    """
    Verify that a pain assessment was correctly documented.
    
    Args:
        traj: Trajectory data with frames, steps, episode_dir
        env_info: Environment info with copy_from_env function
        task_info: Task info with metadata
        
    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
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
    expected_fname = metadata.get('patient_fname', 'Isabella')
    expected_lname = metadata.get('patient_lname', 'Gonzalez')
    expected_pain_score = metadata.get('expected_pain_score', '7')
    expected_location = metadata.get('expected_location', 'lower back')
    
    # Get score weights from metadata
    weights = metadata.get('score_weights', {
        'correct_patient': 20,
        'encounter_created': 15,
        'pain_score_recorded': 25,
        'pain_score_correct': 15,
        'location_documented': 15,
        'recent_timestamp': 10
    })
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/pain_assessment_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        score = 0
        feedback_parts = []
        subscores = {
            "correct_patient": False,
            "encounter_created": False,
            "pain_score_recorded": False,
            "pain_score_correct": False,
            "location_documented": False,
            "recent_timestamp": False
        }
        
        # Extract data from result
        task_start = result.get('task_start', 0)
        task_end = result.get('task_end', 0)
        patient = result.get('patient', {})
        initial_vitals = result.get('initial_vitals_count', 0)
        current_vitals = result.get('current_vitals_count', 0)
        initial_encounters = result.get('initial_encounter_count', 0)
        current_encounters = result.get('current_encounter_count', 0)
        new_vitals_found = result.get('new_vitals_found', False)
        new_encounter_found = result.get('new_encounter_found', False)
        vitals = result.get('vitals', {})
        validation = result.get('validation', {})
        
        logger.info(f"Result data: new_vitals={new_vitals_found}, new_encounter={new_encounter_found}")
        logger.info(f"Vitals: {vitals}")
        logger.info(f"Patient: {patient}")
        
        # CRITERION 1: Correct patient (20 points)
        patient_fname = patient.get('fname', '').lower()
        patient_lname = patient.get('lname', '').lower()
        
        if expected_fname.lower() in patient_fname or patient_fname in expected_fname.lower():
            if expected_lname.lower() in patient_lname or patient_lname in expected_lname.lower():
                score += weights['correct_patient']
                subscores["correct_patient"] = True
                feedback_parts.append(f"✅ Correct patient: {patient.get('fname', '')} {patient.get('lname', '')}")
            else:
                feedback_parts.append(f"⚠️ Patient last name mismatch: expected '{expected_lname}', got '{patient.get('lname', '')}'")
        else:
            feedback_parts.append(f"❌ Wrong patient: expected '{expected_fname} {expected_lname}', got '{patient.get('fname', '')} {patient.get('lname', '')}'")
        
        # CRITERION 2: Encounter created/opened (15 points)
        if new_encounter_found or new_vitals_found:
            score += weights['encounter_created']
            subscores["encounter_created"] = True
            if new_encounter_found:
                feedback_parts.append("✅ New encounter created")
            else:
                feedback_parts.append("✅ Vitals added to existing encounter")
        else:
            # Check if vitals entry has an encounter ID
            encounter_id = vitals.get('encounter_id', '')
            if encounter_id and encounter_id != '' and encounter_id != '0':
                score += weights['encounter_created']
                subscores["encounter_created"] = True
                feedback_parts.append(f"✅ Encounter context found (ID: {encounter_id})")
            else:
                feedback_parts.append("❌ No encounter created or accessed")
        
        # CRITERION 3: Pain score recorded (25 points)
        pain_score = vitals.get('pain_score', '')
        
        if pain_score and pain_score.strip() != '':
            score += weights['pain_score_recorded']
            subscores["pain_score_recorded"] = True
            feedback_parts.append(f"✅ Pain score recorded: {pain_score}")
        else:
            feedback_parts.append("❌ No pain score recorded")
        
        # CRITERION 4: Pain score is correct value (15 points)
        if pain_score == expected_pain_score:
            score += weights['pain_score_correct']
            subscores["pain_score_correct"] = True
            feedback_parts.append(f"✅ Pain score correct: {expected_pain_score}/10")
        elif pain_score:
            # Partial credit for any pain score
            partial_credit = weights['pain_score_correct'] // 2
            score += partial_credit
            feedback_parts.append(f"⚠️ Pain score incorrect: expected {expected_pain_score}, got {pain_score} (+{partial_credit} partial)")
        else:
            feedback_parts.append(f"❌ Pain score not set (expected {expected_pain_score})")
        
        # CRITERION 5: Location documented (15 points)
        location_documented = validation.get('location_documented', False)
        vitals_note = vitals.get('note', '')
        
        if location_documented:
            score += weights['location_documented']
            subscores["location_documented"] = True
            feedback_parts.append("✅ Pain location documented in notes")
        elif vitals_note and len(vitals_note.strip()) > 5:
            # Partial credit for any notes
            partial_credit = weights['location_documented'] // 2
            score += partial_credit
            feedback_parts.append(f"⚠️ Notes present but location unclear (+{partial_credit} partial)")
        else:
            feedback_parts.append(f"❌ Pain location not documented (expected: {expected_location})")
        
        # CRITERION 6: Recent timestamp (10 points) - anti-gaming check
        vitals_date = vitals.get('date', '')
        
        if vitals_date:
            try:
                # Try to parse various date formats
                vitals_epoch = None
                for fmt in ['%Y-%m-%d %H:%M:%S', '%Y-%m-%d', '%Y-%m-%dT%H:%M:%S']:
                    try:
                        vitals_dt = datetime.strptime(vitals_date.split('.')[0], fmt)
                        vitals_epoch = vitals_dt.timestamp()
                        break
                    except ValueError:
                        continue
                
                if vitals_epoch and vitals_epoch >= task_start:
                    score += weights['recent_timestamp']
                    subscores["recent_timestamp"] = True
                    feedback_parts.append("✅ Documentation created during task session")
                elif current_vitals > initial_vitals:
                    # New vitals record exists even if timestamp check fails
                    score += weights['recent_timestamp']
                    subscores["recent_timestamp"] = True
                    feedback_parts.append("✅ New vitals record confirmed (count increased)")
                else:
                    feedback_parts.append(f"⚠️ Unable to verify timestamp (date: {vitals_date})")
            except Exception as e:
                logger.warning(f"Timestamp parsing error: {e}")
                # Give benefit of doubt if new records were created
                if current_vitals > initial_vitals:
                    score += weights['recent_timestamp']
                    subscores["recent_timestamp"] = True
                    feedback_parts.append("✅ New vitals record detected")
                else:
                    feedback_parts.append(f"⚠️ Could not verify timestamp: {vitals_date}")
        elif current_vitals > initial_vitals:
            score += weights['recent_timestamp']
            subscores["recent_timestamp"] = True
            feedback_parts.append("✅ New vitals record created")
        else:
            feedback_parts.append("❌ No new documentation detected")
        
        # Determine pass/fail
        # Must have pain_score_recorded criterion met plus score >= 60
        key_criteria_met = subscores["pain_score_recorded"]
        passed = score >= 60 and key_criteria_met
        
        # Add summary
        if passed:
            feedback_parts.insert(0, f"✅ PASSED with score {score}/100")
        else:
            if not key_criteria_met:
                feedback_parts.insert(0, f"❌ FAILED - Pain score not recorded (score: {score}/100)")
            else:
                feedback_parts.insert(0, f"❌ FAILED - Score {score}/100 below threshold of 60")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "patient": patient,
                "pain_score": pain_score,
                "expected_pain_score": expected_pain_score,
                "vitals_note": vitals_note[:200] if vitals_note else "",
                "task_duration_sec": task_end - task_start if task_end and task_start else 0
            }
        }
        
    except FileNotFoundError:
        logger.error("Result file not found")
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Result file not found - export may have failed"
        }
    except json.JSONDecodeError as e:
        logger.error(f"JSON decode error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Failed to parse result JSON: {e}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }


def verify_with_vlm_fallback(traj, env_info, task_info):
    """
    Extended verification with VLM fallback for visual confirmation.
    
    Uses trajectory frames to verify the agent actually navigated through
    the pain assessment workflow.
    """
    # First run primary verification
    primary_result = verify_pain_assessment(traj, env_info, task_info)
    
    # If primary verification passed with high confidence, return it
    if primary_result.get('passed') and primary_result.get('score', 0) >= 80:
        return primary_result
    
    # Attempt VLM verification as supplementary check
    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        return primary_result
    
    try:
        # Import trajectory frame sampling
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        # Sample frames across the trajectory
        frames = sample_trajectory_frames(traj, n=5)
        final_frame = get_final_screenshot(traj)
        
        if not frames and not final_frame:
            return primary_result
        
        # VLM prompt for pain assessment verification
        vlm_prompt = """You are verifying if a computer agent successfully documented a pain assessment in OpenEMR.

TASK: Record a pain score of 7 for a patient's lower back pain.

Look at these screenshots from the agent's session and determine:
1. Did the agent navigate to a patient's chart?
2. Did the agent access a Vitals form or similar clinical form?
3. Is there a pain score field visible with a value entered?
4. Did the form appear to be saved?

Respond in JSON format:
{
    "patient_chart_accessed": true/false,
    "vitals_form_opened": true/false,
    "pain_score_visible": true/false,
    "form_saved": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""
        
        all_frames = (frames or []) + ([final_frame] if final_frame else [])
        
        if all_frames:
            vlm_result = query_vlm(
                prompt=vlm_prompt,
                images=all_frames
            )
            
            if vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                
                # Adjust score based on VLM findings
                vlm_score_adjustment = 0
                vlm_feedback = []
                
                if parsed.get('patient_chart_accessed'):
                    vlm_score_adjustment += 5
                    vlm_feedback.append("VLM: Patient chart accessed")
                
                if parsed.get('vitals_form_opened'):
                    vlm_score_adjustment += 5
                    vlm_feedback.append("VLM: Vitals form opened")
                
                if parsed.get('pain_score_visible'):
                    vlm_score_adjustment += 5
                    vlm_feedback.append("VLM: Pain score visible")
                
                if parsed.get('form_saved'):
                    vlm_score_adjustment += 5
                    vlm_feedback.append("VLM: Form saved")
                
                # Update result with VLM findings
                if vlm_score_adjustment > 0:
                    new_score = min(100, primary_result.get('score', 0) + vlm_score_adjustment)
                    primary_result['score'] = new_score
                    primary_result['feedback'] += " | " + " | ".join(vlm_feedback)
                    
                    # Re-evaluate pass status
                    if new_score >= 60 and primary_result.get('subscores', {}).get('pain_score_recorded'):
                        primary_result['passed'] = True
                
                primary_result['vlm_verification'] = parsed
        
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
    
    return primary_result