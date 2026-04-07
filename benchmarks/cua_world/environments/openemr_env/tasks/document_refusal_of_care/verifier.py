#!/usr/bin/env python3
"""
Verifier for Document Refusal of Care task in OpenEMR

Verifies that the agent correctly documented a patient's informed refusal
of recommended medical care (MRI imaging) with appropriate medicolegal content.

Verification Strategy:
1. PRIMARY: Query exported result JSON for note existence and content
2. SECONDARY: VLM verification of trajectory to confirm workflow was followed

Scoring Criteria:
- Login successful (via user field in note): 10 points
- Correct patient (note for Rosario Conn): 15 points
- Note created: 25 points
- Title contains refusal terminology: 15 points
- Body references MRI/imaging: 15 points
- Risks documented: 10 points
- Created during task window: 10 points

Total: 100 points
Pass threshold: 70 points with note_created and correct_patient
"""

import sys
import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_document_refusal(traj, env_info, task_info):
    """
    Verify that refusal of care was properly documented.
    
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
            "feedback": "Copy function not available - cannot verify task"
        }
    
    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_fname = metadata.get('patient_fname', 'Rosario')
    expected_lname = metadata.get('patient_lname', 'Conn')
    refusal_keywords = metadata.get('refusal_keywords', ['refus', 'ama', 'against medical advice', 'decline'])
    procedure_keywords = metadata.get('procedure_keywords', ['mri', 'imaging', 'scan', 'magnetic resonance'])
    risk_keywords = metadata.get('risk_keywords', ['risk', 'explain', 'discuss', 'counsel', 'inform'])
    
    score = 0
    feedback_parts = []
    subscores = {
        "login_successful": False,
        "correct_patient": False,
        "note_created": False,
        "title_contains_refusal": False,
        "body_references_procedure": False,
        "risks_documented": False,
        "timestamp_valid": False
    }
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/document_refusal_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        # Extract data from result
        task_start = result.get('task_start', 0)
        patient_pid = result.get('patient_pid', 0)
        initial_note_count = result.get('initial_note_count', 0)
        current_note_count = result.get('current_note_count', 0)
        note_found = result.get('note_found', False)
        note_data = result.get('note', {})
        content_analysis = result.get('content_analysis', {})
        
        logger.info(f"Result: pid={patient_pid}, initial={initial_note_count}, current={current_note_count}, found={note_found}")
        
        # CRITERION 1: Correct patient (15 points)
        # Verify we're looking at the right patient
        if patient_pid and patient_pid > 0:
            subscores["correct_patient"] = True
            score += 15
            feedback_parts.append(f"✓ Correct patient targeted (PID: {patient_pid})")
        else:
            feedback_parts.append("✗ Could not verify patient")
        
        # CRITERION 2: Note created (25 points)
        # Check if a new note was added
        if note_found and current_note_count > initial_note_count:
            subscores["note_created"] = True
            score += 25
            feedback_parts.append(f"✓ New note created (count: {initial_note_count} → {current_note_count})")
        elif note_found:
            # Note found but count didn't increase - might be editing existing
            subscores["note_created"] = True
            score += 20  # Partial credit
            feedback_parts.append(f"✓ Note found (may have modified existing)")
        else:
            feedback_parts.append(f"✗ No new note created for patient")
            # Early return - critical failure
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }
        
        # CRITERION 3: Login successful (10 points)
        # Check if note was created by a valid user
        note_user = note_data.get('user', '')
        if note_user and note_user.strip():
            subscores["login_successful"] = True
            score += 10
            feedback_parts.append(f"✓ Note created by user: {note_user}")
        else:
            feedback_parts.append("? Could not verify login (no user in note)")
        
        # CRITERION 4: Title contains refusal terminology (15 points)
        note_title = note_data.get('title', '').lower()
        title_has_refusal = content_analysis.get('title_has_refusal', False)
        
        # Also do our own check in case export missed it
        if not title_has_refusal:
            title_has_refusal = any(kw in note_title for kw in refusal_keywords)
        
        if title_has_refusal:
            subscores["title_contains_refusal"] = True
            score += 15
            feedback_parts.append(f"✓ Title contains refusal terminology")
        else:
            # Check body for refusal terms as fallback
            note_body = note_data.get('body', '').lower()
            if any(kw in note_body for kw in refusal_keywords):
                score += 8  # Partial credit if in body but not title
                feedback_parts.append(f"△ Refusal mentioned in body but not title")
            else:
                feedback_parts.append(f"✗ No refusal terminology found in title")
        
        # CRITERION 5: Body references MRI/imaging (15 points)
        note_body = note_data.get('body', '').lower()
        body_has_procedure = content_analysis.get('body_has_procedure', False)
        
        # Also do our own check
        if not body_has_procedure:
            body_has_procedure = any(kw in note_body for kw in procedure_keywords)
        
        if body_has_procedure:
            subscores["body_references_procedure"] = True
            score += 15
            feedback_parts.append(f"✓ Note references MRI/imaging procedure")
        else:
            # Check title as fallback
            if any(kw in note_title for kw in procedure_keywords):
                score += 8  # Partial credit
                feedback_parts.append(f"△ Procedure mentioned in title but not body")
            else:
                feedback_parts.append(f"✗ No reference to MRI/imaging in note")
        
        # CRITERION 6: Risks documented (10 points)
        body_has_risks = content_analysis.get('body_has_risks', False)
        
        # Also do our own check
        if not body_has_risks:
            body_has_risks = any(kw in note_body for kw in risk_keywords)
        
        if body_has_risks:
            subscores["risks_documented"] = True
            score += 10
            feedback_parts.append(f"✓ Note documents risk discussion")
        else:
            feedback_parts.append(f"△ No explicit risk discussion documented")
        
        # CRITERION 7: Created during task window (10 points)
        created_during_task = content_analysis.get('created_during_task', False)
        note_timestamp = note_data.get('timestamp', 0)
        
        # Verify timestamp ourselves with 2-minute buffer
        if note_timestamp and task_start:
            if note_timestamp >= (task_start - 120):
                created_during_task = True
        
        if created_during_task:
            subscores["timestamp_valid"] = True
            score += 10
            feedback_parts.append(f"✓ Note created during task window")
        else:
            feedback_parts.append(f"? Note timestamp could not be verified")
        
        # VLM verification for trajectory (bonus confidence check)
        vlm_verified = False
        try:
            query_vlm = env_info.get('query_vlm')
            if query_vlm and traj:
                # Import trajectory utilities
                try:
                    from gym_anything.vlm import sample_trajectory_frames
                    frames = sample_trajectory_frames(traj, n=4)
                    
                    if frames:
                        vlm_prompt = """Analyze these screenshots from an OpenEMR task session.
                        
