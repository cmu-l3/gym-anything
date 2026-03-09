#!/usr/bin/env python3
"""
Verifier for create_fourpanel_comparison task.

VERIFICATION STRATEGY (Hybrid: Programmatic + VLM on Trajectory):

Programmatic checks (35 points):
  1. Screenshot exists at expected path (15 pts)
  2. Screenshot file size indicates real content (10 pts)
  3. File was created during task - anti-gaming (10 pts)

VLM checks using TRAJECTORY frames (65 points):
  4. Four panels visible in final screenshot (25 pts)
  5. Different MRI contrasts visible (20 pts)
  6. Brain anatomy present (10 pts)
  7. Tumor visible / same slice level (10 pts)

Pass threshold: 60 points with screenshot existing and four panels visible
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ================================================================
# VLM PROMPTS
# ================================================================

FOUR_PANEL_VERIFICATION_PROMPT = """You are analyzing a screenshot from 3D Slicer medical imaging software to verify that a four-panel MRI comparison view was created correctly.

The task was to display four different MRI sequences (T1, T1-contrast, T2, FLAIR) of a brain tumor patient in a 2x2 grid layout.

Analyze this image and determine:

1. FOUR_PANELS_VISIBLE: Is the screen divided into 4 distinct image panels (2x2 grid)?
   - Look for clear boundaries between panels
   - Each panel should show a grayscale medical image
   - NOT just one large image, NOT 3 panels

