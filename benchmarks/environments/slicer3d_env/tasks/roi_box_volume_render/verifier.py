#!/usr/bin/env python3
"""
Verifier for ROI Box Volume Rendering task.

VERIFICATION STRATEGY (Multi-criteria with anti-gaming):

Programmatic checks (85 points):
  1. ROI Box Created (15 pts) - An ROI markup node exists in the scene
  2. ROI Reasonable Size (10 pts) - ROI dimensions between 40-160mm per axis
  3. ROI Correct Location (20 pts) - ROI center is in right kidney region (R>30, -60<A<40)
  4. Volume Rendering Active (10 pts) - VR display node exists and is visible
  5. ROI Cropping Enabled (20 pts) - VR display node has ROI cropping linked
  6. Screenshot Exists (10 pts) - Output file created at correct path during task

VLM verification (15 points):
  7. VLM Confirms Isolation (15 pts) - Visual check confirms isolated kidney rendering

Pass threshold: 70 points with ROI_BOX_CREATED and ROI_CROPPING_ENABLED both satisfied
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_roi_box_volume_render(traj, env_info, task_info):
    """
    Verify that ROI box was created and volume rendering is cropped to show kidney.

    Uses multiple independent signals to prevent gaming.
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
    roi_center_range = metadata.get('acceptable_roi_center_range', {
        "R_min": 30, "R_max": 110,
        "A_min": -60, "A_max": 40,
        "S_min": -60, "S_max": 80
    })
    roi_size_range = metadata.get('roi_size_range_mm', {
        "min_per_axis": 40,
        "max_per_axis": 160
    })
    min_screenshot_kb = metadata.get('min_screenshot_size_kb', 50)
    
    weights = metadata.get('scoring_weights', {
        "roi_box_created": 15,
        "roi_reasonable_size": 10,
        "roi_correct_location": 20,
        "volume_rendering_active": 10,
        "roi_cropping_enabled": 20,
        "screenshot_exists": 10,
        "vlm_confirms_isolation": 15
    })

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/roi_task_result.json", temp_result.name)
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
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion"
        }

    # ============================================================
    # CRITERION 1: ROI Box Created (15 points)
    # ============================================================
    roi_exists = result.get('roi_exists', False)
    roi_count = result.get('roi_count', 0)
    
    if roi_exists and roi_count > 0:
        score += weights.get('roi_box_created', 15)
        feedback_parts.append(f"ROI created ({roi_count} node(s))")
        details['roi_created'] = True
    else:
        feedback_parts.append("No ROI box created")
        details['roi_created'] = False
        # Cannot proceed meaningfully without ROI
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }

    # ============================================================
    # CRITERION 2: ROI Reasonable Size (10 points)
    # ============================================================
    roi_size_x = float(result.get('roi_size_x', 0))
    roi_size_y = float(result.get('roi_size_y', 0))
    roi_size_z = float(result.get('roi_size_z', 0))
    
    min_size = roi_size_range.get('min_per_axis', 40)
    max_size = roi_size_range.get('max_per_axis', 160)
    
    sizes_valid = (
        min_size <= roi_size_x <= max_size and
        min_size <= roi_size_y <= max_size and
        min_size <= roi_size_z <= max_size
    )
    
    details['roi_size'] = [roi_size_x, roi_size_y, roi_size_z]
    
    if sizes_valid:
        score += weights.get('roi_reasonable_size', 10)
        feedback_parts.append(f"ROI size OK ({roi_size_x:.0f}x{roi_size_y:.0f}x{roi_size_z:.0f}mm)")
        details['roi_size_valid'] = True
    elif roi_size_x > 0 and roi_size_y > 0 and roi_size_z > 0:
        # Partial credit for having some size
        score += weights.get('roi_reasonable_size', 10) // 2
        feedback_parts.append(f"ROI size unusual ({roi_size_x:.0f}x{roi_size_y:.0f}x{roi_size_z:.0f}mm)")
        details['roi_size_valid'] = False
    else:
        feedback_parts.append("ROI size invalid/zero")
        details['roi_size_valid'] = False

    # ============================================================
    # CRITERION 3: ROI Correct Location (20 points)
    # Right kidney should have positive R (patient's right), 
    # A roughly central, S varies
    # ============================================================
    roi_center_r = float(result.get('roi_center_r', 0))
    roi_center_a = float(result.get('roi_center_a', 0))
    roi_center_s = float(result.get('roi_center_s', 0))
    
    details['roi_center'] = [roi_center_r, roi_center_a, roi_center_s]
    
    r_valid = roi_center_range.get('R_min', 30) <= roi_center_r <= roi_center_range.get('R_max', 110)
    a_valid = roi_center_range.get('A_min', -60) <= roi_center_a <= roi_center_range.get('A_max', 40)
    s_valid = roi_center_range.get('S_min', -60) <= roi_center_s <= roi_center_range.get('S_max', 80)
    
    location_score = 0
    if r_valid:
        location_score += weights.get('roi_correct_location', 20) * 0.5  # R is most important
    if a_valid:
        location_score += weights.get('roi_correct_location', 20) * 0.25
    if s_valid:
        location_score += weights.get('roi_correct_location', 20) * 0.25
    
    score += int(location_score)
    
    if r_valid and a_valid and s_valid:
        feedback_parts.append(f"ROI location correct (R={roi_center_r:.0f})")
        details['roi_location_valid'] = True
    elif r_valid:
        feedback_parts.append(f"ROI on right side (R={roi_center_r:.0f})")
        details['roi_location_valid'] = "partial"
    else:
        feedback_parts.append(f"ROI location may be wrong (R={roi_center_r:.0f})")
        details['roi_location_valid'] = False

    # ============================================================
    # CRITERION 4: Volume Rendering Active (10 points)
    # ============================================================
    vr_active = result.get('volume_rendering_active', False)
    
    if vr_active:
        score += weights.get('volume_rendering_active', 10)
        feedback_parts.append("VR active")
        details['vr_active'] = True
    else:
        feedback_parts.append("VR not active")
        details['vr_active'] = False

    # ============================================================
    # CRITERION 5: ROI Cropping Enabled (20 points)
    # This is a KEY criterion
    # ============================================================
    roi_cropping = result.get('roi_cropping_enabled', False)
    roi_linked = result.get('roi_linked_to_vr', False)
    
    if roi_cropping and roi_linked:
        score += weights.get('roi_cropping_enabled', 20)
        feedback_parts.append("ROI cropping enabled")
        details['roi_cropping_enabled'] = True
    elif roi_cropping or roi_linked:
        score += weights.get('roi_cropping_enabled', 20) // 2
        feedback_parts.append("ROI cropping partial")
        details['roi_cropping_enabled'] = "partial"
    else:
        feedback_parts.append("ROI cropping NOT enabled")
        details['roi_cropping_enabled'] = False

    # ============================================================
    # CRITERION 6: Screenshot Exists (10 points)
    # ============================================================
    screenshot_exists = result.get('screenshot_exists', False)
    screenshot_size = result.get('screenshot_size_kb', 0)
    screenshot_during_task = result.get('screenshot_created_during_task', False)
    
    if screenshot_exists and screenshot_during_task and screenshot_size >= min_screenshot_kb:
        score += weights.get('screenshot_exists', 10)
        feedback_parts.append(f"Screenshot saved ({screenshot_size}KB)")
        details['screenshot_valid'] = True
    elif screenshot_exists and screenshot_size > 0:
        score += weights.get('screenshot_exists', 10) // 2
        feedback_parts.append(f"Screenshot exists ({screenshot_size}KB)")
        details['screenshot_valid'] = "partial"
    else:
        feedback_parts.append("No valid screenshot")
        details['screenshot_valid'] = False

    # ============================================================
    # CRITERION 7: VLM Confirms Isolation (15 points)
    # Use trajectory frames to verify work progression and final state
    # ============================================================
    vlm_score = 0
    vlm_feedback = "VLM check skipped"
    
    try:
        # Try to import VLM utilities
        from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
        
        # Sample trajectory frames for process verification
        trajectory_frames = sample_trajectory_frames(traj, n=4) if traj else []
        final_frame = get_final_screenshot(traj) if traj else None
        
        if final_frame or trajectory_frames:
            # Combine for VLM analysis - use trajectory + final
            all_frames = trajectory_frames + ([final_frame] if final_frame else [])
            
            vlm_prompt = """Analyze these screenshots from a 3D Slicer medical imaging task.

The task was to:
1. Create a 3D ROI (Region of Interest) box around the kidney
2. Configure volume rendering to show ONLY the anatomy inside that box

Look at the progression of screenshots and the final state.

Evaluate:
1. WORKFLOW_PROGRESSION: Do the images show the user working with Slicer?
2. ROI_BOX_VISIBLE: Is there a rectangular 3D ROI box visible in any frame?
3. ISOLATED_RENDERING: In the final frames, does the 3D view show ISOLATED anatomy (not full body)?
   - A successful task shows ONLY a small organ region (kidney), not the entire spine/pelvis/torso
   - Look for: cropped/bounded 3D rendering, single organ visible
4. KIDNEY_LIKE_SHAPE: Does the isolated region look like a kidney (bean-shaped, ~10cm length)?

Respond in JSON format:
{
    "workflow_visible": true/false,
    "roi_box_visible": true/false,
    "isolated_rendering": true/false,
    "kidney_shape_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "what you see in the images"
}"""

            vlm_result = query_vlm(prompt=vlm_prompt, images=all_frames)
            
            if vlm_result and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                details['vlm_result'] = parsed
                
                isolated = parsed.get('isolated_rendering', False)
                roi_visible = parsed.get('roi_box_visible', False)
                kidney_visible = parsed.get('kidney_shape_visible', False)
                confidence = parsed.get('confidence', 'low')
                
                if isolated and (roi_visible or kidney_visible):
                    vlm_score = weights.get('vlm_confirms_isolation', 15)
                    vlm_feedback = "VLM confirms isolated kidney render"
                elif isolated or kidney_visible:
                    vlm_score = weights.get('vlm_confirms_isolation', 15) * 2 // 3
                    vlm_feedback = "VLM partial confirmation"
                elif roi_visible:
                    vlm_score = weights.get('vlm_confirms_isolation', 15) // 3
                    vlm_feedback = "VLM sees ROI but not isolation"
                else:
                    vlm_feedback = "VLM cannot confirm isolation"
                
                details['vlm_observations'] = parsed.get('observations', '')
            else:
                vlm_feedback = "VLM query failed"
                details['vlm_error'] = vlm_result.get('error') if vlm_result else "No result"
        else:
            vlm_feedback = "No frames available for VLM"
            
    except ImportError:
        vlm_feedback = "VLM module not available"
    except Exception as e:
        vlm_feedback = f"VLM error: {str(e)[:50]}"
        details['vlm_error'] = str(e)

    score += vlm_score
    feedback_parts.append(vlm_feedback)

    # ============================================================
    # FINAL SCORING
    # ============================================================
    max_score = sum(weights.values())
    normalized_score = int((score / max_score) * 100) if max_score > 0 else 0
    
    # Key criteria check
    roi_created = details.get('roi_created', False)
    cropping_enabled = details.get('roi_cropping_enabled', False)
    
    key_criteria_met = roi_created and (cropping_enabled == True or cropping_enabled == "partial")
    
    # Pass threshold: 70 points with key criteria
    passed = normalized_score >= 70 and key_criteria_met
    
    # Provide helpful feedback if close but not passing
    if normalized_score >= 60 and not passed:
        if not roi_created:
            feedback_parts.append("HINT: Create an ROI box first")
        elif not cropping_enabled:
            feedback_parts.append("HINT: Enable ROI cropping in Volume Rendering module")

    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": normalized_score,
        "feedback": feedback,
        "details": details
    }