#!/usr/bin/env python3
"""
Verifier for Assign Patient Price Level task in OpenEMR

This task verifies that the agent successfully changed a patient's price level
from "Standard" to "Sliding 1" for sliding fee schedule purposes.

Verification Strategy:
1. PRIMARY: Database query to verify price level field was changed
2. SECONDARY: Timestamp check to ensure record was modified during task
3. TERTIARY: VLM verification of trajectory to confirm workflow

Anti-Gaming Measures:
- Timestamp validation ensures change happened during task execution
- Correct patient validation (pid=5, Alesha Harber)
- Exact value match required for full points
"""

import sys
import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_assign_price_level(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that the patient's price level was correctly updated.
    
    Scoring (100 points total):
    - Patient record found and accessible: 20 points
    - Price level was changed from initial value: 40 points
    - Correct price level "Sliding 1" set: 25 points
    - Record modification timestamp updated: 10 points
    - VLM confirms demographics form visible: 5 points
    
    Pass threshold: 75 points (must have price_level_changed + correct_price_level)
    
    Args:
        traj: Trajectory data with frames and episode info
        env_info: Environment info with copy_from_env function
        task_info: Task metadata including expected values
        
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
    expected_pid = metadata.get('patient_pid', 5)
    expected_fname = metadata.get('patient_fname', 'Alesha')
    expected_lname = metadata.get('patient_lname', 'Harber')
    initial_price_level = metadata.get('initial_price_level', 'Standard')
    expected_price_level = metadata.get('expected_price_level', 'Sliding 1')
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    subscores = {
        "patient_found": False,
        "price_level_changed": False,
        "correct_price_level": False,
        "record_saved": False,
        "visual_confirmation": False
    }
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/price_level_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        patient_found = result.get('patient_found', False)
        patient_info = result.get('patient', {})
        price_level_info = result.get('price_level', {})
        validation = result.get('validation', {})
        timestamps = result.get('timestamps', {})
        
        logger.info(f"Result data: pid={patient_pid}, found={patient_found}")
        logger.info(f"Price level info: {price_level_info}")
        logger.info(f"Validation: {validation}")
        
        # CRITERION 1: Patient found and correct (20 points)
        if patient_found:
            fname = patient_info.get('fname', '').strip()
            lname = patient_info.get('lname', '').strip()
            
            if patient_pid == expected_pid:
                if fname.lower() == expected_fname.lower() and lname.lower() == expected_lname.lower():
                    score += 20
                    subscores["patient_found"] = True
                    feedback_parts.append(f"✅ Correct patient found: {fname} {lname} (pid={patient_pid})")
                else:
                    # Partial credit - right pid but name mismatch (data issue)
                    score += 15
                    subscores["patient_found"] = True
                    feedback_parts.append(f"⚠️ Patient pid={patient_pid} found, name: {fname} {lname}")
            else:
                feedback_parts.append(f"❌ Wrong patient! Expected pid={expected_pid}, got {patient_pid}")
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": f"Wrong patient modified (expected pid={expected_pid})",
                    "subscores": subscores
                }
        else:
            feedback_parts.append(f"❌ Patient pid={expected_pid} not found in database")
            return {
                "passed": False,
                "score": 0,
                "feedback": "Patient record not found",
                "subscores": subscores
            }
        
        # CRITERION 2: Price level was changed (40 points)
        current_price_level = price_level_info.get('current', '')
        initial_level = price_level_info.get('initial', initial_price_level)
        
        if validation.get('price_level_changed', False):
            score += 40
            subscores["price_level_changed"] = True
            feedback_parts.append(f"✅ Price level changed from '{initial_level}' to '{current_price_level}'")
        else:
            feedback_parts.append(f"❌ Price level not changed (still '{current_price_level}')")
        
        # CRITERION 3: Correct price level set (25 points)
        # Normalize for comparison (handle case/spacing variations)
        normalized_current = current_price_level.lower().replace(' ', '').strip()
        normalized_expected = expected_price_level.lower().replace(' ', '').strip()
        
        if validation.get('correct_price_level', False) or normalized_current == normalized_expected:
            score += 25
            subscores["correct_price_level"] = True
            feedback_parts.append(f"✅ Correct price level '{expected_price_level}' set")
        elif subscores["price_level_changed"]:
            # Changed to wrong value - partial credit for the effort
            score += 5
            feedback_parts.append(f"⚠️ Price level changed but to '{current_price_level}', expected '{expected_price_level}'")
        else:
            feedback_parts.append(f"❌ Price level is '{current_price_level}', expected '{expected_price_level}'")
        
        # CRITERION 4: Record was saved/modified during task (10 points)
        task_start = timestamps.get('task_start', 0)
        current_mod_time = timestamps.get('current_mod_time', 0)
        
        if validation.get('record_modified_during_task', False):
            score += 10
            subscores["record_saved"] = True
            feedback_parts.append("✅ Record modification timestamp updated during task")
        elif validation.get('record_updated', False):
            # Record was updated but timestamp check failed (timezone issue?)
            score += 5
            subscores["record_saved"] = True
            feedback_parts.append("⚠️ Record was updated (timestamp comparison inconclusive)")
        elif subscores["price_level_changed"]:
            # Price level changed but timestamp not updated (form quirk)
            score += 5
            feedback_parts.append("⚠️ Price level changed but modification time not updated")
        
        # CRITERION 5: VLM visual confirmation (5 points)
        # Check trajectory for evidence of demographics form interaction
        vlm_score = verify_workflow_via_trajectory(traj, env_info)
        if vlm_score > 0:
            score += vlm_score
            subscores["visual_confirmation"] = True
            feedback_parts.append("✅ Visual confirmation: demographics form workflow detected")
        else:
            feedback_parts.append("⚠️ Could not visually confirm demographics form interaction")
        
        # Determine pass/fail
        # Must have at least changed to the correct value
        key_criteria_met = subscores["price_level_changed"] and subscores["correct_price_level"]
        passed = score >= 75 and key_criteria_met
        
        # Build final feedback
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": feedback,
            "subscores": subscores,
            "details": {
                "expected_price_level": expected_price_level,
                "actual_price_level": current_price_level,
                "patient_pid": patient_pid
            }
        }
        
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export may have failed",
            "subscores": subscores
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid result JSON: {e}",
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


