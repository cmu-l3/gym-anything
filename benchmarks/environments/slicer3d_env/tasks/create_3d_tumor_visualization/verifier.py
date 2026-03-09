#!/usr/bin/env python3
"""
Verifier for Create 3D Tumor Visualization task.

VERIFICATION STRATEGY (Multi-Signal):

Programmatic checks (from export script JSON):
1. Segmentation node present (15 pts) - TumorSegmentation exists in scene
2. 3D visibility enabled (25 pts) - Segmentation display has visibility3D ON
3. 3D view has content (20 pts) - Renderer contains visible actors
4. Screenshot file exists (15 pts) - PNG file at expected path
5. Screenshot created during task (10 pts) - Timestamp check (anti-gaming)
6. Screenshot has content (15 pts) - File size and VLM analysis

VLM verification:
- Uses TRAJECTORY frames to verify workflow progression
- Analyzes final screenshot/state for 3D rendered content

Pass threshold: 70 points with "3D visibility enabled" criterion met
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_3d_tumor_visualization(traj, env_info, task_info):
    """
    Verify that 3D tumor visualization was enabled and screenshot captured.

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
    expected_screenshot = metadata.get('expected_screenshot_path', 
        '/home/ga/Documents/SlicerData/Screenshots/tumor_3d_visualization.png')
    min_size_kb = metadata.get('min_screenshot_size_kb', 50)
    
    weights = metadata.get('scoring_weights', {})
    w_seg_present = weights.get('segmentation_node_present', 15)
    w_vis_3d = weights.get('visibility_3d_enabled', 25)
    w_3d_content = weights.get('threed_view_has_content', 20)
    w_file_exists = weights.get('screenshot_file_exists', 15)
    w_screenshot_content = weights.get('screenshot_has_content', 15)
    w_timestamp = weights.get('screenshot_created_during_task', 10)

    # Initialize results
    score = 0
    feedback_parts = []
    details = {}

    # ================================================================
    # Copy result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/tumor_3d_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Export result not found - task may not have completed properly"
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

    details['raw_result'] = result

    # Check if Slicer was running
    if not result.get('slicer_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "3D Slicer was not running - task cannot be verified"
        }

    # ================================================================
    # CRITERION 1: Segmentation node present (15 pts)
    # ================================================================
    seg_exists = result.get('segmentation_exists', False)
    
    if seg_exists:
        score += w_seg_present
        feedback_parts.append("Segmentation node present")
        details['segmentation_present'] = True
    else:
        feedback_parts.append("Segmentation NOT found")
        details['segmentation_present'] = False

    # ================================================================
    # CRITERION 2: 3D visibility enabled (25 pts) - KEY CRITERION
    # ================================================================
    vis_3d = result.get('visibility_3d_enabled', False)
    
    if vis_3d:
        score += w_vis_3d
        feedback_parts.append("3D visibility ENABLED")
        details['visibility_3d'] = True
    else:
        feedback_parts.append("3D visibility NOT enabled")
        details['visibility_3d'] = False

    # ================================================================
    # CRITERION 3: 3D view has content (20 pts)
    # ================================================================
    has_actors = result.get('threed_view_has_actors', False)
    num_actors = result.get('num_actors_in_3d', 0)
    
    if has_actors and num_actors > 0:
        score += w_3d_content
        feedback_parts.append(f"3D view has {num_actors} actor(s)")
        details['threed_has_content'] = True
    elif vis_3d:
        # If 3D was enabled, give partial credit even if actors not detected
        score += w_3d_content // 2
        feedback_parts.append("3D enabled but actors not verified")
        details['threed_has_content'] = "partial"
    else:
        feedback_parts.append("3D view empty")
        details['threed_has_content'] = False

    # ================================================================
    # CRITERION 4: Screenshot file exists (15 pts)
    # ================================================================
    screenshot_exists = result.get('screenshot_exists', False)
    screenshot_size = result.get('screenshot_size_bytes', 0)
    screenshot_size_kb = screenshot_size / 1024 if screenshot_size else 0
    
    if screenshot_exists:
        if screenshot_size_kb >= min_size_kb:
            score += w_file_exists
            feedback_parts.append(f"Screenshot saved ({screenshot_size_kb:.1f}KB)")
        else:
            score += w_file_exists // 2
            feedback_parts.append(f"Screenshot small ({screenshot_size_kb:.1f}KB)")
        details['screenshot_exists'] = True
        details['screenshot_size_kb'] = screenshot_size_kb
    else:
        feedback_parts.append("Screenshot NOT saved")
        details['screenshot_exists'] = False

    # ================================================================
    # CRITERION 5: Screenshot created during task (10 pts) - ANTI-GAMING
    # ================================================================
    created_during_task = result.get('screenshot_created_during_task', False)
    
    if created_during_task:
        score += w_timestamp
        feedback_parts.append("Screenshot created during task")
        details['created_during_task'] = True
    elif screenshot_exists:
        feedback_parts.append("Screenshot may pre-exist")
        details['created_during_task'] = False
    else:
        details['created_during_task'] = False

    # ================================================================
    # CRITERION 6: Screenshot has 3D content (15 pts) - VLM + heuristics
    # ================================================================
    has_3d_content = result.get('screenshot_has_3d_content', False)
    color_count = result.get('screenshot_color_count', 0)
    
    # Use VLM to verify screenshot content if available
    vlm_verified = False
    vlm_feedback = ""
    
    try:
        # Import VLM utilities
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        # Get trajectory frames for process verification
        trajectory_frames = sample_trajectory_frames(traj, n=5) if traj else []
        final_screenshot = get_final_screenshot(traj) if traj else None
        
        # Also try to get the user's saved screenshot
        user_screenshot = None
        temp_user_ss = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env("/tmp/user_screenshot.png", temp_user_ss.name)
            if os.path.exists(temp_user_ss.name) and os.path.getsize(temp_user_ss.name) > 1000:
                user_screenshot = temp_user_ss.name
        except Exception:
            pass
        
        # VLM verification on trajectory to confirm workflow
        if trajectory_frames:
            process_prompt = """Analyze these sequential screenshots from a medical imaging task in 3D Slicer.

The task was to enable 3D visualization of a brain tumor segmentation.

Look for evidence of:
1. Brain MRI data loaded (grayscale brain image in slice views)
2. Tumor segmentation visible (colored overlay on slices)
3. Segment Editor or Segmentations module accessed
4. 3D view showing a rendered 3D object (tumor model)
5. Final state shows 3D visualization of tumor

Respond in JSON:
{
    "mri_data_visible": true/false,
    "segmentation_visible": true/false,
    "threed_model_visible": true/false,
    "workflow_progression": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description"
}"""
            
            vlm_result = query_vlm(prompt=process_prompt, images=trajectory_frames)
            
            if vlm_result and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                if parsed.get('threed_model_visible') or parsed.get('workflow_progression'):
                    vlm_verified = True
                    vlm_feedback = parsed.get('observations', 'VLM verified 3D content')
                    details['vlm_verification'] = parsed
        
        # VLM verification on final screenshot specifically
        if final_screenshot and not vlm_verified:
            content_prompt = """Examine this screenshot from 3D Slicer.

Is there a 3D rendered anatomical structure (tumor/brain model) visible in the 3D view panel?

The 3D view is typically in the upper right or as a separate panel showing a rendered 3D object with shading and depth.

Respond in JSON:
{
    "threed_object_visible": true/false,
    "appears_to_be_tumor": true/false,
    "confidence": "low"/"medium"/"high"
}"""
            
            vlm_result = query_vlm(prompt=content_prompt, image=final_screenshot)
            
            if vlm_result and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                if parsed.get('threed_object_visible'):
                    vlm_verified = True
                    vlm_feedback = "VLM confirmed 3D object in view"
                    details['vlm_final_check'] = parsed
        
        # Clean up temp file
        if user_screenshot and os.path.exists(temp_user_ss.name):
            os.unlink(temp_user_ss.name)
            
    except ImportError:
        logger.info("VLM utilities not available, using heuristic checks only")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")

    # Score based on content verification
    if vlm_verified:
        score += w_screenshot_content
        feedback_parts.append(f"3D content verified ({vlm_feedback})")
        details['content_verified'] = True
        details['vlm_feedback'] = vlm_feedback
    elif has_3d_content:
        score += w_screenshot_content * 3 // 4
        feedback_parts.append("3D content likely (heuristic)")
        details['content_verified'] = "heuristic"
    elif screenshot_exists and color_count > 200:
        score += w_screenshot_content // 2
        feedback_parts.append(f"Some image content ({color_count} colors)")
        details['content_verified'] = "partial"
    else:
        feedback_parts.append("3D content not verified")
        details['content_verified'] = False

    # ================================================================
    # FINAL SCORING
    # ================================================================
    max_score = w_seg_present + w_vis_3d + w_3d_content + w_file_exists + w_screenshot_content + w_timestamp
    
    # Key criteria for passing
    key_criteria_met = vis_3d  # 3D visibility must be enabled
    
    # Pass threshold: 70% AND key criterion
    passed = score >= 70 and key_criteria_met
    
    # Compile feedback
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }