#!/usr/bin/env python3
"""
Verifier for Assign Primary Care Provider task in OpenEMR

Verifies that the correct provider (Philip Katz) was assigned as the
primary care provider for patient Jayson Fadel.

Uses copy_from_env to read pre-exported verification data from the container.
The export_result.sh script queries the database and saves results to JSON.

Scoring (100 points total):
- Patient accessed correctly: 20 points
- Demographics section accessed: 20 points  
- Provider field modified (not NULL): 40 points
- Correct provider (Philip Katz): 20 points

Pass threshold: 60 points with provider field modified
"""

import sys
import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_assign_pcp(traj, env_info, task_info):
    """
    Verify that the primary care provider was correctly assigned.

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
    expected_pid = metadata.get('patient_pid', 3)
    expected_provider_fname = metadata.get('provider_fname', 'Philip')
    expected_provider_lname = metadata.get('provider_lname', 'Katz')
    expected_provider_username = metadata.get('provider_username', 'physician')

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/assign_pcp_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {
            "patient_accessed": False,
            "demographics_accessed": False,
            "provider_assigned": False,
            "correct_provider": False
        }

        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        initial_provider_id = result.get('initial_provider_id', 0)
        expected_provider_id = result.get('expected_provider_id', 0)
        current_provider_id = result.get('current_provider_id', 0)
        provider_changed = result.get('provider_changed', False)
        correct_provider_assigned = result.get('correct_provider_assigned', False)
        assigned_provider = result.get('assigned_provider', {})

        logger.info(f"Result data: pid={patient_pid}, initial={initial_provider_id}, "
                   f"current={current_provider_id}, expected={expected_provider_id}")
        logger.info(f"Provider changed: {provider_changed}, Correct provider: {correct_provider_assigned}")

        # CRITERION 1: Correct patient was targeted (20 points)
        # We assume if the result shows correct pid, the agent accessed right patient
        if patient_pid == expected_pid:
            score += 20
            subscores["patient_accessed"] = True
            feedback_parts.append(f"✅ Correct patient accessed (pid={expected_pid})")
        else:
            feedback_parts.append(f"❌ Wrong patient targeted (expected pid={expected_pid})")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }

        # CRITERION 2: Demographics section was accessed (20 points)
        # We infer this from whether provider was changed
        # If provider changed from initial value, demographics must have been accessed
        if provider_changed or current_provider_id != initial_provider_id:
            score += 20
            subscores["demographics_accessed"] = True
            feedback_parts.append("✅ Demographics/provider section accessed")
        elif current_provider_id != 0:
            # Provider is set but wasn't changed - might have been accessed
            score += 10
            feedback_parts.append("⚠️ Provider is set but may have been pre-existing")
        else:
            feedback_parts.append("❌ Demographics section not accessed (provider unchanged)")

        # CRITERION 3: Provider field was modified (40 points)
        # Must have a non-zero/non-null provider assigned
        if current_provider_id != 0 and current_provider_id is not None:
            if provider_changed:
                # Provider was definitely changed during task (anti-gaming check passed)
                score += 40
                subscores["provider_assigned"] = True
                feedback_parts.append(f"✅ Provider field updated (providerID={current_provider_id})")
            elif initial_provider_id == 0:
                # Provider was NULL before and now has value - this is valid
                score += 40
                subscores["provider_assigned"] = True
                feedback_parts.append(f"✅ Provider assigned (providerID={current_provider_id})")
            else:
                # Provider was already set - possible gaming
                score += 20  # Partial credit
                feedback_parts.append(f"⚠️ Provider was already set (possible pre-existing: {current_provider_id})")
        else:
            feedback_parts.append("❌ No provider assigned (providerID is NULL or 0)")

        # CRITERION 4: Correct provider assigned (20 points)
        # Must be Philip Katz (the physician user)
        if correct_provider_assigned:
            score += 20
            subscores["correct_provider"] = True
            provider_name = f"{assigned_provider.get('fname', '')} {assigned_provider.get('lname', '')}"
            feedback_parts.append(f"✅ Correct provider assigned: {provider_name}")
        elif current_provider_id != 0:
            # A provider was assigned but not the correct one
            provider_name = f"{assigned_provider.get('fname', '')} {assigned_provider.get('lname', '')}"
            provider_user = assigned_provider.get('username', 'unknown')
            feedback_parts.append(f"❌ Wrong provider assigned: {provider_name} ({provider_user})")
            feedback_parts.append(f"   Expected: {expected_provider_fname} {expected_provider_lname}")
        else:
            feedback_parts.append(f"❌ No provider to verify (expected {expected_provider_fname} {expected_provider_lname})")

        # Determine pass/fail
        # Must have provider assigned (40 points) to pass
        key_criterion_met = subscores["provider_assigned"]
        passed = score >= 60 and key_criterion_met

        # Construct final feedback
        feedback = " | ".join(feedback_parts)
        feedback += f" | Final score: {score}/100"

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores,
            "details": {
                "patient_pid": patient_pid,
                "initial_provider_id": initial_provider_id,
                "current_provider_id": current_provider_id,
                "expected_provider_id": expected_provider_id,
                "provider_changed": provider_changed,
                "assigned_provider": assigned_provider
            }
        }

    except FileNotFoundError:
        logger.error("Result file not found - export may have failed")
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Result file not found - task export may have failed"
        }
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse result JSON: {e}")
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
            "feedback": f"❌ Verification error: {e}"
        }


def verify_with_vlm_fallback(traj, env_info, task_info):
    """
    Extended verification that includes VLM analysis of trajectory.
    
    This is a fallback/supplementary verification that examines screenshots
    to verify the workflow was actually performed.
    """
    # First run the primary database verification
    primary_result = verify_assign_pcp(traj, env_info, task_info)
    
    # If primary verification passed with high score, return it
    if primary_result.get('passed') and primary_result.get('score', 0) >= 80:
        return primary_result
    
    # Try VLM verification as supplementary check
    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        return primary_result
    
    try:
        # Import trajectory utilities
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        # Get trajectory frames for workflow verification
        frames = sample_trajectory_frames(traj, n=5)
        final_screenshot = get_final_screenshot(traj)
        
        if not frames and not final_screenshot:
            return primary_result
        
        # Query VLM to verify workflow
        vlm_prompt = """Analyze these screenshots from an OpenEMR session to verify the following workflow was performed:

