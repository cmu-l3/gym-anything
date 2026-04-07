#!/usr/bin/env python3
"""
Verifier for Document PHQ-9 Screening task in OpenEMR

Verification Strategy:
1. Check if PHQ-9/depression screening documentation exists for correct patient
2. Verify score of 8 is documented
3. Verify "mild" interpretation is noted
4. Confirm documentation was created during task (not pre-existing)
5. Use VLM to verify agent navigated through appropriate workflow

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


def verify_phq9_screening(traj, env_info, task_info):
    """
    Verify that PHQ-9 depression screening was documented correctly.

    Scoring (100 points total):
    - Documentation exists for correct patient: 30 points
    - Score of 8 documented: 25 points
    - Correct patient (pid=3): 20 points
    - Newly created during task: 15 points
    - Mild interpretation noted: 10 points

    Passing threshold: 60 points (must have documentation + correct patient + score)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 3)
    expected_score = metadata.get('expected_score', 8)
    expected_interpretation = metadata.get('expected_interpretation', 'mild')
    
    scoring_weights = metadata.get('scoring_weights', {
        'documentation_exists': 30,
        'correct_patient': 20,
        'score_documented': 25,
        'newly_created': 15,
        'interpretation_noted': 10
    })

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/phq9_screening_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {
            "documentation_exists": False,
            "correct_patient": False,
            "score_documented": False,
            "newly_created": False,
            "interpretation_noted": False
        }

        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        documentation_found = result.get('documentation_found', False)
        documentation_type = result.get('documentation_type', '')
        newly_created = result.get('newly_created', False)
        phq_data = result.get('phq_data', {})
        
        initial_counts = result.get('initial_counts', {})
        current_counts = result.get('current_counts', {})
        
        score_8_found = phq_data.get('score_8_found', False)
        mild_found = phq_data.get('mild_interpretation_found', False)

        logger.info(f"Result data: pid={patient_pid}, doc_found={documentation_found}, type={documentation_type}")
        logger.info(f"PHQ data: score_8={score_8_found}, mild={mild_found}, newly_created={newly_created}")

        # CRITERION 1: Correct patient (20 points)
        if patient_pid == expected_pid:
            score += scoring_weights.get('correct_patient', 20)
            subscores["correct_patient"] = True
            feedback_parts.append(f"✅ Correct patient (pid={expected_pid}, Jayson Fadel)")
        else:
            feedback_parts.append(f"❌ Wrong patient: expected pid={expected_pid}, got {patient_pid}")
            # Critical failure - wrong patient
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Documentation was for wrong patient (expected pid={expected_pid})",
                "subscores": subscores
            }

        # CRITERION 2: Documentation exists (30 points)
        if documentation_found:
            score += scoring_weights.get('documentation_exists', 30)
            subscores["documentation_exists"] = True
            feedback_parts.append(f"✅ PHQ-9/depression screening documentation found (type: {documentation_type})")
        else:
            feedback_parts.append("❌ No PHQ-9 or depression screening documentation found")
            # Check if there was any new activity
            notes_added = current_counts.get('notes', 0) - initial_counts.get('notes', 0)
            forms_added = current_counts.get('forms', 0) - initial_counts.get('forms', 0)
            encounters_added = current_counts.get('encounters', 0) - initial_counts.get('encounters', 0)
            
            if notes_added > 0 or forms_added > 0 or encounters_added > 0:
                feedback_parts.append(f"Note: New entries were added (notes: +{notes_added}, forms: +{forms_added}, encounters: +{encounters_added}) but none contained PHQ-9/depression keywords")
            else:
                feedback_parts.append("No new clinical documentation was created")
            
            # Attempt VLM verification as fallback
            vlm_result = verify_via_vlm(traj, env_info)
            if vlm_result.get('documentation_visible', False):
                # Give partial credit if VLM sees documentation
                score += 15
                feedback_parts.append("⚠️ VLM detected possible documentation in screenshots (partial credit)")
            
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }

        # CRITERION 3: Score of 8 documented (25 points)
        if score_8_found:
            score += scoring_weights.get('score_documented', 25)
            subscores["score_documented"] = True
            feedback_parts.append(f"✅ PHQ-9 score of {expected_score} documented")
        else:
            feedback_parts.append(f"⚠️ Score of {expected_score} not clearly documented")
            # Give partial credit if documentation exists but score not found
            score += 10
            feedback_parts.append("(Partial credit: documentation exists but score not verified)")

        # CRITERION 4: Newly created during task (15 points)
        if newly_created:
            score += scoring_weights.get('newly_created', 15)
            subscores["newly_created"] = True
            feedback_parts.append("✅ Documentation was created during this task")
        else:
            feedback_parts.append("⚠️ Could not confirm documentation was newly created")
            # Check if any counts increased
            notes_diff = current_counts.get('notes', 0) - initial_counts.get('notes', 0)
            forms_diff = current_counts.get('forms', 0) - initial_counts.get('forms', 0)
            if notes_diff > 0 or forms_diff > 0:
                score += 8  # Partial credit
                subscores["newly_created"] = True
                feedback_parts.append(f"(Partial credit: new entries detected - notes: +{notes_diff}, forms: +{forms_diff})")

        # CRITERION 5: Mild interpretation noted (10 points)
        if mild_found:
            score += scoring_weights.get('interpretation_noted', 10)
            subscores["interpretation_noted"] = True
            feedback_parts.append(f"✅ '{expected_interpretation.capitalize()}' interpretation documented")
        else:
            feedback_parts.append(f"⚠️ '{expected_interpretation.capitalize()}' interpretation not found")

        # VLM verification for workflow validation
        vlm_result = verify_via_vlm(traj, env_info)
        if vlm_result.get('workflow_correct', False):
            feedback_parts.append("✅ VLM verified proper workflow through trajectory")
        
        # Determine pass/fail
        # Must have: correct patient + documentation exists + (score OR newly created)
        key_criteria_met = (
            subscores["correct_patient"] and 
            subscores["documentation_exists"] and 
            (subscores["score_documented"] or subscores["newly_created"])
        )
        
        passed = score >= 60 and key_criteria_met
        
        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "patient_pid": patient_pid,
                "documentation_type": documentation_type,
                "phq_data": phq_data,
                "counts_diff": {
                    "notes": current_counts.get('notes', 0) - initial_counts.get('notes', 0),
                    "forms": current_counts.get('forms', 0) - initial_counts.get('forms', 0),
                    "encounters": current_counts.get('encounters', 0) - initial_counts.get('encounters', 0)
                }
            }
        }

    except FileNotFoundError:
        logger.error("Result file not found - export may have failed")
        
        # Attempt VLM-only verification as fallback
        vlm_result = verify_via_vlm(traj, env_info)
        if vlm_result.get('documentation_visible', False):
            return {
                "passed": False,
                "score": 25,
                "feedback": "Export failed, but VLM detected possible documentation (partial credit)",
                "subscores": {"vlm_verification": True}
            }
        
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - task may not have completed properly"
        }
        
    except json.JSONDecodeError as e:
        logger.error(f"JSON decode error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse result file: {e}"
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def verify_via_vlm(traj, env_info):
    """
    Use VLM to verify workflow via trajectory screenshots.
    
    Checks:
    1. Agent navigated to patient chart
    2. Agent accessed clinical documentation area
    3. PHQ-9 or depression screening is visible
    4. Score appears to be documented
    """
    result = {
        "documentation_visible": False,
        "workflow_correct": False,
        "confidence": "low"
    }
    
    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        logger.warning("VLM query function not available")
        return result
    
    try:
        # Import trajectory utilities
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        # Sample frames from trajectory to verify workflow
        frames = sample_trajectory_frames(traj, n=5)
        final_screenshot = get_final_screenshot(traj)
        
        if not frames and not final_screenshot:
            logger.warning("No screenshots available for VLM verification")
            return result
        
        # Use all available frames for comprehensive verification
        all_frames = frames + ([final_screenshot] if final_screenshot else [])
        
        vlm_prompt = """You are verifying if a computer agent successfully documented a PHQ-9 depression screening in OpenEMR.

TASK: Document a PHQ-9 depression screening with score of 8 (mild depression) for patient Jayson Fadel.

Examine these screenshots from the agent's workflow and determine:

1. Did the agent navigate to a patient chart (patient name visible, clinical tabs/sections visible)?
2. Did the agent access a documentation area (notes, forms, encounters, assessments)?
3. Is there evidence of PHQ-9 or depression screening being documented?
4. Can you see the score "8" or "mild" anywhere in the documentation?
5. Does the workflow show the agent creating new documentation (not just viewing)?

Look for:
- Patient name "Jayson Fadel" 
- Clinical documentation interfaces
- Form entry or note creation screens
- PHQ, PHQ-9, depression, screening keywords
- Numbers indicating scores
- Save/submit buttons being used

Respond in JSON format:
{
    "patient_chart_accessed": true/false,
    "documentation_area_accessed": true/false,
    "phq9_visible": true/false,
    "score_visible": true/false,
    "documentation_created": true/false,
    "workflow_appears_complete": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation of what you observed in the workflow"
}
"""
        
        vlm_response = query_vlm(
            prompt=vlm_prompt,
            images=all_frames
        )
        
        if vlm_response.get('success'):
            parsed = vlm_response.get('parsed', {})
            
            # Evaluate VLM response
            doc_visible = (
                parsed.get('phq9_visible', False) or 
                parsed.get('documentation_created', False) or
                parsed.get('score_visible', False)
            )
            
            workflow_correct = (
                parsed.get('patient_chart_accessed', False) and
                parsed.get('documentation_area_accessed', False) and
                parsed.get('workflow_appears_complete', False)
            )
            
            result["documentation_visible"] = doc_visible
            result["workflow_correct"] = workflow_correct
            result["confidence"] = parsed.get('confidence', 'low')
            result["vlm_details"] = parsed
            
            logger.info(f"VLM verification: doc_visible={doc_visible}, workflow={workflow_correct}")
            
    except ImportError:
        logger.warning("gym_anything.vlm not available for trajectory verification")
    except Exception as e:
        logger.error(f"VLM verification error: {e}")
    
    return result


# Allow running as standalone script for testing
if __name__ == "__main__":
    # Test with mock data
    mock_traj = {"frames": [], "steps": []}
    mock_env_info = {"copy_from_env": None}
    mock_task_info = {"metadata": {"patient_pid": 3, "expected_score": 8}}
    
    result = verify_phq9_screening(mock_traj, mock_env_info, mock_task_info)
    print(json.dumps(result, indent=2))