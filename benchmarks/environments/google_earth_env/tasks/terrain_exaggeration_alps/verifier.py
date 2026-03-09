#!/usr/bin/env python3
"""
Verifier for terrain_exaggeration_alps task.

VERIFICATION STRATEGY (Multi-Signal):
1. Configuration Check: Elevation exaggeration set to 2.5 (30 points)
2. File Exists: Screenshot saved to correct path (15 points)
3. File Created During Task: Anti-gaming timestamp check (10 points)
4. VLM - Mountain Terrain: Dramatic peaks visible (15 points)
5. VLM - Tilted 3D View: Not top-down, shows perspective (15 points)
6. VLM - Location Correct: Matterhorn/Swiss Alps region (10 points)
7. VLM - Exaggeration Evidence: Terrain appears dramatically steep (5 points)

Pass Threshold: 60 points with key criteria (config OR file created + VLM passes)

Uses TRAJECTORY frames for VLM verification to prove work was actually done.
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_terrain_exaggeration_alps(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that terrain exaggeration was configured and Matterhorn screenshot captured.
    
    Uses multiple independent signals to prevent gaming:
    - Configuration file analysis
    - File existence and timestamp checks
    - VLM trajectory analysis
    
    Args:
        traj: Trajectory data with frames, steps, episode_dir
        env_info: Environment info with copy_from_env, query_vlm
        task_info: Task info with metadata
        
    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available for verification"
        }
    
    # Get metadata
    metadata = task_info.get('metadata', {})
    target_exaggeration = metadata.get('target_exaggeration', 2.5)
    exaggeration_tolerance = metadata.get('exaggeration_tolerance', 0.2)
    expected_output_path = metadata.get('expected_output_path', '/home/ga/matterhorn_exaggerated.png')
    min_file_size_kb = metadata.get('min_file_size_kb', 100)
    
    feedback_parts = []
    score = 0
    result_details = {}
    
    # ================================================================
    # STEP 1: Copy and parse task result JSON from container
    # ================================================================
    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            task_result = json.load(f)
        result_details['task_result'] = task_result
    except Exception as e:
        logger.error(f"Failed to read task result: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Failed to read task result: {e}",
            "details": result_details
        }
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)
    
    # ================================================================
    # CRITERION 1: Elevation exaggeration config (30 points)
    # ================================================================
    exaggeration_found = task_result.get('exaggeration_found', False)
    exaggeration_value_str = task_result.get('exaggeration_value', 'unknown')
    config_points = 0
    
    try:
        if exaggeration_found and exaggeration_value_str not in ['unknown', '']:
            exaggeration_value = float(exaggeration_value_str)
            if abs(exaggeration_value - target_exaggeration) <= exaggeration_tolerance:
                config_points = 30
                feedback_parts.append(f"✅ Elevation exaggeration correctly set to {exaggeration_value}")
            elif exaggeration_value > 1.0:
                # Partial credit for changing from default
                config_points = 15
                feedback_parts.append(f"⚠️ Exaggeration set to {exaggeration_value}, expected {target_exaggeration}")
            else:
                feedback_parts.append(f"❌ Exaggeration still at default ({exaggeration_value})")
        else:
            feedback_parts.append("⚠️ Could not verify exaggeration config (may still be correct)")
    except (ValueError, TypeError) as e:
        logger.warning(f"Could not parse exaggeration value: {e}")
        feedback_parts.append("⚠️ Could not parse exaggeration value from config")
    
    score += config_points
    result_details['config_points'] = config_points
    
    # ================================================================
    # CRITERION 2: Output file exists (15 points)
    # ================================================================
    output_exists = task_result.get('output_exists', False)
    output_size = task_result.get('output_size_bytes', 0)
    image_width = task_result.get('image_width', 0)
    image_height = task_result.get('image_height', 0)
    file_points = 0
    
    if output_exists:
        if output_size >= min_file_size_kb * 1024:
            file_points = 15
            feedback_parts.append(f"✅ Screenshot saved ({output_size // 1024}KB, {image_width}x{image_height})")
        elif output_size > 10000:
            file_points = 10
            feedback_parts.append(f"⚠️ Screenshot saved but small ({output_size // 1024}KB)")
        else:
            file_points = 5
            feedback_parts.append(f"⚠️ Screenshot file very small ({output_size} bytes)")
    else:
        feedback_parts.append(f"❌ Screenshot NOT found at {expected_output_path}")
    
    score += file_points
    result_details['file_points'] = file_points
    
    # ================================================================
    # CRITERION 3: File created during task (10 points) - ANTI-GAMING
    # ================================================================
    file_created_during_task = task_result.get('file_created_during_task', False)
    timing_points = 0
    
    if file_created_during_task:
        timing_points = 10
        feedback_parts.append("✅ File created during task execution")
    elif output_exists:
        feedback_parts.append("⚠️ File exists but may predate task")
        timing_points = 3
    else:
        feedback_parts.append("❌ No file created during task")
    
    score += timing_points
    result_details['timing_points'] = timing_points
    
    # ================================================================
    # VLM VERIFICATION (45 points total)
    # Use TRAJECTORY frames to prove work was done
    # ================================================================
    vlm_points = 0
    vlm_details = {}
    
    if query_vlm:
        # Try to get trajectory frames for process verification
        trajectory_frames = _get_trajectory_frames(traj, n=5)
        final_screenshot = _get_final_screenshot(traj, env_info, copy_from_env)
        
        if trajectory_frames or final_screenshot:
            # Use trajectory frames for process verification
            if trajectory_frames and len(trajectory_frames) >= 3:
                process_result = _verify_process_via_trajectory(query_vlm, trajectory_frames)
                vlm_details['process_verification'] = process_result
                
                if process_result.get('workflow_completed', False):
                    vlm_points += 10
                    feedback_parts.append("✅ VLM: Workflow progression verified")
                elif process_result.get('meaningful_actions', False):
                    vlm_points += 5
                    feedback_parts.append("⚠️ VLM: Some workflow actions detected")
            
            # Use final screenshot (or last trajectory frame) for content verification
            image_for_content = final_screenshot or (trajectory_frames[-1] if trajectory_frames else None)
            
            if image_for_content:
                content_result = _verify_content_via_vlm(query_vlm, image_for_content)
                vlm_details['content_verification'] = content_result
                
                # Mountain terrain visible (15 points)
                if content_result.get('mountain_terrain_visible', False):
                    vlm_points += 15
                    feedback_parts.append("✅ VLM: Mountain terrain visible")
                elif content_result.get('geographic_terrain', False):
                    vlm_points += 8
                    feedback_parts.append("⚠️ VLM: Geographic terrain visible (not clearly mountains)")
                else:
                    feedback_parts.append("❌ VLM: No mountain terrain detected")
                
                # Tilted 3D view (15 points)
                if content_result.get('tilted_3d_view', False):
                    vlm_points += 15
                    feedback_parts.append("✅ VLM: Tilted 3D perspective confirmed")
                elif content_result.get('some_perspective', False):
                    vlm_points += 7
                    feedback_parts.append("⚠️ VLM: Some perspective visible")
                else:
                    feedback_parts.append("❌ VLM: No 3D tilt detected")
                
                # Location correct - Matterhorn/Alps (10 points)
                if content_result.get('matterhorn_or_alps', False):
                    vlm_points += 10
                    feedback_parts.append("✅ VLM: Matterhorn/Alps region identified")
                elif content_result.get('alpine_terrain', False):
                    vlm_points += 5
                    feedback_parts.append("⚠️ VLM: Alpine-like terrain")
                else:
                    feedback_parts.append("⚠️ VLM: Location not confirmed as Matterhorn")
                
                # Exaggeration visible (5 points - bonus)
                if content_result.get('exaggeration_evident', False):
                    vlm_points += 5
                    feedback_parts.append("✅ VLM: Terrain exaggeration evident")
        else:
            feedback_parts.append("⚠️ No screenshots available for VLM verification")
    else:
        feedback_parts.append("⚠️ VLM not available for visual verification")
    
    score += vlm_points
    result_details['vlm_points'] = vlm_points
    result_details['vlm_details'] = vlm_details
    
    # ================================================================
    # DETERMINE PASS/FAIL
    # ================================================================
    # Key criteria: Either config is correct OR (file created + reasonable VLM score)
    config_correct = config_points >= 25
    file_created = file_points >= 10 and timing_points >= 5
    vlm_passes = vlm_points >= 25
    
    # Pass if score >= 60 AND at least one strong signal
    key_criteria_met = config_correct or (file_created and vlm_passes)
    passed = score >= 60 and key_criteria_met
    
    result_details['config_correct'] = config_correct
    result_details['file_created'] = file_created
    result_details['vlm_passes'] = vlm_passes
    result_details['key_criteria_met'] = key_criteria_met
    
    # Build final feedback
    feedback = " | ".join(feedback_parts)
    feedback += f" | Total: {score}/100"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": result_details
    }


def _get_trajectory_frames(traj: Dict[str, Any], n: int = 5) -> list:
    """
    Extract trajectory frames from the trajectory data.
    
    The framework captures screenshots at each step. We sample n frames
    across the trajectory to verify the workflow.
    """
    try:
        # Try to get frames from trajectory
        frames = traj.get('frames', [])
        if not frames:
            # Try alternate keys
            frames = traj.get('screenshots', [])
        if not frames:
            frames = traj.get('observations', [])
        
        if not frames or len(frames) == 0:
            return []
        
        # Sample n frames evenly across the trajectory
        total = len(frames)
        if total <= n:
            return frames
        
        indices = [int(i * (total - 1) / (n - 1)) for i in range(n)]
        sampled = [frames[i] for i in indices]
        return sampled
        
    except Exception as e:
        logger.warning(f"Could not extract trajectory frames: {e}")
        return []


def _get_final_screenshot(traj: Dict[str, Any], env_info: Dict[str, Any], copy_from_env) -> Optional[str]:
    """
    Get the final screenshot, either from trajectory or by copying from container.
    Returns path to local copy of screenshot.
    """
    try:
        # First try trajectory
        frames = traj.get('frames', []) or traj.get('screenshots', [])
        if frames:
            return frames[-1] if isinstance(frames[-1], str) else None
        
        # Try copying final screenshot from container
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            # Try the output file first
            copy_from_env("/home/ga/matterhorn_exaggerated.png", temp_file.name)
            if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 1000:
                return temp_file.name
        except:
            pass
        
        try:
            # Try the task final screenshot
            copy_from_env("/tmp/task_final_state.png", temp_file.name)
            if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 1000:
                return temp_file.name
        except:
            pass
        
        # Clean up if nothing worked
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
        
    except Exception as e:
        logger.warning(f"Could not get final screenshot: {e}")
    
    return None


def _verify_process_via_trajectory(query_vlm, frames: list) -> Dict[str, Any]:
    """
    Use VLM to verify the agent's workflow progression through trajectory frames.
    """
    process_prompt = """You are analyzing a sequence of screenshots from an agent configuring terrain settings in Google Earth Pro.

The images are in chronological order (earliest to latest).

For this task, the agent should:
1. Open Google Earth's Options/Settings dialog (Tools > Options)
2. Navigate to the 3D View tab
3. Adjust the Elevation Exaggeration setting
4. Navigate to a mountain location (Matterhorn, Switzerland)
5. Tilt the view to show 3D perspective
6. Save a screenshot

Analyze these frames and determine:

1. WORKFLOW_COMPLETED: Do the frames show progression through the workflow (settings dialog → navigation → 3D view)?
2. SETTINGS_DIALOG_VISIBLE: At any point, is a settings/options dialog visible?
3. MEANINGFUL_ACTIONS: Do the frames show different states (not just the same screen)?
4. GOOGLE_EARTH_VISIBLE: Is Google Earth clearly visible in the frames?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "settings_dialog_visible": true/false,
    "meaningful_actions": true/false,
    "google_earth_visible": true/false,
    "stages_observed": ["list any stages you can identify"],
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see across frames"
}
"""
    
    try:
        result = query_vlm(prompt=process_prompt, images=frames)
        if result.get('success'):
            return result.get('parsed', {})
    except Exception as e:
        logger.warning(f"VLM process verification failed: {e}")
    
    return {}


def _verify_content_via_vlm(query_vlm, image) -> Dict[str, Any]:
    """
    Use VLM to verify the content of the screenshot shows correct task completion.
    """
    content_prompt = """You are verifying a Google Earth screenshot for a terrain visualization task.

TASK: The user should have:
1. Set terrain elevation exaggeration to 2.5x (makes mountains appear 2.5x taller)
2. Navigated to the Matterhorn in Switzerland
3. Tilted the view to show 3D perspective (not flat top-down)
4. The terrain should appear dramatically exaggerated (steeper than natural)

Analyze this screenshot and determine:

1. MOUNTAIN_TERRAIN_VISIBLE: Are dramatic mountain peaks clearly visible? Look for:
   - Snow-capped peaks
   - Steep mountain slopes
   - Alpine terrain with dramatic elevation changes

2. TILTED_3D_VIEW: Is the view tilted to show 3D perspective? Signs include:
   - Visible horizon or sky
   - Mountains seen from an angle (not directly from above)
   - Depth/perspective in the terrain

3. MATTERHORN_OR_ALPS: Does this appear to be the Matterhorn or Swiss Alps? Look for:
   - Distinctive pyramid-shaped peak (Matterhorn is iconic)
   - Alpine terrain with glaciers
   - High-altitude terrain with snow

4. EXAGGERATION_EVIDENT: Does the terrain appear vertically exaggerated? Signs include:
   - Mountains appearing steeper than natural
   - Dramatic vertical relief
   - "Spiky" or dramatically tall peaks

5. GEOGRAPHIC_TERRAIN: Is any geographic/satellite terrain visible?

6. SOME_PERSPECTIVE: Is there any perspective/tilt (even if not fully 3D)?

7. ALPINE_TERRAIN: Does it look like alpine/mountainous terrain even if not clearly Matterhorn?

Respond in JSON format:
{
    "mountain_terrain_visible": true/false,
    "tilted_3d_view": true/false,
    "matterhorn_or_alps": true/false,
    "exaggeration_evident": true/false,
    "geographic_terrain": true/false,
    "some_perspective": true/false,
    "alpine_terrain": true/false,
    "is_google_earth": true/false,
    "confidence": "low"/"medium"/"high",
    "description": "brief description of what you see"
}
"""
    
    try:
        result = query_vlm(prompt=content_prompt, image=image)
        if result.get('success'):
            return result.get('parsed', {})
    except Exception as e:
        logger.warning(f"VLM content verification failed: {e}")
    
    return {}