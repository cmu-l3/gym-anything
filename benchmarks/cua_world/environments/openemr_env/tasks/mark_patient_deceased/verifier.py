#!/usr/bin/env python3
"""
Verifier for Mark Patient as Deceased task in OpenEMR

Verification Strategy:
1. Query database via exported JSON to verify deceased_date was set
2. Verify the correct date (2024-03-15) was entered
3. Confirm record was modified during task execution (anti-gaming)
4. Use VLM on trajectory to verify demographics workflow was followed

Uses copy_from_env to read pre-exported verification data from the container.
"""

import sys
import os
import json
import logging
import tempfile
from typing import Dict, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_mark_deceased(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that patient was correctly marked as deceased.
    
    Scoring (100 points total):
    - Patient found in database: 15 points
    - Demographics accessed (record modified): 15 points
    - Deceased date correctly set: 40 points
    - Record saved (modification during task): 20 points
    - VLM trajectory verification: 10 points
    
    Pass Threshold: 75 points with deceased_date correctly set
    
    Args:
        traj: Trajectory data with frames, steps, episode_dir
        env_info: Environment info including copy_from_env function
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
    expected_pid = metadata.get('patient_pid', 7)
    expected_fname = metadata.get('patient_fname', 'Deandre')
    expected_lname = metadata.get('patient_lname', 'Reichel')
    expected_death_date = metadata.get('expected_death_date', '2024-03-15')
    
    score = 0
    feedback_parts = []
    subscores = {
        "patient_found": False,
        "demographics_accessed": False,
        "deceased_date_set": False,
        "deceased_date_correct": False,
        "record_saved": False,
        "vlm_verification": False
    }
    
    # Copy result JSON from container
    result = None
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/mark_deceased_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
    except Exception as e:
        logger.error(f"Failed to read result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read verification data: {str(e)}",
            "subscores": subscores
        }
    
    if not result:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No verification data found - export may have failed",
            "subscores": subscores
        }
    
    logger.info(f"Verification data: {json.dumps(result, indent=2)}")
    
    # Extract data from result
    patient_found = result.get('patient_found', False)
    patient_name = result.get('patient_name', '')
    initial_status = result.get('initial_deceased_status', 'NULL')
    current_deceased_date = result.get('current_deceased_date', 'NULL')
    current_deceased_reason = result.get('current_deceased_reason', '')
    deceased_date_correct = result.get('deceased_date_correct', False)
    status_changed = result.get('status_changed', False)
    record_modified = result.get('record_modified', False)
    task_start = result.get('task_start_time', 0)
    current_mod_time = result.get('current_mod_time', 0)
    
    # CRITERION 1: Patient found (15 points)
    if patient_found:
        score += 15
        subscores["patient_found"] = True
        feedback_parts.append(f"✓ Patient found: {patient_name} (pid={expected_pid})")
    else:
        feedback_parts.append(f"✗ Patient pid={expected_pid} not found in database")
        # Cannot proceed without patient
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }
    
    # CRITERION 2: Deceased date set with correct value (40 points)
    if current_deceased_date and current_deceased_date != 'NULL':
        subscores["deceased_date_set"] = True
        
        # Check if date matches expected
        if deceased_date_correct or expected_death_date in current_deceased_date:
            score += 40
            subscores["deceased_date_correct"] = True
            feedback_parts.append(f"✓ Deceased date correctly set to {expected_death_date}")
        else:
            # Partial credit for setting a date, even if wrong
            score += 15
            feedback_parts.append(f"△ Deceased date set ({current_deceased_date}) but expected {expected_death_date}")
    else:
        feedback_parts.append("✗ Deceased date not set - patient still shows as active")
    
    # CRITERION 3: Demographics accessed / Record modified (15 points)
    # This verifies the agent actually navigated to demographics
    if record_modified:
        score += 15
        subscores["demographics_accessed"] = True
        feedback_parts.append("✓ Patient demographics were accessed and modified")
    else:
        feedback_parts.append("△ Record modification not detected")
    
    # CRITERION 4: Record saved during task (20 points)
    # Anti-gaming: verify the change happened during task execution
    if status_changed:
        score += 20
        subscores["record_saved"] = True
        feedback_parts.append("✓ Patient status changed from active to deceased during task")
    elif record_modified and current_deceased_date and current_deceased_date != 'NULL':
        # Give partial credit if deceased date is set and record was modified
        score += 10
        subscores["record_saved"] = True
        feedback_parts.append("△ Record was modified (partial credit for save verification)")
    else:
        # Check if modification timestamp is after task start
        if current_mod_time > task_start and current_deceased_date and current_deceased_date != 'NULL':
            score += 15
            subscores["record_saved"] = True
            feedback_parts.append("✓ Record modification timestamp confirms change during task")
        else:
            feedback_parts.append("✗ Cannot confirm record was saved during task")
    
    # CRITERION 5: VLM trajectory verification (10 points)
    # Verify the agent followed the correct workflow by examining trajectory
    vlm_score = verify_workflow_via_vlm(traj, env_info)
    if vlm_score > 0:
        score += vlm_score
        subscores["vlm_verification"] = True
        feedback_parts.append(f"✓ VLM verified demographics workflow ({vlm_score}/10 points)")
    else:
        feedback_parts.append("△ VLM verification not available or inconclusive")
    
    # Bonus: Check if deceased reason was also set
    if current_deceased_reason and current_deceased_reason != 'NULL' and current_deceased_reason.strip():
        feedback_parts.append(f"✓ Bonus: Deceased reason documented: {current_deceased_reason[:50]}")
    
    # Determine pass/fail
    # Must have: deceased date correctly set AND score >= 75
    passed = (subscores["deceased_date_correct"] and score >= 75)
    
    # Add summary
    feedback_parts.append(f"\nFinal Score: {score}/100")
    feedback_parts.append(f"Pass Threshold: 75 points with correct death date")
    feedback_parts.append(f"Result: {'PASSED' if passed else 'FAILED'}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "expected_patient": f"{expected_fname} {expected_lname}",
            "expected_death_date": expected_death_date,
            "actual_death_date": current_deceased_date,
            "status_changed": status_changed,
            "record_modified": record_modified
        }
    }


def verify_workflow_via_vlm(traj: Dict[str, Any], env_info: Dict[str, Any]) -> int:
    """
    Use VLM to verify the agent followed the correct workflow.
    
    Checks trajectory frames for:
    - Patient search/finder screen
    - Patient demographics edit screen
    - Form with deceased/death date field
    
    Args:
        traj: Trajectory with frames
        env_info: Environment info with query_vlm function
        
    Returns:
        int: Score from 0-10
    """
    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        logger.warning("VLM query function not available")
        return 0
    
    try:
        # Try to import trajectory utilities
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        except ImportError:
            logger.warning("Could not import gym_anything.vlm utilities")
            return 0
        
        # Sample frames from trajectory (not just final screenshot!)
        frames = sample_trajectory_frames(traj, n=5)
        final_frame = get_final_screenshot(traj)
        
        if not frames and not final_frame:
            logger.warning("No trajectory frames available for VLM verification")
            return 0
        
        # Combine frames for analysis
        all_frames = frames + ([final_frame] if final_frame else [])
        
        if not all_frames:
            return 0
        
        # VLM prompt to verify workflow
        vlm_prompt = """You are verifying if a computer agent correctly updated a patient's deceased status in OpenEMR (Electronic Health Records system).

TASK: Mark patient Deandre Reichel as deceased with death date 2024-03-15

Analyze these screenshots from the agent's workflow and determine:

1. Did the agent access the OpenEMR patient search or finder?
2. Did the agent open a patient's demographics/edit screen?
3. Is there evidence of a "deceased" or "death date" field being filled in?
4. Does any screen show the date "2024-03-15" or "March 15, 2024"?
5. Is there a save/submit action visible?

Respond in JSON format:
{
    "patient_search_visible": true/false,
    "demographics_screen_visible": true/false,
    "deceased_field_visible": true/false,
    "death_date_entered": true/false,
    "save_action_visible": true/false,
    "workflow_confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation of what workflow steps are visible"
}
"""
        
        # Query VLM with trajectory frames
        vlm_result = query_vlm(
            prompt=vlm_prompt,
            images=all_frames
        )
        
        if not vlm_result.get("success"):
            logger.warning(f"VLM query failed: {vlm_result.get('error', 'Unknown error')}")
            return 0
        
        # Parse VLM response
        parsed = vlm_result.get("parsed", {})
        
        # Calculate score based on workflow verification
        workflow_score = 0
        
        if parsed.get("demographics_screen_visible"):
            workflow_score += 3
        if parsed.get("deceased_field_visible"):
            workflow_score += 3
        if parsed.get("death_date_entered"):
            workflow_score += 2
        if parsed.get("save_action_visible"):
            workflow_score += 2
        
        # Cap at 10 points
        return min(workflow_score, 10)
        
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        return 0


def main():
    """Main entry point for command-line testing."""
    print("=" * 60)
    print("Mark Patient as Deceased Verifier")
    print("=" * 60)
    print("\nThis verifier is designed to be called by the gym-anything framework.")
    print("It uses copy_from_env to read /tmp/mark_deceased_result.json from the container.")
    print("\nExpected task: Mark patient Deandre Reichel (pid=7) as deceased")
    print("Expected death date: 2024-03-15")
    print("\nScoring:")
    print("  - Patient found: 15 points")
    print("  - Demographics accessed: 15 points")
    print("  - Deceased date correctly set: 40 points")
    print("  - Record saved during task: 20 points")
    print("  - VLM workflow verification: 10 points")
    print("\nPass threshold: 75 points with correct death date")
    print("=" * 60)
    
    return 0


if __name__ == "__main__":
    sys.exit(main())