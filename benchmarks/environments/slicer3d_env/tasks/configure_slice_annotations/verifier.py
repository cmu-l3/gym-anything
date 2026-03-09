#!/usr/bin/env python3
"""
Verifier for Configure Slice Annotations task.

VERIFICATION STRATEGY (Hybrid: Programmatic + VLM on Trajectory):

Programmatic checks (60 points):
  1. Orientation markers enabled in at least one view (20 pts)
  2. Orientation markers enabled in all three views (10 pts bonus)
  3. Settings were changed during task (15 pts) - anti-gaming
  4. Data was loaded (10 pts)
  5. Slicer was running (5 pts)

VLM checks (40 points) - using trajectory frames:
  6. Process verification (15 pts): Agent accessed settings menus
  7. Orientation labels visible in final state (20 pts)
  8. Patient info NOT visible (5 pts)

Pass threshold: 70 points with orientation markers enabled AND patient name hidden criteria
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_slice_annotations(traj, env_info, task_info):
    """
    Verify that slice view annotations were configured correctly.
    
    Uses multi-criteria scoring with VLM trajectory verification.
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
    weights = metadata.get('scoring_weights', {})
    pass_threshold = metadata.get('pass_threshold', 70)
    
    w_orientation_enabled = weights.get('orientation_markers_enabled', 30)
    w_patient_hidden = weights.get('patient_name_hidden', 25)
    w_date_hidden = weights.get('study_date_hidden', 15)
    w_all_views = weights.get('all_views_configured', 15)
    w_vlm = weights.get('vlm_confirms_configuration', 10)
    w_settings = weights.get('settings_applied', 5)

    score = 0
    feedback_parts = []
    details = {}

    # ================================================================
    # COPY RESULT FILE FROM CONTAINER
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/slice_annotations_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Export result not found - task may not have completed"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result: {e}"
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

    details['export_result'] = result

    # ================================================================
    # CRITERION 1: Slicer was running (5 points)
    # ================================================================
    slicer_running = result.get('slicer_was_running', False)
    if slicer_running:
        score += 5
        feedback_parts.append("Slicer running")
    else:
        feedback_parts.append("Slicer NOT running")
        # Can't verify much without Slicer
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }

    # ================================================================
    # CRITERION 2: Data was loaded (10 points)
    # ================================================================
    data_loaded = result.get('data_loaded', False)
    if data_loaded:
        score += 10
        feedback_parts.append("Data loaded")
    else:
        feedback_parts.append("Data NOT loaded")

    # ================================================================
    # CRITERION 3: Orientation markers enabled (30 points)
    # ================================================================
    any_orientation = result.get('any_orientation_enabled', False)
    all_orientation = result.get('all_orientation_enabled', False)
    
    red_orientation = result.get('red_orientation_enabled', False)
    yellow_orientation = result.get('yellow_orientation_enabled', False)
    green_orientation = result.get('green_orientation_enabled', False)
    
    orientation_count = sum([red_orientation, yellow_orientation, green_orientation])
    
    if all_orientation:
        score += w_orientation_enabled
        feedback_parts.append("Orientation markers: ALL views")
        details['orientation_status'] = 'all_enabled'
    elif any_orientation:
        # Partial credit based on how many views
        partial_score = int(w_orientation_enabled * (orientation_count / 3))
        score += partial_score
        feedback_parts.append(f"Orientation markers: {orientation_count}/3 views")
        details['orientation_status'] = f'{orientation_count}_of_3'
    else:
        feedback_parts.append("Orientation markers: NOT enabled")
        details['orientation_status'] = 'none_enabled'

    # ================================================================
    # CRITERION 4: All views configured bonus (15 points)
    # ================================================================
    if all_orientation:
        score += w_all_views
        feedback_parts.append("All 3 views configured")

    # ================================================================
    # CRITERION 5: Settings were changed during task (anti-gaming) (15 points)
    # ================================================================
    settings_changed = result.get('settings_changed', False)
    initial_any = result.get('initial_any_orientation', False)
    
    if settings_changed:
        score += 15
        feedback_parts.append("Settings modified during task")
        details['anti_gaming'] = 'passed'
    elif any_orientation and not initial_any:
        # Orientation is now enabled but wasn't before
        score += 15
        feedback_parts.append("Orientation enabled (was off)")
        details['anti_gaming'] = 'passed_implicit'
    else:
        feedback_parts.append("Settings may not have changed")
        details['anti_gaming'] = 'unclear'

    # ================================================================
    # VLM VERIFICATION (40 points total)
    # ================================================================
    vlm_score = 0
    vlm_feedback = []
    
    # Try to get VLM query function
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm:
        try:
            # Get trajectory frames for process verification
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Sample frames across the trajectory
            traj_frames = sample_trajectory_frames(traj, n=5) if traj else []
            final_screenshot = get_final_screenshot(traj)
            
            # Also try to get screenshots from container
            if not final_screenshot:
                temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
                try:
                    copy_from_env("/tmp/task_final.png", temp_screenshot.name)
                    if os.path.exists(temp_screenshot.name) and os.path.getsize(temp_screenshot.name) > 1000:
                        final_screenshot = temp_screenshot.name
                except Exception:
                    pass
            
            # VLM Check 1: Process verification (15 points)
            # Did the agent navigate through settings menus?
            if traj_frames and len(traj_frames) >= 3:
                process_prompt = """Analyze these screenshots from a 3D Slicer session (medical imaging software).

The task was to configure slice view annotation settings to:
1. Enable orientation markers (A/P, R/L, S/I labels in corners)
2. Hide patient identifying information

Looking at the sequence of screenshots, determine:
1. Did the user access any menus or settings dialogs?
2. Is there evidence of navigating to View menu, Application Settings, or slice controller?
3. Do the screenshots show progression through a configuration workflow?

Respond in JSON:
{
    "menus_accessed": true/false,
    "settings_visible": true/false,
    "workflow_progression": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description"
}
"""
                try:
                    process_result = query_vlm(prompt=process_prompt, images=traj_frames)
                    if process_result and process_result.get('success'):
                        parsed = process_result.get('parsed', {})
                        if parsed.get('menus_accessed') or parsed.get('settings_visible'):
                            vlm_score += 15
                            vlm_feedback.append("VLM: Settings accessed")
                        elif parsed.get('workflow_progression'):
                            vlm_score += 10
                            vlm_feedback.append("VLM: Workflow detected")
                        details['vlm_process'] = parsed
                except Exception as e:
                    logger.warning(f"VLM process check failed: {e}")
            
            # VLM Check 2: Final state verification (20 points)
            # Are orientation labels visible?
            if final_screenshot:
                orientation_prompt = """Analyze this screenshot from 3D Slicer showing brain MRI slice views.

Look at the slice view panels (the 2D cross-section views showing brain anatomy).

Check for:
1. Orientation marker labels - letters like 'A', 'P', 'L', 'R', 'S', 'I' in the CORNERS of slice views indicating anatomical directions (Anterior, Posterior, Left, Right, Superior, Inferior)
2. 3D orientation cube/axes indicator in a corner
3. Patient name text displayed anywhere in the views
4. Date/time information displayed

Respond in JSON:
{
    "orientation_labels_visible": true/false,
    "orientation_cube_visible": true/false,
    "patient_name_visible": true/false,
    "date_visible": true/false,
    "slice_views_visible": true/false,
    "brain_anatomy_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "what you see in the slice views"
}
"""
                try:
                    final_result = query_vlm(prompt=orientation_prompt, image=final_screenshot)
                    if final_result and final_result.get('success'):
                        parsed = final_result.get('parsed', {})
                        details['vlm_final'] = parsed
                        
                        # Score orientation visibility
                        if parsed.get('orientation_labels_visible') or parsed.get('orientation_cube_visible'):
                            vlm_score += 20
                            vlm_feedback.append("VLM: Orientation markers visible")
                        elif parsed.get('slice_views_visible') and parsed.get('brain_anatomy_visible'):
                            vlm_score += 5
                            vlm_feedback.append("VLM: Slice views show data")
                        
                        # Bonus for patient info hidden (5 points)
                        if parsed.get('patient_name_visible') == False:
                            vlm_score += 5
                            vlm_feedback.append("VLM: Patient info hidden")
                        
                except Exception as e:
                    logger.warning(f"VLM final check failed: {e}")
            
        except ImportError:
            logger.warning("VLM utilities not available")
            vlm_feedback.append("VLM: Not available")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            vlm_feedback.append(f"VLM: Error - {str(e)[:50]}")
    else:
        vlm_feedback.append("VLM: Query function not provided")
    
    # Add VLM score (capped at 40)
    vlm_score = min(vlm_score, 40)
    score += vlm_score
    feedback_parts.extend(vlm_feedback)
    details['vlm_score'] = vlm_score

    # ================================================================
    # DETERMINE PASS/FAIL
    # ================================================================
    # Required criteria: orientation markers enabled
    required_met = any_orientation
    
    # Pass if score >= threshold AND required criteria met
    passed = (score >= pass_threshold) and required_met
    
    # If orientation was enabled but VLM unavailable, still pass with sufficient score
    if any_orientation and score >= 50 and not query_vlm:
        passed = True
        feedback_parts.append("Passed (VLM unavailable, programmatic check OK)")

    details['final_score'] = score
    details['pass_threshold'] = pass_threshold
    details['required_criteria_met'] = required_met
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": feedback,
        "details": details
    }