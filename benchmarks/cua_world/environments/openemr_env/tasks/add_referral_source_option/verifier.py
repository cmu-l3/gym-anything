#!/usr/bin/env python3
"""
Verifier for Add Referral Source Option task in OpenEMR

Verifies that the agent successfully added a new referral source option
"Westside Urgent Care" to OpenEMR's list management system.

Verification Strategy:
1. PRIMARY: Check exported JSON from database query
2. SECONDARY: VLM verification on trajectory for workflow confirmation

Scoring Criteria:
- Option exists in database: 40 points
- Option in correct list (refsource): 20 points
- Title contains "Westside Urgent Care": 20 points
- Option is active: 10 points
- Option has valid ID (usable): 10 points

Pass Threshold: 70 points with option_exists criterion met
"""

import sys
import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_add_referral_source(traj, env_info, task_info):
    """
    Verify that Westside Urgent Care referral source was added to OpenEMR.
    
    Uses copy_from_env to read pre-exported verification data from the container.
    The export_result.sh script queries the database and saves results to JSON.
    
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
    
    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_list_id = metadata.get('list_id', 'refsource')
    expected_title_pattern = metadata.get('expected_title_pattern', 'westside')
    scoring = metadata.get('scoring', {
        'option_exists': 40,
        'correct_list': 20,
        'title_correct': 20,
        'option_active': 10,
        'option_usable': 10
    })
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/add_refsource_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        score = 0
        feedback_parts = []
        subscores = {
            "option_exists": False,
            "correct_list": False,
            "title_correct": False,
            "option_active": False,
            "option_usable": False,
            "newly_added": False
        }
        
        # Extract data from result
        initial_count = result.get('initial_count', 0)
        current_count = result.get('current_count', 0)
        option_found = result.get('option_found', False)
        option_data = result.get('option', {})
        validation = result.get('validation', {})
        wrong_list_found = result.get('wrong_list_found', False)
        wrong_list_id = result.get('wrong_list_id', '')
        
        logger.info(f"Result data: initial={initial_count}, current={current_count}, found={option_found}")
        logger.info(f"Option data: {option_data}")
        logger.info(f"Validation: {validation}")
        
        # CRITERION 1: Option exists (40 points)
        if option_found:
            score += scoring.get('option_exists', 40)
            subscores["option_exists"] = True
            feedback_parts.append("✅ Westside referral source option found in database")
        else:
            feedback_parts.append("❌ Westside referral source option NOT found")
            
            # Check if option was added to wrong list
            if wrong_list_found:
                feedback_parts.append(f"⚠️ Option found in WRONG list: '{wrong_list_id}' (should be 'refsource')")
            
            # Check if any new options were added at all
            new_options = result.get('new_options_added', 0)
            if new_options > 0:
                feedback_parts.append(f"Note: {new_options} new option(s) added, but not with expected 'Westside' name")
            else:
                feedback_parts.append("No new options were added to any list")
            
            # Return early since nothing to verify
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores,
                "details": {
                    "initial_count": initial_count,
                    "current_count": current_count,
                    "option_data": option_data
                }
            }
        
        # CRITERION 2: Correct list (20 points)
        list_id = option_data.get('list_id', '')
        if list_id == expected_list_id:
            score += scoring.get('correct_list', 20)
            subscores["correct_list"] = True
            feedback_parts.append(f"✅ Option in correct list: '{expected_list_id}'")
        else:
            feedback_parts.append(f"❌ Option in WRONG list: '{list_id}' (expected: '{expected_list_id}')")
        
        # CRITERION 3: Title correct (20 points)
        title = option_data.get('title', '').lower()
        if 'westside' in title and 'urgent' in title:
            score += scoring.get('title_correct', 20)
            subscores["title_correct"] = True
            feedback_parts.append(f"✅ Title correct: '{option_data.get('title', '')}'")
        elif 'westside' in title:
            # Partial credit for having "Westside" but missing "Urgent Care"
            partial_score = scoring.get('title_correct', 20) // 2
            score += partial_score
            subscores["title_correct"] = True  # Partial
            feedback_parts.append(f"⚠️ Title partially correct: '{option_data.get('title', '')}' (missing 'Urgent Care')")
        else:
            feedback_parts.append(f"❌ Title incorrect: '{option_data.get('title', '')}'")
        
        # CRITERION 4: Option is active (10 points)
        activity = option_data.get('activity', '')
        if activity == '1' or validation.get('option_active', False):
            score += scoring.get('option_active', 10)
            subscores["option_active"] = True
            feedback_parts.append("✅ Option is active")
        else:
            feedback_parts.append(f"❌ Option is NOT active (activity={activity})")
        
        # CRITERION 5: Option has valid ID / usable (10 points)
        option_id = option_data.get('option_id', '')
        if option_id and option_id.strip() and option_id != 'NULL':
            score += scoring.get('option_usable', 10)
            subscores["option_usable"] = True
            feedback_parts.append(f"✅ Option has valid ID: '{option_id}'")
        else:
            feedback_parts.append("❌ Option has no valid ID")
        
        # BONUS CHECK: Verify option was newly added (anti-gaming)
        if current_count > initial_count:
            subscores["newly_added"] = True
            feedback_parts.append(f"✅ Option was newly created (count: {initial_count} → {current_count})")
        else:
            feedback_parts.append(f"⚠️ Option count unchanged - may be pre-existing")
        
        # Determine pass/fail
        # Must have option_exists AND at least 70 points
        key_criteria_met = subscores["option_exists"] and subscores["correct_list"]
        passed = score >= 70 and key_criteria_met
        
        # Build final feedback
        final_feedback = f"Score: {score}/100 | " + " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": final_feedback,
            "subscores": subscores,
            "details": {
                "initial_count": initial_count,
                "current_count": current_count,
                "option_data": option_data,
                "validation": validation
            }
        }
        
    except FileNotFoundError:
        logger.error("Result file not found - export may have failed")
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - task export may have failed"
        }
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse task result: {e}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def verify_with_vlm_trajectory(traj, env_info, task_info):
    """
    Optional VLM-based verification using trajectory frames.
    
    This can be used as secondary verification to confirm the agent
    actually navigated through the correct workflow.
    """
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    except ImportError:
        logger.warning("VLM utilities not available")
        return None
    
    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        return None
    
    # Sample frames from trajectory
    frames = sample_trajectory_frames(traj, n=5)
    final = get_final_screenshot(traj)
    
    if not frames and not final:
        return None
    
    all_frames = frames + ([final] if final else [])
    
    vlm_prompt = """You are verifying if an agent successfully added a referral source option in OpenEMR.

The task was to:
1. Navigate to Administration > Lists
2. Find the "Referral Source" list  
3. Add "Westside Urgent Care" as a new option
4. Save the new option

Looking at these screenshots from the agent's workflow, determine:
1. Did the agent navigate to the Administration menu?
2. Did the agent access the Lists management page?
3. Did the agent appear to add a new list option?
4. Was there any visible confirmation of success?

Respond in JSON format:
{
    "navigated_to_admin": true/false,
    "accessed_lists": true/false,
    "added_option": true/false,
    "success_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""
    
    try:
        result = query_vlm(
            prompt=vlm_prompt,
            images=all_frames
        )
        return result
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        return None


if __name__ == "__main__":
    # Test stub for local development
    print("Verifier module for add_referral_source_option task")
    print("This module should be called by the task framework with proper traj, env_info, task_info")