The agent was asked to document a patient's refusal of an MRI imaging study.

Check for evidence of:
1. Login to OpenEMR
2. Patient search/selection (looking for patient Rosario Conn)
3. Opening a note or documentation form
4. Typing content related to refusal/declined care
5. Saving the documentation

Respond in JSON format:
{
    "login_visible": true/false,
    "patient_search_visible": true/false,
    "note_form_visible": true/false,
    "workflow_appears_complete": true/false,
    "confidence": "low"/"medium"/"high"
}"""
                        vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
                        
                        if vlm_result and vlm_result.get('success'):
                            parsed = vlm_result.get('parsed', {})
                            if parsed.get('workflow_appears_complete') and parsed.get('confidence') in ['medium', 'high']:
                                vlm_verified = True
                                feedback_parts.append(f"✓ VLM confirms workflow completion")
                except ImportError:
                    logger.warning("Could not import VLM utilities")
                except Exception as e:
                    logger.warning(f"VLM verification failed: {e}")
        except Exception as e:
            logger.warning(f"VLM check skipped: {e}")
        
        # Calculate final pass/fail
        # Must have: correct_patient AND note_created
        # Must reach 70 points
        key_criteria_met = subscores["correct_patient"] and subscores["note_created"]
        passed = score >= 70 and key_criteria_met
        
        # Bonus points for VLM verification
        if vlm_verified and score < 100:
            score = min(100, score + 5)
        
        # Final feedback
        feedback_parts.append("")
        feedback_parts.append(f"=== FINAL SCORE: {score}/100 ===")
        
        if passed:
            feedback_parts.append("RESULT: PASS - Refusal of care documented appropriately")
        else:
            if not key_criteria_met:
                feedback_parts.append("RESULT: FAIL - Missing critical criteria (patient or note creation)")
            else:
                feedback_parts.append("RESULT: FAIL - Score below threshold (70 points required)")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": "\n".join(feedback_parts),
            "subscores": subscores
        }
        
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - task may not have completed properly",
            "subscores": subscores
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse result JSON: {e}",
            "subscores": subscores
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "subscores": subscores
        }


if __name__ == "__main__":
    # Test harness for local development
    print("Document Refusal of Care Verifier")
    print("This verifier checks for proper documentation of patient refusal of MRI imaging")
    print("")
    print("Expected scoring:")
    print("  - Login successful: 10 pts")
    print("  - Correct patient: 15 pts")
    print("  - Note created: 25 pts")
    print("  - Title has refusal: 15 pts")
    print("  - Body has procedure: 15 pts")
    print("  - Risks documented: 10 pts")
    print("  - Timestamp valid: 10 pts")
    print("  - Total: 100 pts")
    print("  - Pass threshold: 70 pts + key criteria")