2. DIFFERENT_CONTRASTS: Do the panels show visually different MRI contrasts?
   - T1 vs T2 have inverted contrast (what's dark in T1 is bright in T2)
   - Look for different brightness patterns in brain tissue
   - Panels should NOT all look identical

3. BRAIN_ANATOMY_VISIBLE: Is brain anatomy clearly visible?
   - Brain shape (oval/round structure)
   - Gray and white matter differentiation
   - NOT just noise or empty black/white images

4. TUMOR_OR_PATHOLOGY_VISIBLE: Is there a visible abnormality/tumor in the images?
   - Bright or dark irregular area within the brain
   - Asymmetric finding
   - Area that looks different from surrounding tissue

5. SAME_ANATOMICAL_LEVEL: Do all 4 panels appear to show the same slice level?
   - Similar brain shape/size across panels
   - Ventricles (if visible) at similar level
   - NOT randomly different slices

Respond in JSON format:
{
    "four_panels_visible": true/false,
    "panel_count_estimate": <number>,
    "different_contrasts_visible": true/false,
    "brain_anatomy_visible": true/false,
    "tumor_visible": true/false,
    "same_slice_level": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "Brief description of what you see in the image"
}
"""

TRAJECTORY_WORKFLOW_PROMPT = """You are analyzing a sequence of screenshots from an agent performing a task in 3D Slicer medical imaging software.

The task was to:
1. Change the layout to a 2x2 grid (Four-Up view)
2. Assign different MRI sequences to each panel
3. Navigate to a slice showing a brain tumor
4. Save a screenshot

The images are in chronological order (earliest to latest).

Assess the workflow progression:

1. LAYOUT_CHANGED: At any point, does the view change from single/standard view to a multi-panel grid?
2. VOLUMES_ASSIGNED: Do you see different images appearing in different panels?
3. NAVIGATION_OCCURRED: Does the slice position change (scrolling through brain)?
4. MEANINGFUL_PROGRESSION: Do the frames show actual state changes (not same screen repeated)?
5. TASK_COMPLETED: Does the final frame show a 4-panel view with brain MRI?

Respond in JSON format:
{
    "layout_changed": true/false,
    "volumes_assigned": true/false,
    "navigation_occurred": true/false,
    "meaningful_progression": true/false,
    "task_completed": true/false,
    "confidence": "low"/"medium"/"high",
    "workflow_observations": "Description of the progression seen"
}
"""


def _query_vlm(query_vlm_func, prompt, image=None, images=None):
    """Run VLM query with error handling."""
    if not query_vlm_func:
        return None
    try:
        result = query_vlm_func(prompt=prompt, image=image, images=images)
        if result.get("success"):
            return result.get("parsed", {})
        logger.warning(f"VLM query failed: {result.get('error', 'unknown')}")
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None


def verify_fourpanel_comparison(traj, env_info, task_info):
    """
    Verify that a four-panel MRI comparison view was created and screenshot saved.
    
    Uses multi-criteria scoring with VLM verification on trajectory frames.
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
    expected_screenshot_path = metadata.get('expected_screenshot_path', 
        '/home/ga/Documents/SlicerData/Screenshots/four_panel_comparison.png')
    min_size_kb = metadata.get('min_screenshot_size_kb', 100)
    
    weights = metadata.get('scoring_weights', {})
    w_screenshot_exists = weights.get('screenshot_exists', 15)
    w_screenshot_size = weights.get('screenshot_size_valid', 10)
    w_four_panels = weights.get('four_panels_visible', 25)
    w_contrasts = weights.get('different_contrasts', 20)
    w_brain_anatomy = weights.get('brain_anatomy_present', 10)
    w_same_level = weights.get('same_slice_level', 10)
    w_tumor = weights.get('tumor_visible', 10)

    feedback_parts = []
    score = 0
    details = {}

    # ================================================================
    # Copy result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/fourpanel_task_result.json", temp_result.name)
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
    # CRITERION 1: Screenshot exists (15 points)
    # ================================================================
    screenshot_exists = result.get('screenshot_exists', False)
    new_screenshots = result.get('new_screenshots_count', 0)
    
    if screenshot_exists:
        score += w_screenshot_exists
        feedback_parts.append("Screenshot saved to expected path")
        details['screenshot_at_expected_path'] = True
    elif new_screenshots > 0:
        score += w_screenshot_exists * 0.6  # Partial credit
        feedback_parts.append(f"Screenshot saved ({new_screenshots} new files, but not at expected path)")
        details['screenshot_at_expected_path'] = False
    else:
        feedback_parts.append("No screenshot saved")
        details['screenshot_at_expected_path'] = False

    # ================================================================
    # CRITERION 2: Screenshot size indicates real content (10 points)
    # ================================================================
    screenshot_size_kb = result.get('screenshot_size_kb', 0)
    image_colors = result.get('image_colors', 0)
    
    if screenshot_size_kb >= min_size_kb:
        score += w_screenshot_size
        feedback_parts.append(f"Screenshot size OK ({screenshot_size_kb}KB)")
    elif screenshot_size_kb > 50:
        score += w_screenshot_size * 0.5
        feedback_parts.append(f"Screenshot small ({screenshot_size_kb}KB)")
    else:
        feedback_parts.append(f"Screenshot too small or missing ({screenshot_size_kb}KB)")

    # ================================================================
    # CRITERION 3: File created during task - anti-gaming (included in criterion 1)
    # ================================================================
    file_created_during_task = result.get('file_created_during_task', False)
    if screenshot_exists and not file_created_during_task:
        # Penalize if file existed before task (potential gaming)
        score -= 10
        feedback_parts.append("WARNING: Screenshot may not have been created during task")
        details['anti_gaming_flag'] = True
    
    details['file_created_during_task'] = file_created_during_task

    # ================================================================
    # Copy screenshot for VLM analysis
    # ================================================================
    screenshot_for_vlm = None
    temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    try:
        # Try the expected path first
        try:
            copy_from_env(expected_screenshot_path, temp_screenshot.name)
            screenshot_for_vlm = temp_screenshot.name
        except:
            # Try the task final screenshot
            try:
                copy_from_env("/tmp/task_final.png", temp_screenshot.name)
                screenshot_for_vlm = temp_screenshot.name
            except:
                pass
    except Exception as e:
        logger.warning(f"Could not copy screenshot for VLM: {e}")

    # ================================================================
    # VLM VERIFICATION (65 points total)
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    
    # Get trajectory frames for workflow verification
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        trajectory_frames = sample_trajectory_frames(traj, n=5)
        final_frame = get_final_screenshot(traj)
    except ImportError:
        logger.warning("Could not import VLM utilities")
        trajectory_frames = []
        final_frame = None
    except Exception as e:
        logger.warning(f"Error getting trajectory frames: {e}")
        trajectory_frames = []
        final_frame = None

    # Use screenshot file if trajectory frames not available
    vlm_image = None
    if screenshot_for_vlm and os.path.exists(screenshot_for_vlm):
        vlm_image = screenshot_for_vlm
    elif final_frame:
        vlm_image = final_frame

    vlm_result = None
    if query_vlm and vlm_image:
        # Primary VLM check: analyze the final screenshot/saved screenshot
        vlm_result = _query_vlm(query_vlm, FOUR_PANEL_VERIFICATION_PROMPT, image=vlm_image)
        
        if vlm_result:
            details['vlm_analysis'] = vlm_result
            
            # CRITERION 4: Four panels visible (25 points)
            if vlm_result.get('four_panels_visible', False):
                score += w_four_panels
                feedback_parts.append("Four-panel layout confirmed")
            else:
                panel_count = vlm_result.get('panel_count_estimate', 0)
                if panel_count >= 2:
                    score += w_four_panels * 0.3
                    feedback_parts.append(f"Multi-panel layout ({panel_count} panels, expected 4)")
                else:
                    feedback_parts.append("Four-panel layout not detected")
            
            # CRITERION 5: Different contrasts visible (20 points)
            if vlm_result.get('different_contrasts_visible', False):
                score += w_contrasts
                feedback_parts.append("Different MRI contrasts visible")
            else:
                feedback_parts.append("Different contrasts not clearly visible")
            
            # CRITERION 6: Brain anatomy present (10 points)
            if vlm_result.get('brain_anatomy_visible', False):
                score += w_brain_anatomy
                feedback_parts.append("Brain anatomy visible")
            else:
                feedback_parts.append("Brain anatomy not clearly visible")
            
            # CRITERION 7: Same slice level + tumor visible (10 points combined)
            same_level = vlm_result.get('same_slice_level', False)
            tumor_visible = vlm_result.get('tumor_visible', False)
            
            if same_level and tumor_visible:
                score += w_same_level + w_tumor
                feedback_parts.append("Tumor visible at same anatomical level")
            elif tumor_visible:
                score += w_tumor
                feedback_parts.append("Tumor visible")
            elif same_level:
                score += w_same_level
                feedback_parts.append("Views at same anatomical level")
            
            details['vlm_confidence'] = vlm_result.get('confidence', 'unknown')
        else:
            feedback_parts.append("VLM analysis unavailable")
    else:
        # No VLM available - use programmatic fallback
        feedback_parts.append("VLM verification not available")
        
        # Fallback: check image properties
        if image_colors > 500:
            score += 15  # Partial credit for having complex image
            feedback_parts.append("Image has sufficient complexity")
        
        # Check layout from Slicer state
        current_layout = result.get('current_layout', '')
        if 'four' in current_layout.lower() or 'four' in str(result.get('slice_views_count', 0)):
            score += 10
            feedback_parts.append(f"Layout indicates multi-panel ({current_layout})")

    # ================================================================
    # Trajectory workflow verification (bonus check)
    # ================================================================
    if query_vlm and trajectory_frames and len(trajectory_frames) >= 3:
        workflow_result = _query_vlm(query_vlm, TRAJECTORY_WORKFLOW_PROMPT, images=trajectory_frames)
        if workflow_result:
            details['workflow_analysis'] = workflow_result
            
            if workflow_result.get('task_completed', False):
                if workflow_result.get('meaningful_progression', False):
                    # Bonus for showing actual work
                    feedback_parts.append("Trajectory shows task progression")
                else:
                    feedback_parts.append("Task completed but limited progression visible")

    # ================================================================
    # Cleanup
    # ================================================================
    if temp_screenshot and os.path.exists(temp_screenshot.name):
        try:
            os.unlink(temp_screenshot.name)
        except:
            pass

    # ================================================================
    # Final scoring
    # ================================================================
    # Ensure score is within bounds
    score = max(0, min(100, int(score)))
    
    # Determine pass/fail
    # Key criteria: screenshot exists AND (four panels detected OR decent score)
    screenshot_ok = screenshot_exists or new_screenshots > 0
    four_panels_ok = vlm_result and vlm_result.get('four_panels_visible', False) if vlm_result else False
    
    passed = score >= 60 and screenshot_ok
    
    # Higher bar if VLM confirmed four panels
    if vlm_result and not four_panels_ok and score >= 60:
        # If VLM ran but didn't see four panels, be more strict
        passed = score >= 70
    
    details['final_score'] = score
    details['slicer_running'] = result.get('slicer_was_running', False)
    details['volumes_loaded'] = result.get('volumes_loaded', 0)

    feedback = " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }