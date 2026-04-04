#!/usr/bin/env python3
"""
Verifier for configure_linked_views task.

VERIFICATION STRATEGY:
This task verifies that the agent configured a dual-view layout with linked scrolling
in 3D Slicer to compare two MRI sequences.

SCORING CRITERIA (100 points total):
1. Multi-view layout active (20 pts) - Layout changed from default single view
2. Two slice views visible (15 pts) - At least two slice widgets are active
3. Different volumes displayed (25 pts) - Each view shows a different MRI sequence
4. View linking enabled (20 pts) - Slice view linking is turned on
5. Offsets synchronized (10 pts) - Both views at same anatomical position
6. Screenshot saved (10 pts) - Valid screenshot exists at expected path

ANTI-GAMING:
- Screenshot timestamp checked against task start time
- Slicer state queried to verify actual configuration
- VLM trajectory verification confirms real work done

Pass threshold: 70 points with "Different volumes displayed" criterion met
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_linked_views(traj, env_info, task_info):
    """
    Verify that dual-view layout with linked scrolling was configured.
    
    Uses multi-criteria scoring with programmatic checks and VLM trajectory verification.
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
    expected_screenshot_path = metadata.get('expected_screenshot_path', '/home/ga/Documents/SlicerData/Exports/linked_views.png')
    min_screenshot_size_kb = metadata.get('min_screenshot_size_kb', 50)
    valid_multiview_layouts = metadata.get('valid_multiview_layout_ids', [2, 3, 12, 13, 14, 15, 23, 24, 25, 26, 27, 28, 29, 30])
    
    weights = metadata.get('scoring_weights', {})
    w_multiview = weights.get('multiview_layout_active', 20)
    w_two_views = weights.get('two_slice_views_visible', 15)
    w_diff_volumes = weights.get('different_volumes_displayed', 25)
    w_linking = weights.get('view_linking_enabled', 20)
    w_sync = weights.get('offsets_synchronized', 10)
    w_screenshot = weights.get('screenshot_saved', 10)

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/linked_views_result.json", temp_result.name)
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

    # Check if Slicer was running
    slicer_running = result.get('slicer_was_running', False)
    if not slicer_running:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion"
        }
    feedback_parts.append("Slicer running")

    # ============================================================
    # CRITERION 1: Multi-view layout active (20 points)
    # ============================================================
    layout_id = result.get('layout_id', -1)
    layout_name = result.get('layout_name', '')
    is_multiview = result.get('is_multiview_layout', False)

    if is_multiview or layout_id in valid_multiview_layouts:
        score += w_multiview
        feedback_parts.append(f"Multi-view layout ({layout_name})")
        details['multiview_layout'] = True
    elif layout_id > 1:
        # Partial credit for non-default layout
        score += int(w_multiview * 0.5)
        feedback_parts.append(f"Non-default layout ({layout_name})")
        details['multiview_layout'] = False
    else:
        feedback_parts.append(f"Default layout (ID={layout_id})")
        details['multiview_layout'] = False

    # ============================================================
    # CRITERION 2: Two slice views visible (15 points)
    # ============================================================
    num_views = result.get('num_slice_views', 0)
    
    if num_views >= 2:
        score += w_two_views
        feedback_parts.append(f"{num_views} slice views visible")
        details['two_views_visible'] = True
    elif num_views == 1:
        score += int(w_two_views * 0.3)
        feedback_parts.append("Only 1 slice view visible")
        details['two_views_visible'] = False
    else:
        feedback_parts.append("No slice views visible")
        details['two_views_visible'] = False

    # ============================================================
    # CRITERION 3: Different volumes displayed (25 points)
    # This is the KEY criterion
    # ============================================================
    different_volumes = result.get('different_volumes_displayed', False)
    red_vol = result.get('red_volume_name', '')
    yellow_vol = result.get('yellow_volume_name', '')

    if different_volumes:
        score += w_diff_volumes
        feedback_parts.append(f"Different volumes: {red_vol[:20]} vs {yellow_vol[:20]}")
        details['different_volumes'] = True
        details['red_volume'] = red_vol
        details['yellow_volume'] = yellow_vol
    elif red_vol or yellow_vol:
        # Volumes loaded but same in both views
        score += int(w_diff_volumes * 0.3)
        feedback_parts.append(f"Same volume in both views: {red_vol[:20]}")
        details['different_volumes'] = False
    else:
        feedback_parts.append("No volumes assigned to views")
        details['different_volumes'] = False

    # ============================================================
    # CRITERION 4: View linking enabled (20 points)
    # ============================================================
    any_linking = result.get('any_linking_enabled', False)
    red_linked = result.get('linking_enabled_red', False)
    yellow_linked = result.get('linking_enabled_yellow', False)

    if any_linking or (red_linked and yellow_linked):
        score += w_linking
        feedback_parts.append("View linking enabled")
        details['linking_enabled'] = True
    elif red_linked or yellow_linked:
        score += int(w_linking * 0.5)
        feedback_parts.append("Partial linking enabled")
        details['linking_enabled'] = False
    else:
        feedback_parts.append("Linking not enabled")
        details['linking_enabled'] = False

    # ============================================================
    # CRITERION 5: Offsets synchronized (10 points)
    # ============================================================
    offsets_sync = result.get('offsets_synchronized', False)

    if offsets_sync:
        score += w_sync
        feedback_parts.append("Offsets synchronized")
        details['offsets_synchronized'] = True
    else:
        # This is less critical - might just not have scrolled yet
        feedback_parts.append("Offsets not synchronized")
        details['offsets_synchronized'] = False

    # ============================================================
    # CRITERION 6: Screenshot saved (10 points)
    # ============================================================
    screenshot_exists = result.get('screenshot_exists', False)
    screenshot_size = result.get('screenshot_size_kb', 0)
    screenshot_created = result.get('screenshot_created_during_task', False)
    new_screenshots = result.get('new_screenshots_count', 0)

    if screenshot_exists and screenshot_created and screenshot_size >= min_screenshot_size_kb:
        score += w_screenshot
        feedback_parts.append(f"Screenshot saved ({screenshot_size}KB)")
        details['screenshot_saved'] = True
    elif screenshot_exists and screenshot_size >= min_screenshot_size_kb:
        # File exists but may not have been created during task
        score += int(w_screenshot * 0.7)
        feedback_parts.append(f"Screenshot exists ({screenshot_size}KB)")
        details['screenshot_saved'] = True
    elif new_screenshots > 0:
        score += int(w_screenshot * 0.5)
        feedback_parts.append(f"{new_screenshots} new screenshot(s) found")
        details['screenshot_saved'] = True
    else:
        feedback_parts.append("No screenshot saved")
        details['screenshot_saved'] = False

    # ============================================================
    # VLM TRAJECTORY VERIFICATION (bonus validation)
    # ============================================================
    vlm_verified = False
    vlm_feedback = ""
    
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        # Sample frames from trajectory
        frames = sample_trajectory_frames(traj, n=5)
        
        if frames:
            vlm_prompt = """You are verifying a task in 3D Slicer medical imaging software.

The task was to configure a dual-view (side-by-side) layout showing two different MRI sequences with linked scrolling.

Looking at these trajectory frames (earliest to latest), determine:
1. LAYOUT_CHANGED: Did the layout change from single-view to multi-view/side-by-side?
2. TWO_VIEWS_VISIBLE: Are there two slice views visible showing brain MRI data?
3. DIFFERENT_SEQUENCES: Do the two views appear to show different MRI contrasts (e.g., one brighter than other, or different tissue appearance)?
4. WORKFLOW_PROGRESSION: Does the sequence show the agent making meaningful changes?

Respond in JSON:
{
    "layout_changed": true/false,
    "two_views_visible": true/false,
    "different_sequences": true/false,
    "workflow_progression": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description"
}"""
            
            vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
            
            if vlm_result and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                
                # Check key VLM indicators
                two_views = parsed.get('two_views_visible', False)
                diff_seq = parsed.get('different_sequences', False)
                workflow = parsed.get('workflow_progression', False)
                confidence = parsed.get('confidence', 'low')
                
                if two_views and diff_seq and confidence in ['medium', 'high']:
                    vlm_verified = True
                    vlm_feedback = f"VLM confirms dual-view setup ({confidence} confidence)"
                elif two_views or diff_seq:
                    vlm_feedback = f"VLM partial confirmation: views={two_views}, diff_seq={diff_seq}"
                else:
                    vlm_feedback = "VLM could not confirm dual-view setup"
                
                details['vlm_result'] = parsed
                
    except ImportError:
        vlm_feedback = "VLM not available"
    except Exception as e:
        vlm_feedback = f"VLM error: {str(e)[:50]}"
        logger.warning(f"VLM verification failed: {e}")

    if vlm_feedback:
        feedback_parts.append(vlm_feedback)
    details['vlm_verified'] = vlm_verified

    # ============================================================
    # FINAL SCORING
    # ============================================================
    
    # Key criterion: different volumes must be displayed
    key_criteria_met = details.get('different_volumes', False)
    
    # Pass threshold: 70 points with key criterion
    passed = score >= 70 and key_criteria_met

    # Alternative pass: if VLM strongly confirms, lower threshold
    if vlm_verified and score >= 60:
        passed = True

    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }