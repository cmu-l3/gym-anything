#!/usr/bin/env python3
"""
Verifier for smooth_surface_model task.

VERIFICATION STRATEGY (Multi-Signal):

Programmatic checks (85 points):
1. Smoothed model file exists (20 pts)
2. File created during task - anti-gaming (5 pts implicit in #1)
3. Roughness reduced ≥30% (25 pts)
4. Shape preserved - volume change <10% (15 pts)
5. Shape preserved - bounds change <5% (10 pts)
6. Polygon count valid >1000 (10 pts)
7. Model appropriately named (5 pts)

VLM trajectory verification (15 points):
8. Visual confirmation of smoother surface (15 pts)

Pass threshold: 60 points with roughness_reduced AND shape_preserved_volume
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_smooth_surface_model(traj, env_info, task_info):
    """
    Verify that the agent smoothed the surface model correctly.
    
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
    min_roughness_reduction = metadata.get('min_roughness_reduction_percent', 30)
    max_volume_change = metadata.get('max_volume_change_percent', 10)
    max_bounds_change = metadata.get('max_bounds_change_percent', 5)
    min_polygon_count = metadata.get('min_polygon_count', 1000)
    
    weights = metadata.get('scoring_weights', {})
    w_exists = weights.get('smoothed_model_exists', 20)
    w_roughness = weights.get('roughness_reduced', 25)
    w_volume = weights.get('shape_preserved_volume', 15)
    w_bounds = weights.get('shape_preserved_bounds', 10)
    w_polygons = weights.get('polygon_count_valid', 10)
    w_naming = weights.get('appropriate_naming', 5)
    w_vlm = weights.get('vlm_visual_quality', 15)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/smooth_task_result.json", temp_result.name)
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
        feedback_parts.append("Slicer was not running")
    
    # ================================================================
    # CRITERION 1: Smoothed model exists (20 points)
    # ================================================================
    output_exists = result.get('output_model_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    output_size = result.get('output_size_bytes', 0)
    
    if output_exists and file_created_during_task:
        score += w_exists
        feedback_parts.append(f"Smoothed model created ({output_size} bytes)")
        details['model_exists'] = True
        details['file_created_during_task'] = True
    elif output_exists:
        # File exists but wasn't created during task - possible pre-existing or copied
        score += w_exists // 2
        feedback_parts.append("Model exists but may not be newly created")
        details['model_exists'] = True
        details['file_created_during_task'] = False
    else:
        feedback_parts.append("Smoothed model NOT created")
        details['model_exists'] = False
        # Early exit - can't verify anything else
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # Get metrics from result
    metrics = result.get('metrics', {})
    roughness_reduction = metrics.get('roughness_reduction_percent', 0)
    volume_change = metrics.get('volume_change_percent', 0)
    bounds_change = metrics.get('bounds_change_percent', 0)
    polygon_count = metrics.get('smoothed_polygon_count', 0)
    orig_curvature = metrics.get('original_curvature_variance', 0)
    smooth_curvature = metrics.get('smoothed_curvature_variance', 0)
    
    details['metrics'] = metrics
    
    # ================================================================
    # CRITERION 2: Roughness reduced ≥30% (25 points)
    # ================================================================
    if roughness_reduction >= min_roughness_reduction:
        score += w_roughness
        feedback_parts.append(f"Roughness reduced {roughness_reduction:.1f}%")
        details['roughness_improved'] = True
    elif roughness_reduction > 0:
        # Partial credit for some improvement
        partial = int(w_roughness * roughness_reduction / min_roughness_reduction)
        score += partial
        feedback_parts.append(f"Roughness reduced {roughness_reduction:.1f}% (target: {min_roughness_reduction}%)")
        details['roughness_improved'] = False
    elif roughness_reduction < 0:
        # Model got rougher - definitely wrong
        feedback_parts.append(f"Roughness INCREASED by {abs(roughness_reduction):.1f}%")
        details['roughness_improved'] = False
    else:
        feedback_parts.append("No roughness improvement detected")
        details['roughness_improved'] = False
    
    # ================================================================
    # CRITERION 3: Shape preserved - volume (15 points)
    # ================================================================
    if volume_change <= max_volume_change:
        score += w_volume
        feedback_parts.append(f"Volume preserved (change: {volume_change:.1f}%)")
        details['volume_preserved'] = True
    elif volume_change <= max_volume_change * 1.5:
        # Partial credit
        score += w_volume // 2
        feedback_parts.append(f"Volume somewhat preserved (change: {volume_change:.1f}%)")
        details['volume_preserved'] = False
    else:
        feedback_parts.append(f"Volume NOT preserved (change: {volume_change:.1f}%)")
        details['volume_preserved'] = False
    
    # ================================================================
    # CRITERION 4: Shape preserved - bounds (10 points)
    # ================================================================
    if bounds_change <= max_bounds_change:
        score += w_bounds
        feedback_parts.append(f"Bounds preserved (change: {bounds_change:.1f}%)")
        details['bounds_preserved'] = True
    elif bounds_change <= max_bounds_change * 2:
        score += w_bounds // 2
        feedback_parts.append(f"Bounds somewhat preserved (change: {bounds_change:.1f}%)")
        details['bounds_preserved'] = False
    else:
        feedback_parts.append(f"Bounds NOT preserved (change: {bounds_change:.1f}%)")
        details['bounds_preserved'] = False
    
    # ================================================================
    # CRITERION 5: Polygon count valid (10 points)
    # ================================================================
    if polygon_count >= min_polygon_count:
        score += w_polygons
        feedback_parts.append(f"Valid polygon count ({polygon_count})")
        details['valid_mesh'] = True
    elif polygon_count > min_polygon_count // 2:
        score += w_polygons // 2
        feedback_parts.append(f"Low polygon count ({polygon_count})")
        details['valid_mesh'] = False
    else:
        feedback_parts.append(f"Mesh destroyed or invalid ({polygon_count} polygons)")
        details['valid_mesh'] = False
    
    # ================================================================
    # CRITERION 6: Appropriate naming (5 points)
    # ================================================================
    output_path = result.get('output_model_path', '')
    if 'smooth' in output_path.lower() or 'Smoothed' in output_path:
        score += w_naming
        feedback_parts.append("Appropriately named")
        details['naming_correct'] = True
    else:
        feedback_parts.append("Model not named with 'Smooth'")
        details['naming_correct'] = False
    
    # ================================================================
    # CRITERION 7: VLM visual verification (15 points)
    # ================================================================
    vlm_score = 0
    vlm_feedback = ""
    
    try:
        # Try to get VLM functions from env_info
        query_vlm = env_info.get('query_vlm')
        
        if query_vlm and traj:
            # Import VLM utilities
            try:
                from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
                
                # Sample trajectory frames for process verification
                frames = sample_trajectory_frames(traj, n=4)
                final_screenshot = get_final_screenshot(traj)
                
                if frames or final_screenshot:
                    all_images = frames + ([final_screenshot] if final_screenshot else [])
                    
                    vlm_prompt = """Analyze these screenshots from a 3D Slicer mesh smoothing task.

The agent should have:
1. Opened Surface Toolbox or a smoothing module
2. Applied smoothing to a rough tumor model
3. Created a visually smoother result

Look at the 3D views and assess:
- Is there a 3D model visible?
- Does the model appear smooth (no obvious stair-step artifacts)?
- Is the Surface Toolbox module or smoothing dialog visible in any frame?
- Does the workflow show progression from rough to smooth model?

Respond in JSON:
{
    "model_visible": true/false,
    "model_appears_smooth": true/false,
    "smoothing_workflow_visible": true/false,
    "surface_toolbox_used": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description"
}"""
                    
                    vlm_result = query_vlm(prompt=vlm_prompt, images=all_images)
                    
                    if vlm_result and vlm_result.get('success'):
                        parsed = vlm_result.get('parsed', {})
                        
                        model_visible = parsed.get('model_visible', False)
                        model_smooth = parsed.get('model_appears_smooth', False)
                        workflow_visible = parsed.get('smoothing_workflow_visible', False)
                        confidence = parsed.get('confidence', 'low')
                        
                        details['vlm_result'] = parsed
                        
                        if model_visible and model_smooth:
                            if confidence in ['medium', 'high']:
                                vlm_score = w_vlm
                                vlm_feedback = "VLM confirms smooth model visible"
                            else:
                                vlm_score = w_vlm // 2
                                vlm_feedback = "VLM: model appears smooth (low confidence)"
                        elif model_visible:
                            vlm_score = w_vlm // 3
                            vlm_feedback = "VLM: model visible but smoothness unclear"
                        else:
                            vlm_feedback = "VLM: could not verify model smoothness"
                    else:
                        vlm_feedback = "VLM query failed"
                else:
                    vlm_feedback = "No screenshots available for VLM"
            except ImportError:
                vlm_feedback = "VLM utilities not available"
        else:
            vlm_feedback = "VLM not configured"
    except Exception as e:
        vlm_feedback = f"VLM error: {str(e)}"
        logger.warning(f"VLM verification failed: {e}")
    
    score += vlm_score
    if vlm_feedback:
        feedback_parts.append(vlm_feedback)
    details['vlm_score'] = vlm_score
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    
    # Key criteria for passing
    roughness_improved = details.get('roughness_improved', False)
    volume_preserved = details.get('volume_preserved', False)
    model_exists = details.get('model_exists', False)
    
    # Pass requires: score >= 60 AND key criteria met
    key_criteria_met = model_exists and (roughness_improved or roughness_reduction > 15) and volume_preserved
    passed = score >= 60 and key_criteria_met
    
    # Build final feedback
    feedback = " | ".join(feedback_parts)
    
    if passed:
        feedback = f"PASSED ({score}/100): {feedback}"
    else:
        if not key_criteria_met:
            feedback = f"FAILED - Key criteria not met ({score}/100): {feedback}"
        else:
            feedback = f"FAILED - Score too low ({score}/100): {feedback}"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }