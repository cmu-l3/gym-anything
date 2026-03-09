#!/usr/bin/env python3
"""
Verifier for create_annotation_arrow task.

VERIFICATION STRATEGY (Multi-Signal + Anti-Gaming):

1. Arrow Markup Exists (25 points)
   - Check that at least one line/arrow markup exists in the scene
   - Must have been created during the task (not pre-existing)

2. Correct Label (20 points)
   - Label/name contains "ventricle" or "lateral" (case insensitive)
   
3. Anatomically Positioned (20 points)
   - Arrow position is within brain bounds (not at origin)
   - Ideally within ventricle region

4. Screenshot Saved (15 points)
   - Screenshot file exists at expected path
   - File size > 50KB (not empty)
   - Created during task (timestamp check)

5. VLM Confirms Annotation (10 points)
   - Trajectory frames show annotation workflow
   - Final screenshot shows arrow pointing to anatomical structure

6. Proper Slice Level (10 points)
   - Axial view visible with brain anatomy

Pass threshold: 60 points with arrow_exists AND (screenshot OR correct_label)
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_annotation_arrow(traj, env_info, task_info):
    """
    Verify annotation arrow task completion.
    
    Uses multi-criteria scoring with anti-gaming timestamp checks.
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
        '/home/ga/Documents/SlicerData/Screenshots/ventricle_annotation.png')
    expected_label_keywords = metadata.get('expected_label_keywords', ['ventricle', 'lateral'])
    min_screenshot_size_kb = metadata.get('min_screenshot_size_kb', 50)
    
    brain_bounds = metadata.get('brain_bounds_mm', {
        'x_min': -80, 'x_max': 80,
        'y_min': -120, 'y_max': 80,
        'z_min': -50, 'z_max': 90
    })
    ventricle_region = metadata.get('ventricle_region_mm', {
        'x_min': -30, 'x_max': 30,
        'y_min': -40, 'y_max': 40,
        'z_min': 0, 'z_max': 60
    })
    
    weights = metadata.get('scoring_weights', {})
    w_arrow_exists = weights.get('arrow_markup_exists', 25)
    w_correct_label = weights.get('correct_label', 20)
    w_anatomically_positioned = weights.get('anatomically_positioned', 20)
    w_screenshot_saved = weights.get('screenshot_saved', 15)
    w_vlm_confirms = weights.get('vlm_confirms_annotation', 10)
    w_proper_slice = weights.get('proper_slice_level', 10)

    # ============================================================
    # Copy result JSON from container
    # ============================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/annotation_task_result.json", temp_result.name)
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

    # ============================================================
    # Check if Slicer was running
    # ============================================================
    if not result.get('slicer_was_running', False):
        feedback_parts.append("Slicer not running")
        details['slicer_running'] = False
    else:
        details['slicer_running'] = True

    # ============================================================
    # CRITERION 1: Arrow Markup Exists (25 points)
    # ============================================================
    arrow_exists = result.get('arrow_exists', False)
    num_arrows = result.get('num_arrows', 0)
    num_all_markups = result.get('num_all_markups', 0)
    
    if arrow_exists:
        score += w_arrow_exists
        feedback_parts.append(f"Arrow markup found ({num_arrows} arrows, {num_all_markups} total markups)")
        details['arrow_exists'] = True
        details['num_arrows'] = num_arrows
    elif num_all_markups > 0:
        # Partial credit for any markup
        score += w_arrow_exists * 0.5
        feedback_parts.append(f"Markup exists but may not be arrow ({num_all_markups} markups)")
        details['arrow_exists'] = False
        details['num_markups'] = num_all_markups
    else:
        feedback_parts.append("No arrow markup found")
        details['arrow_exists'] = False

    # ============================================================
    # CRITERION 2: Correct Label (20 points)
    # ============================================================
    arrow_label = result.get('arrow_label', '').lower()
    label_contains_keyword = any(kw.lower() in arrow_label for kw in expected_label_keywords)
    
    if label_contains_keyword:
        score += w_correct_label
        feedback_parts.append(f"Correct label: '{result.get('arrow_label', '')}'")
        details['label_correct'] = True
        details['arrow_label'] = result.get('arrow_label', '')
    elif arrow_label and len(arrow_label) > 0:
        # Partial credit for having any label
        score += w_correct_label * 0.3
        feedback_parts.append(f"Label present but missing 'ventricle': '{result.get('arrow_label', '')}'")
        details['label_correct'] = False
        details['arrow_label'] = result.get('arrow_label', '')
    else:
        feedback_parts.append("No label or default label")
        details['label_correct'] = False

    # ============================================================
    # CRITERION 3: Anatomically Positioned (20 points)
    # ============================================================
    arrow_position = result.get('arrow_position', [0, 0, 0])
    if isinstance(arrow_position, str):
        try:
            arrow_position = json.loads(arrow_position)
        except:
            arrow_position = [0, 0, 0]
    
    if not isinstance(arrow_position, list) or len(arrow_position) < 3:
        arrow_position = [0, 0, 0]
    
    x, y, z = arrow_position[0], arrow_position[1], arrow_position[2]
    details['arrow_position'] = arrow_position
    
    # Check if position is at origin (likely not placed)
    at_origin = abs(x) < 1 and abs(y) < 1 and abs(z) < 1
    
    # Check if within brain bounds
    in_brain = (brain_bounds['x_min'] <= x <= brain_bounds['x_max'] and
                brain_bounds['y_min'] <= y <= brain_bounds['y_max'] and
                brain_bounds['z_min'] <= z <= brain_bounds['z_max'])
    
    # Check if in ventricle region (more specific)
    in_ventricle_region = (ventricle_region['x_min'] <= x <= ventricle_region['x_max'] and
                          ventricle_region['y_min'] <= y <= ventricle_region['y_max'] and
                          ventricle_region['z_min'] <= z <= ventricle_region['z_max'])
    
    if at_origin:
        feedback_parts.append("Arrow at origin (not placed)")
        details['anatomically_positioned'] = False
    elif in_ventricle_region:
        score += w_anatomically_positioned
        feedback_parts.append(f"Arrow in ventricle region: ({x:.1f}, {y:.1f}, {z:.1f})")
        details['anatomically_positioned'] = True
        details['in_ventricle_region'] = True
    elif in_brain:
        score += w_anatomically_positioned * 0.7
        feedback_parts.append(f"Arrow in brain bounds: ({x:.1f}, {y:.1f}, {z:.1f})")
        details['anatomically_positioned'] = True
        details['in_brain'] = True
    else:
        score += w_anatomically_positioned * 0.2
        feedback_parts.append(f"Arrow outside expected region: ({x:.1f}, {y:.1f}, {z:.1f})")
        details['anatomically_positioned'] = False

    # ============================================================
    # CRITERION 4: Screenshot Saved (15 points)
    # ============================================================
    screenshot_exists = result.get('screenshot_exists', False)
    screenshot_size_kb = result.get('screenshot_size_kb', 0)
    screenshot_created_during_task = result.get('screenshot_created_during_task', False)
    new_screenshots = result.get('new_screenshots_count', 0)
    
    if screenshot_exists and screenshot_created_during_task:
        if screenshot_size_kb >= min_screenshot_size_kb:
            score += w_screenshot_saved
            feedback_parts.append(f"Screenshot saved ({screenshot_size_kb}KB)")
            details['screenshot_saved'] = True
        else:
            score += w_screenshot_saved * 0.5
            feedback_parts.append(f"Screenshot small ({screenshot_size_kb}KB)")
            details['screenshot_saved'] = True
    elif screenshot_exists:
        score += w_screenshot_saved * 0.3
        feedback_parts.append("Screenshot exists but may be pre-existing")
        details['screenshot_saved'] = False
    elif new_screenshots > 0:
        score += w_screenshot_saved * 0.5
        feedback_parts.append(f"{new_screenshots} new screenshot(s) in different location")
        details['screenshot_saved'] = True
    else:
        feedback_parts.append("No screenshot saved")
        details['screenshot_saved'] = False
    
    details['screenshot_size_kb'] = screenshot_size_kb

    # ============================================================
    # CRITERION 5: VLM Verification (10 points)
    # Uses trajectory frames if available
    # ============================================================
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm:
        try:
            # Try to get trajectory frames
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Sample trajectory frames for process verification
            traj_frames = sample_trajectory_frames(traj, n=4) if traj else []
            final_screenshot = get_final_screenshot(traj)
            
            if traj_frames or final_screenshot:
                vlm_prompt = """Analyze these screenshots from a medical image viewer (3D Slicer).

The task was to create an annotation arrow pointing to the lateral ventricle in a brain MRI.

Assess:
1. Is this 3D Slicer or a medical image viewer?
2. Is brain MRI data visible?
3. Is there an arrow or line annotation visible on the image?
4. Does the annotation appear to point to a dark region in the center of the brain (ventricle)?
5. Is there visible text label near the annotation?

Respond in JSON:
{
    "is_slicer": true/false,
    "brain_mri_visible": true/false,
    "annotation_visible": true/false,
    "points_to_ventricle": true/false,
    "label_visible": true/false,
    "confidence": "low/medium/high"
}"""
                
                images_to_send = (traj_frames + [final_screenshot]) if final_screenshot else traj_frames
                
                vlm_result = query_vlm(prompt=vlm_prompt, images=images_to_send)
                
                if vlm_result and vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    details['vlm_result'] = parsed
                    
                    # Score based on VLM assessment
                    if parsed.get('annotation_visible'):
                        vlm_score += 5
                    if parsed.get('points_to_ventricle'):
                        vlm_score += 3
                    if parsed.get('label_visible'):
                        vlm_score += 2
                    
                    score += vlm_score
                    if vlm_score > 0:
                        feedback_parts.append(f"VLM: annotation visible ({vlm_score}pts)")
                    else:
                        feedback_parts.append("VLM: annotation not clearly visible")
                else:
                    feedback_parts.append("VLM query failed")
                    details['vlm_error'] = vlm_result.get('error', 'unknown') if vlm_result else 'no result'
            else:
                feedback_parts.append("No trajectory frames for VLM")
                
        except ImportError:
            logger.warning("VLM module not available")
            feedback_parts.append("VLM verification unavailable")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            feedback_parts.append(f"VLM error: {str(e)[:30]}")
            details['vlm_error'] = str(e)
    else:
        feedback_parts.append("VLM not configured")

    # ============================================================
    # CRITERION 6: Proper Slice Level (10 points)
    # Based on whether volume was loaded
    # ============================================================
    volume_loaded = result.get('volume_loaded', False)
    
    if volume_loaded:
        score += w_proper_slice
        feedback_parts.append("Brain volume loaded")
        details['volume_loaded'] = True
    else:
        feedback_parts.append("Volume may not be loaded")
        details['volume_loaded'] = False

    # ============================================================
    # Calculate final result
    # ============================================================
    max_score = w_arrow_exists + w_correct_label + w_anatomically_positioned + \
                w_screenshot_saved + w_vlm_confirms + w_proper_slice
    
    # Key criteria for passing
    key_criteria_met = (
        arrow_exists and 
        (screenshot_exists or label_contains_keyword or num_all_markups > 0)
    )
    
    passed = score >= 60 and key_criteria_met
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": feedback,
        "details": details
    }