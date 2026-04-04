#!/usr/bin/env python3
"""
Verifier for configure_camera_views task.

VERIFICATION STRATEGY (Hybrid: Programmatic + VLM on Trajectory):

Programmatic checks (50 points):
  1. Volume rendering active (15 pts) - VR module was used
  2. Anterior screenshot exists (10 pts) - file created during task
  3. Lateral screenshot exists (10 pts) - file created during task
  4. Superior screenshot exists (10 pts) - file created during task
  5. All views distinct (5 pts) - screenshots are different files

VLM checks using TRAJECTORY frames (50 points):
  6. Anterior view correct (15 pts) - shows frontal face-forward perspective
  7. Lateral view correct (15 pts) - shows profile/side perspective
  8. Superior view correct (15 pts) - shows top-down perspective
  9. Cross-validation (5 pts) - screenshots show 3D rendered brain content

Pass threshold: 70 points with at least 2 screenshots correctly oriented
"""

import json
import os
import tempfile
import logging
import hashlib

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ================================================================
# VLM PROMPTS
# ================================================================

ANTERIOR_VIEW_PROMPT = """You are analyzing a 3D medical image screenshot to verify the camera orientation.

This should be an ANTERIOR VIEW of a brain - looking at the front of the head (face-forward perspective).

Assess the image:
1. Is this a 3D volume rendering of a brain (not 2D slices)?
2. Is this an anterior/frontal view? Signs of anterior view:
   - Face features visible (eye sockets, nose area)
   - Symmetric left-right appearance
   - Looking at the front of the head
   - Top of head pointing upward

Respond in JSON format:
{
    "is_3d_rendering": true/false,
    "is_anterior_view": true/false,
    "shows_brain_content": true/false,
    "symmetry_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}
"""

LATERAL_VIEW_PROMPT = """You are analyzing a 3D medical image screenshot to verify the camera orientation.

This should be a RIGHT LATERAL VIEW of a brain - looking at the side profile of the head.

Assess the image:
1. Is this a 3D volume rendering of a brain (not 2D slices)?
2. Is this a lateral/side view? Signs of lateral view:
   - Profile visible (asymmetric view)
   - Nose pointing to one side of the image
   - One ear region visible
   - Not a symmetric front-on view
   - Top of head pointing upward

Respond in JSON format:
{
    "is_3d_rendering": true/false,
    "is_lateral_view": true/false,
    "shows_brain_content": true/false,
    "profile_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}
"""

SUPERIOR_VIEW_PROMPT = """You are analyzing a 3D medical image screenshot to verify the camera orientation.

This should be a SUPERIOR VIEW of a brain - looking down at the top of the head from above.

Assess the image:
1. Is this a 3D volume rendering of a brain (not 2D slices)?
2. Is this a superior/top-down view? Signs of superior view:
   - Looking down at crown of head
   - Roughly circular/oval outline
   - No face features visible (no eyes, nose)
   - Front-back asymmetry may be visible (frontal vs occipital lobes)
   - Not a profile or frontal view

Respond in JSON format:
{
    "is_3d_rendering": true/false,
    "is_superior_view": true/false,
    "shows_brain_content": true/false,
    "top_down_perspective": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}
"""

TRAJECTORY_WORKFLOW_PROMPT = """You are analyzing screenshots from an agent performing 3D visualization tasks in 3D Slicer.

The images are sampled chronologically from the agent's interaction.

For this task, the agent should:
1. Load brain MRI data
2. Enable 3D volume rendering (switch to Volume Rendering module)
3. Rotate the 3D view to different angles
4. Capture screenshots

Assess the progression:
1. Is 3D Slicer visible?
2. Was volume rendering enabled (can see 3D brain visualization)?
3. Did the agent rotate the 3D view (different angles visible across frames)?
4. Is there evidence of screenshot capture activity?

Respond in JSON format:
{
    "slicer_visible": true/false,
    "volume_rendering_shown": true/false,
    "view_rotation_observed": true/false,
    "workflow_progression": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe the workflow you observe"
}
"""


def _vlm_query(query_vlm, prompt, image=None, images=None):
    """Run VLM query with single or multiple images. Returns parsed dict or None."""
    if not query_vlm:
        return None
    if not image and not images:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result.get("success"):
            return result.get("parsed", {})
        logger.warning(f"VLM query failed: {result.get('error', 'unknown')}")
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None


def get_file_hash(filepath):
    """Get MD5 hash of file to check for duplicates."""
    try:
        with open(filepath, 'rb') as f:
            return hashlib.md5(f.read()).hexdigest()
    except:
        return None