TASK: Assign a Primary Care Provider to a patient named Jayson Fadel

Look for evidence of:
1. User logged into OpenEMR
2. Patient search/finder was used
3. Patient "Jayson Fadel" was selected/opened
4. Patient demographics or edit screen was accessed
5. A provider dropdown/field was modified
6. Changes were saved

Respond in JSON format:
{
    "openemr_logged_in": true/false,
    "patient_search_visible": true/false,
    "patient_fadel_accessed": true/false,
    "demographics_screen_visible": true/false,
    "provider_field_visible": true/false,
    "workflow_completed": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}"""

        all_images = frames + ([final_screenshot] if final_screenshot else [])
        
        vlm_result = query_vlm(
            prompt=vlm_prompt,
            images=all_images
        )
        
        if vlm_result.get('success'):
            parsed = vlm_result.get('parsed', {})
            vlm_workflow_complete = parsed.get('workflow_completed', False)
            vlm_confidence = parsed.get('confidence', 'low')
            
            # If VLM confirms workflow but DB check failed, add bonus points
            if vlm_workflow_complete and vlm_confidence in ['medium', 'high']:
                primary_result['feedback'] += f" | VLM: Workflow appears complete ({vlm_confidence} confidence)"
                # Add up to 10 bonus points for VLM confirmation
                if primary_result['score'] < 100:
                    bonus = 10 if vlm_confidence == 'high' else 5
                    primary_result['score'] = min(100, primary_result['score'] + bonus)
        
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
    
    return primary_result