def verify_workflow_via_trajectory(traj: Dict[str, Any], env_info: Dict[str, Any]) -> int:
    """
    Use VLM to verify the agent followed the correct workflow.
    
    Checks trajectory frames (not just final screenshot) for evidence of:
    - Patient search
    - Demographics form open
    - Price level field interaction
    
    Args:
        traj: Trajectory with frames
        env_info: Environment info with query_vlm function
        
    Returns:
        int: Points earned (0-5)
    """
    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        logger.warning("VLM query function not available")
        return 0
    
    try:
        # Try to import trajectory frame sampling
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=5)
            final_frame = get_final_screenshot(traj)
            if final_frame:
                frames.append(final_frame)
        except ImportError:
            # Fallback: try to get frames from trajectory directly
            frames = []
            if 'frames' in traj:
                all_frames = traj['frames']
                if len(all_frames) > 0:
                    # Sample evenly across trajectory
                    indices = [0, len(all_frames)//4, len(all_frames)//2, 3*len(all_frames)//4, -1]
                    frames = [all_frames[i] for i in indices if i < len(all_frames)]
        
        if not frames:
            logger.warning("No trajectory frames available for VLM verification")
            return 0
        
        # VLM prompt to verify workflow
        vlm_prompt = """Analyze these screenshots from an OpenEMR (Electronic Health Record) session.

Look for evidence that the user:
1. Searched for or selected a patient
2. Opened a patient demographics form
3. Interacted with form fields (especially dropdown menus)
4. Saved or submitted form changes

Key visual elements to look for:
- Patient name visible (e.g., "Alesha Harber")
- Demographics or patient edit form
- Form fields and dropdown menus
- "Price Level" or similar financial fields
- Save/Update buttons

Respond in JSON format:
{
    "patient_search_visible": true/false,
    "demographics_form_visible": true/false,
    "form_fields_visible": true/false,
    "workflow_consistent": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}
"""
        
        # Query VLM with trajectory frames
        vlm_result = query_vlm(
            prompt=vlm_prompt,
            images=frames
        )
        
        if not vlm_result.get('success', False):
            logger.warning(f"VLM query failed: {vlm_result.get('error', 'Unknown error')}")
            return 0
        
        parsed = vlm_result.get('parsed', {})
        
        # Score based on VLM findings
        evidence_count = sum([
            parsed.get('patient_search_visible', False),
            parsed.get('demographics_form_visible', False),
            parsed.get('form_fields_visible', False),
            parsed.get('workflow_consistent', False)
        ])
        
        confidence = parsed.get('confidence', 'low')
        
        if evidence_count >= 3 and confidence in ['medium', 'high']:
            return 5
        elif evidence_count >= 2:
            return 3
        elif evidence_count >= 1:
            return 1
        
        return 0
        
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        return 0


# For direct testing
if __name__ == "__main__":
    # Test with mock data
    test_result = {
        "patient_pid": 5,
        "patient_found": True,
        "patient": {"fname": "Alesha", "lname": "Harber", "dob": "2014-03-14"},
        "price_level": {
            "initial": "Standard",
            "current": "Sliding 1",
            "expected": "Sliding 1"
        },
        "validation": {
            "price_level_changed": True,
            "correct_price_level": True,
            "record_modified_during_task": True,
            "record_updated": True
        },
        "timestamps": {
            "task_start": 1700000000,
            "task_end": 1700000180,
            "initial_mod_time": 1699999000,
            "current_mod_time": 1700000100
        }
    }
    
    print("Test result structure:")
    print(json.dumps(test_result, indent=2))