def verify_configure_camera_views(traj, env_info, task_info):
    """
    Verify that camera views were configured and screenshots captured.
    
    Uses multi-criteria scoring with VLM verification of view orientations.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - framework error"
        }

    # Get task metadata
    metadata = task_info.get('metadata', {})
    min_size_kb = metadata.get('min_screenshot_size_kb', 50)
    weights = metadata.get('scoring_weights', {})
    
    w_vr = weights.get('volume_rendering_active', 15)
    w_ant_exists = weights.get('anterior_exists', 10)
    w_ant_correct = weights.get('anterior_correct', 15)
    w_lat_exists = weights.get('lateral_exists', 10)
    w_lat_correct = weights.get('lateral_correct', 15)
    w_sup_exists = weights.get('superior_exists', 10)
    w_sup_correct = weights.get('superior_correct', 15)
    w_orthogonal = weights.get('views_orthogonal', 10)

    score = 0
    feedback_parts = []
    details = {}

    # ================================================================
    # Copy result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/camera_views_result.json", temp_result.name)
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

    # Check if Slicer was running
    if not result.get('slicer_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "3D Slicer was not running - cannot complete task"
        }

    # ================================================================
    # CRITERION 1: Volume Rendering Active (15 points)
    # ================================================================
    vr_enabled = result.get('volume_rendering_enabled', False)
    vr_nodes = result.get('vr_display_nodes', 0)
    volumes_loaded = result.get('volumes_loaded', 0)
    
    if vr_enabled:
        score += w_vr
        feedback_parts.append("Volume rendering enabled")
    elif vr_nodes > 0:
        score += w_vr * 0.7
        feedback_parts.append("VR nodes exist (may not be visible)")
    elif volumes_loaded > 0:
        score += w_vr * 0.3
        feedback_parts.append("Volume loaded but VR not confirmed")
    else:
        feedback_parts.append("Volume rendering not detected")
    
    details['vr_enabled'] = vr_enabled
    details['volumes_loaded'] = volumes_loaded

    # ================================================================
    # CRITERION 2-4: Screenshot Existence (10 points each)
    # ================================================================
    screenshot_files = {}
    screenshot_hashes = {}
    
    for view_name in ['anterior', 'lateral', 'superior']:
        view_info = result.get(view_name, {})
        exists = view_info.get('exists', False)
        created = view_info.get('created_during_task', False)
        size_kb = view_info.get('size_kb', 0)
        
        details[f'{view_name}_exists'] = exists
        details[f'{view_name}_created'] = created
        details[f'{view_name}_size_kb'] = size_kb
        
        weight = w_ant_exists if view_name == 'anterior' else (w_lat_exists if view_name == 'lateral' else w_sup_exists)
        
        if exists and created and size_kb >= min_size_kb:
            score += weight
            feedback_parts.append(f"{view_name.capitalize()} screenshot OK ({size_kb}KB)")
            
            # Copy screenshot for VLM analysis
            temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            try:
                copy_from_env(f"/tmp/{view_name}_view.png", temp_img.name)
                screenshot_files[view_name] = temp_img.name
                screenshot_hashes[view_name] = get_file_hash(temp_img.name)
            except:
                try:
                    # Try alternative path
                    copy_from_env(f"/home/ga/Documents/SlicerData/Screenshots/{view_name}_view.png", temp_img.name)
                    screenshot_files[view_name] = temp_img.name
                    screenshot_hashes[view_name] = get_file_hash(temp_img.name)
                except:
                    pass
                    
        elif exists and created:
            score += weight * 0.5
            feedback_parts.append(f"{view_name.capitalize()} screenshot small ({size_kb}KB)")
        elif exists:
            score += weight * 0.3
            feedback_parts.append(f"{view_name.capitalize()} existed before task")
        else:
            feedback_parts.append(f"{view_name.capitalize()} screenshot missing")

    # ================================================================
    # CRITERION 5: All Views Distinct (5 points from orthogonal)
    # ================================================================
    unique_hashes = set(h for h in screenshot_hashes.values() if h)
    views_are_distinct = len(unique_hashes) >= len(screenshot_hashes) and len(screenshot_hashes) >= 2
    
    if views_are_distinct and len(screenshot_hashes) == 3:
        score += 5
        feedback_parts.append("All views distinct")
        details['views_distinct'] = True
    elif len(unique_hashes) >= 2:
        score += 3
        feedback_parts.append("Some views distinct")
        details['views_distinct'] = True
    else:
        feedback_parts.append("Views may be duplicates")
        details['views_distinct'] = False

    # ================================================================
    # VLM VERIFICATION: View Orientations (15 points each)
    # ================================================================
    vlm_scores = {'anterior': 0, 'lateral': 0, 'superior': 0}
    
    if query_vlm:
        # Verify anterior view
        if 'anterior' in screenshot_files:
            ant_result = _vlm_query(query_vlm, ANTERIOR_VIEW_PROMPT, image=screenshot_files['anterior'])
            if ant_result:
                details['vlm_anterior'] = ant_result
                is_3d = ant_result.get('is_3d_rendering', False)
                is_anterior = ant_result.get('is_anterior_view', False)
                confidence = ant_result.get('confidence', 'low')
                
                if is_3d and is_anterior:
                    vlm_scores['anterior'] = w_ant_correct if confidence == 'high' else w_ant_correct * 0.8
                    feedback_parts.append(f"Anterior view verified ({confidence})")
                elif is_3d:
                    vlm_scores['anterior'] = w_ant_correct * 0.3
                    feedback_parts.append("Anterior: 3D but wrong angle")
                else:
                    feedback_parts.append("Anterior: not 3D rendering")

        # Verify lateral view
        if 'lateral' in screenshot_files:
            lat_result = _vlm_query(query_vlm, LATERAL_VIEW_PROMPT, image=screenshot_files['lateral'])
            if lat_result:
                details['vlm_lateral'] = lat_result
                is_3d = lat_result.get('is_3d_rendering', False)
                is_lateral = lat_result.get('is_lateral_view', False)
                confidence = lat_result.get('confidence', 'low')
                
                if is_3d and is_lateral:
                    vlm_scores['lateral'] = w_lat_correct if confidence == 'high' else w_lat_correct * 0.8
                    feedback_parts.append(f"Lateral view verified ({confidence})")
                elif is_3d:
                    vlm_scores['lateral'] = w_lat_correct * 0.3
                    feedback_parts.append("Lateral: 3D but wrong angle")
                else:
                    feedback_parts.append("Lateral: not 3D rendering")

        # Verify superior view
        if 'superior' in screenshot_files:
            sup_result = _vlm_query(query_vlm, SUPERIOR_VIEW_PROMPT, image=screenshot_files['superior'])
            if sup_result:
                details['vlm_superior'] = sup_result
                is_3d = sup_result.get('is_3d_rendering', False)
                is_superior = sup_result.get('is_superior_view', False)
                confidence = sup_result.get('confidence', 'low')
                
                if is_3d and is_superior:
                    vlm_scores['superior'] = w_sup_correct if confidence == 'high' else w_sup_correct * 0.8
                    feedback_parts.append(f"Superior view verified ({confidence})")
                elif is_3d:
                    vlm_scores['superior'] = w_sup_correct * 0.3
                    feedback_parts.append("Superior: 3D but wrong angle")
                else:
                    feedback_parts.append("Superior: not 3D rendering")

        # Trajectory verification for workflow
        try:
            # Import trajectory helpers
            from gym_anything.vlm import sample_trajectory_frames
            traj_frames = sample_trajectory_frames(traj, n=5)
            if traj_frames:
                workflow_result = _vlm_query(query_vlm, TRAJECTORY_WORKFLOW_PROMPT, images=traj_frames)
                if workflow_result:
                    details['vlm_workflow'] = workflow_result
                    if workflow_result.get('volume_rendering_shown', False):
                        score += 5  # Bonus for confirmed workflow
                        feedback_parts.append("Workflow verified via trajectory")
        except ImportError:
            logger.info("Trajectory frame sampling not available")
        except Exception as e:
            logger.warning(f"Trajectory verification failed: {e}")

    else:
        # No VLM available - give partial credit based on file existence
        logger.warning("VLM not available - using fallback verification")
        for view_name in ['anterior', 'lateral', 'superior']:
            if view_name in screenshot_files:
                weight = w_ant_correct if view_name == 'anterior' else (w_lat_correct if view_name == 'lateral' else w_sup_correct)
                vlm_scores[view_name] = weight * 0.5
        feedback_parts.append("VLM unavailable - partial credit")

    # Add VLM scores
    score += sum(vlm_scores.values())
    details['vlm_scores'] = vlm_scores

    # Cleanup temp files
    for filepath in screenshot_files.values():
        try:
            if os.path.exists(filepath):
                os.unlink(filepath)
        except:
            pass

    # ================================================================
    # FINAL SCORING
    # ================================================================
    
    # Count correctly oriented views
    correct_views = sum(1 for v in vlm_scores.values() if v >= 10)
    details['correct_views_count'] = correct_views
    
    # Determine pass/fail
    # Pass requires: 70+ points AND at least 2 correctly oriented views
    screenshots_created = result.get('screenshots_created_count', 0)
    key_criteria_met = screenshots_created >= 2 and correct_views >= 2
    
    passed = score >= 70 and key_criteria_met
    
    # Cap score at 100
    score = min(100, int(score))
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }