#!/usr/bin/env python3
"""
Verifier for rename_volume_node task.

VERIFICATION CRITERIA:
1. New name exists (50 points) - Volume with name "STUDY001_T1_Brain" found in scene
2. Original name gone (25 points) - No volume with name "MRHead" remains
3. Volume count unchanged (10 points) - Same number of volumes (rename, not duplicate)
4. Name visible in UI (15 points) - VLM confirms new name visible in screenshot

Pass threshold: 75 points with new_name_exists criterion met
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected values
ORIGINAL_NAME = "MRHead"
EXPECTED_NEW_NAME = "STUDY001_T1_Brain"


def verify_rename_volume_node(traj, env_info, task_info):
    """
    Verify that the volume node was renamed correctly.
    
    Uses multi-criteria scoring with anti-gaming checks.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - framework error"
        }

    # Get task metadata
    metadata = task_info.get('metadata', {})
    original_name = metadata.get('original_volume_name', ORIGINAL_NAME)
    expected_new_name = metadata.get('expected_new_name', EXPECTED_NEW_NAME)
    pass_threshold = metadata.get('pass_threshold', 75)
    
    weights = metadata.get('scoring_weights', {})
    w_new_name = weights.get('new_name_exists', 50)
    w_original_gone = weights.get('original_name_gone', 25)
    w_count_unchanged = weights.get('volume_count_unchanged', 10)
    w_visible_ui = weights.get('name_visible_in_ui', 15)

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/rename_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Export result not found - export script may have failed"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result file: {e}"
        }
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read result: {e}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {}

    # ================================================================
    # Pre-check: Slicer was running
    # ================================================================
    slicer_running = result.get('slicer_was_running', False)
    if not slicer_running:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion"
        }
    
    details['slicer_running'] = True
    
    # Check if query was successful
    query_success = result.get('query_success', False)
    if not query_success:
        # If query failed, we can still try to verify from other data
        feedback_parts.append("Scene query may be incomplete")
        details['query_success'] = False
    else:
        details['query_success'] = True

    # ================================================================
    # CRITERION 1: New name exists (50 points)
    # ================================================================
    has_new_name = result.get('final_has_new_name', False)
    final_volume_names = result.get('final_volume_names', '')
    
    # Check both the direct flag and the names string
    new_name_in_list = expected_new_name in final_volume_names if final_volume_names else False
    
    if has_new_name or new_name_in_list:
        score += w_new_name
        feedback_parts.append(f"Volume '{expected_new_name}' found")
        details['new_name_exists'] = True
    else:
        feedback_parts.append(f"Volume '{expected_new_name}' NOT found")
        details['new_name_exists'] = False

    # ================================================================
    # CRITERION 2: Original name gone (25 points)
    # ================================================================
    has_mrhead = result.get('final_has_mrhead', True)
    original_name_in_list = original_name in final_volume_names if final_volume_names else True
    
    if not has_mrhead and not original_name_in_list:
        score += w_original_gone
        feedback_parts.append(f"'{original_name}' removed (renamed)")
        details['original_name_gone'] = True
    elif not has_mrhead:
        # Partial credit - direct check says gone
        score += int(w_original_gone * 0.8)
        feedback_parts.append(f"'{original_name}' appears renamed")
        details['original_name_gone'] = True
    else:
        feedback_parts.append(f"'{original_name}' still exists")
        details['original_name_gone'] = False

    # ================================================================
    # CRITERION 3: Volume count unchanged (10 points)
    # Anti-gaming: ensure agent renamed, not duplicated+deleted
    # ================================================================
    volume_count_unchanged = result.get('volume_count_unchanged', False)
    initial_count = result.get('initial_volume_count', 1)
    final_count = result.get('final_volume_count', 0)
    
    details['initial_volume_count'] = initial_count
    details['final_volume_count'] = final_count
    
    if volume_count_unchanged and final_count > 0:
        score += w_count_unchanged
        feedback_parts.append(f"Volume count unchanged ({final_count})")
        details['volume_count_unchanged'] = True
    elif final_count == initial_count and final_count > 0:
        # Direct comparison also valid
        score += w_count_unchanged
        feedback_parts.append(f"Volume count unchanged ({final_count})")
        details['volume_count_unchanged'] = True
    elif final_count > 0:
        # Some volumes exist, partial credit
        score += int(w_count_unchanged * 0.5)
        feedback_parts.append(f"Volume count changed ({initial_count} -> {final_count})")
        details['volume_count_unchanged'] = False
    else:
        feedback_parts.append("No volumes found in final state")
        details['volume_count_unchanged'] = False

    # ================================================================
    # CRITERION 4: Name visible in UI via VLM (15 points)
    # Uses trajectory frames for robust verification
    # ================================================================
    vlm_score = 0
    vlm_feedback = "VLM verification not performed"
    
    try:
        # Try to import VLM utilities
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        # Get trajectory frames for process verification
        traj_frames = sample_trajectory_frames(traj, n=3)
        final_screenshot = get_final_screenshot(traj)
        
        if final_screenshot or traj_frames:
            # Prepare images for VLM
            images_to_check = []
            if traj_frames:
                images_to_check.extend(traj_frames[-2:])  # Last 2 trajectory frames
            if final_screenshot:
                images_to_check.append(final_screenshot)
            
            if images_to_check:
                vlm_prompt = f"""You are verifying if a volume was renamed in 3D Slicer medical imaging software.

The task was to rename a volume from '{original_name}' to '{expected_new_name}'.

Look at these screenshots and determine:
1. Is 3D Slicer visible?
2. Can you see the Data module or Subject Hierarchy panel?
3. Is the new name '{expected_new_name}' visible anywhere in the interface (data tree, volume selectors, title bars)?
4. Is the old name '{original_name}' still visible (which would indicate failure)?

Respond in JSON format:
{{
    "slicer_visible": true/false,
    "data_module_visible": true/false,
    "new_name_visible": true/false,
    "old_name_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}}
"""
                vlm_result = query_vlm(prompt=vlm_prompt, images=images_to_check)
                
                if vlm_result and vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    details['vlm_result'] = parsed
                    
                    new_name_visible = parsed.get('new_name_visible', False)
                    old_name_visible = parsed.get('old_name_visible', True)
                    confidence = parsed.get('confidence', 'low')
                    
                    if new_name_visible and not old_name_visible:
                        if confidence == 'high':
                            vlm_score = w_visible_ui
                        elif confidence == 'medium':
                            vlm_score = int(w_visible_ui * 0.8)
                        else:
                            vlm_score = int(w_visible_ui * 0.6)
                        vlm_feedback = f"VLM confirms rename (confidence: {confidence})"
                    elif new_name_visible:
                        vlm_score = int(w_visible_ui * 0.5)
                        vlm_feedback = "VLM sees new name but old name may still exist"
                    elif parsed.get('slicer_visible', False):
                        vlm_score = int(w_visible_ui * 0.2)
                        vlm_feedback = "Slicer visible but rename not confirmed"
                    else:
                        vlm_feedback = "VLM could not confirm rename"
                else:
                    vlm_feedback = "VLM query failed"
        else:
            vlm_feedback = "No screenshots available for VLM verification"
            
    except ImportError:
        vlm_feedback = "VLM utilities not available"
        # Give partial credit if other criteria passed and rename was successful
        if result.get('rename_success', False):
            vlm_score = int(w_visible_ui * 0.5)
            vlm_feedback = "VLM not available; using programmatic verification"
    except Exception as e:
        vlm_feedback = f"VLM error: {str(e)}"
        # Partial credit based on programmatic success
        if result.get('rename_success', False):
            vlm_score = int(w_visible_ui * 0.3)
    
    score += vlm_score
    feedback_parts.append(vlm_feedback)
    details['vlm_score'] = vlm_score

    # ================================================================
    # Final scoring and pass/fail determination
    # ================================================================
    
    # Key criterion: new name must exist
    key_criterion_met = details.get('new_name_exists', False)
    
    # Calculate pass status
    passed = score >= pass_threshold and key_criterion_met
    
    # Compile feedback
    feedback = " | ".join(feedback_parts)
    
    # Add summary
    details['final_score'] = score
    details['pass_threshold'] = pass_threshold
    details['key_criterion_met'] = key_criterion_met
    details['final_volume_names_list'] = final_volume_names.split(',') if final_volume_names else []
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }