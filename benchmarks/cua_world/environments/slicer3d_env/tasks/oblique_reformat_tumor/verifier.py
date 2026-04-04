#!/usr/bin/env python3
"""
Verifier for oblique_reformat_tumor task.

VERIFICATION STRATEGY (Hybrid: Programmatic + VLM on Trajectory):

Programmatic checks (95 points):
1. Oblique Orientation Achieved (35 pts) - slice normal >15° from all standard orientations
2. Tumor Visible in Slice (30 pts) - slice passes within 10mm of tumor centroid
3. Slice Through Tumor Center (20 pts) - slice within 5mm of tumor center
4. Orientation Changed from Initial (10 pts) - agent actually modified the slice

VLM check (5 points):
5. Visual Confirmation (5 pts) - trajectory shows Reformat module usage and brain visible

Pass threshold: 65 points with Oblique Orientation Achieved (35 pts)
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_oblique_reformat_tumor(traj, env_info, task_info):
    """
    Verify that agent created an oblique slice reformat through the tumor.
    
    Uses MULTIPLE INDEPENDENT SIGNALS to prevent gaming:
    1. Slice orientation matrix analysis (programmatic)
    2. Tumor intersection check (programmatic)
    3. Before/after orientation comparison (anti-gaming)
    4. VLM trajectory verification (visual evidence)
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
    min_angle_deg = metadata.get('min_angle_deviation_degrees', 15)
    max_distance_mm = metadata.get('max_distance_to_tumor_mm', 10)
    
    weights = metadata.get('scoring_weights', {})
    w_oblique = weights.get('oblique_orientation_achieved', 35)
    w_tumor_visible = weights.get('tumor_visible_in_slice', 30)
    w_tumor_center = weights.get('slice_through_tumor_center', 20)
    w_orientation_changed = weights.get('orientation_changed', 10)
    w_vlm = weights.get('vlm_visual_confirmation', 5)
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {}
    
    # ================================================================
    # Copy result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/oblique_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        details['result_loaded'] = True
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
    
    # Check basic requirements
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task"
        }
    
    if not result.get('final_state_extracted', False):
        feedback_parts.append("Could not extract final slice state")
        # Continue with partial verification
    
    # ================================================================
    # CRITERION 1: Oblique Orientation Achieved (35 points)
    # ================================================================
    is_oblique = result.get('is_oblique', False)
    min_angle_from_standard = result.get('min_angle_from_standard_deg', 0)
    
    details['is_oblique'] = is_oblique
    details['min_angle_from_standard_deg'] = min_angle_from_standard
    details['angle_from_axial_deg'] = result.get('angle_from_axial_deg', 0)
    details['angle_from_sagittal_deg'] = result.get('angle_from_sagittal_deg', 0)
    details['angle_from_coronal_deg'] = result.get('angle_from_coronal_deg', 0)
    
    oblique_achieved = False
    if is_oblique and min_angle_from_standard >= min_angle_deg:
        score += w_oblique
        oblique_achieved = True
        feedback_parts.append(f"Oblique orientation achieved ({min_angle_from_standard:.1f}° from standard)")
    elif min_angle_from_standard >= min_angle_deg * 0.6:  # Partial credit for >9 degrees
        partial_score = int(w_oblique * 0.5)
        score += partial_score
        feedback_parts.append(f"Partial oblique ({min_angle_from_standard:.1f}°, need {min_angle_deg}°)")
    elif min_angle_from_standard > 0:
        feedback_parts.append(f"Not oblique enough ({min_angle_from_standard:.1f}°, need {min_angle_deg}°)")
    else:
        feedback_parts.append("Slice still in standard orientation")
    
    # ================================================================
    # CRITERION 2: Tumor Visible in Slice (30 points)
    # ================================================================
    tumor_visible = result.get('tumor_visible', False)
    distance_to_tumor = result.get('distance_to_tumor_mm', 999)
    
    details['tumor_visible'] = tumor_visible
    details['distance_to_tumor_mm'] = distance_to_tumor
    
    if tumor_visible and distance_to_tumor <= max_distance_mm:
        score += w_tumor_visible
        feedback_parts.append(f"Tumor visible in slice ({distance_to_tumor:.1f}mm from center)")
    elif distance_to_tumor <= max_distance_mm * 2:  # Partial credit
        partial_score = int(w_tumor_visible * 0.5)
        score += partial_score
        feedback_parts.append(f"Tumor partially visible ({distance_to_tumor:.1f}mm)")
    elif distance_to_tumor < 50:
        partial_score = int(w_tumor_visible * 0.25)
        score += partial_score
        feedback_parts.append(f"Tumor nearby but not in slice ({distance_to_tumor:.1f}mm)")
    else:
        feedback_parts.append(f"Tumor not visible (distance: {distance_to_tumor:.1f}mm)")
    
    # ================================================================
    # CRITERION 3: Slice Through Tumor Center (20 points)
    # ================================================================
    close_to_center_mm = 5.0  # Within 5mm of center for full points
    
    if distance_to_tumor <= close_to_center_mm:
        score += w_tumor_center
        feedback_parts.append(f"Slice through tumor center ({distance_to_tumor:.1f}mm)")
    elif distance_to_tumor <= max_distance_mm:
        # Partial credit based on distance
        ratio = 1.0 - (distance_to_tumor - close_to_center_mm) / (max_distance_mm - close_to_center_mm)
        partial_score = int(w_tumor_center * max(0.3, ratio))
        score += partial_score
        feedback_parts.append(f"Slice near tumor center ({distance_to_tumor:.1f}mm)")
    
    # ================================================================
    # CRITERION 4: Orientation Changed from Initial (10 points)
    # Anti-gaming: detect if agent actually did work
    # ================================================================
    orientation_changed = result.get('orientation_changed', False)
    orientation_change_deg = result.get('orientation_change_degrees', 0)
    
    details['orientation_changed'] = orientation_changed
    details['orientation_change_degrees'] = orientation_change_deg
    
    if orientation_changed and orientation_change_deg >= 5.0:
        score += w_orientation_changed
        feedback_parts.append(f"Orientation modified ({orientation_change_deg:.1f}° change)")
    elif orientation_change_deg > 0:
        partial_score = int(w_orientation_changed * 0.5)
        score += partial_score
        feedback_parts.append(f"Small orientation change ({orientation_change_deg:.1f}°)")
    else:
        feedback_parts.append("No orientation change detected (possible gaming)")
    
    # ================================================================
    # CRITERION 5: VLM Visual Confirmation (5 points)
    # ================================================================
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        # Sample frames from trajectory
        frames = sample_trajectory_frames(traj, n=4)
        
        if frames and len(frames) > 0:
            vlm_prompt = """Analyze these screenshots from a medical imaging task in 3D Slicer.

The agent was asked to create an oblique slice reformat through a brain tumor.

Look for evidence of:
1. The Reformat module being used (a panel with rotation sliders LR/PA/IS)
2. Brain MRI visible in slice views
3. Changes in slice orientation across the screenshots
4. The slice view showing brain tissue (not just empty or outside the volume)

Respond in JSON:
{
    "reformat_module_visible": true/false,
    "brain_visible": true/false,
    "orientation_appears_changed": true/false,
    "workflow_progression": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description"
}
"""
            vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
            
            if vlm_result and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                details['vlm_result'] = parsed
                
                reformat_visible = parsed.get('reformat_module_visible', False)
                brain_visible = parsed.get('brain_visible', False)
                workflow_ok = parsed.get('workflow_progression', False)
                
                vlm_score = 0
                if brain_visible:
                    vlm_score += 2
                if reformat_visible or workflow_ok:
                    vlm_score += 2
                if parsed.get('orientation_appears_changed', False):
                    vlm_score += 1
                
                score += min(vlm_score, w_vlm)
                
                if vlm_score >= 3:
                    feedback_parts.append("VLM confirms workflow")
                elif vlm_score > 0:
                    feedback_parts.append("VLM partial confirmation")
                else:
                    feedback_parts.append("VLM could not confirm workflow")
            else:
                feedback_parts.append("VLM verification failed")
                details['vlm_error'] = vlm_result.get('error', 'unknown') if vlm_result else 'no result'
        else:
            feedback_parts.append("No trajectory frames for VLM")
            
    except ImportError:
        feedback_parts.append("VLM not available")
        details['vlm_error'] = "module not available"
    except Exception as e:
        feedback_parts.append(f"VLM error: {str(e)[:30]}")
        details['vlm_error'] = str(e)
    
    # ================================================================
    # DETERMINE PASS/FAIL
    # ================================================================
    # Key requirement: must achieve oblique orientation (35 pts criterion)
    # Pass threshold: 65 points with oblique achieved
    
    key_criteria_met = oblique_achieved
    passed = score >= 65 and key_criteria_met
    
    details['score_breakdown'] = {
        'oblique_orientation': w_oblique if oblique_achieved else 0,
        'tumor_visible': w_tumor_visible if tumor_visible else 0,
        'tumor_center': w_tumor_center if distance_to_tumor <= close_to_center_mm else 0,
        'orientation_changed': w_orientation_changed if orientation_changed else 0,
        'vlm_confirmation': min(score - (w_oblique + w_tumor_visible + w_tumor_center + w_orientation_changed), w_vlm)
    }
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }