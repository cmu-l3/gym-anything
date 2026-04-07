#!/usr/bin/env python3
"""
Verifier for Street View Heritage Documentation - The Alamo task.

VERIFICATION STRATEGY:
This task requires multi-signal verification because:
1. File existence alone doesn't prove Street View was used
2. The screenshot content must show ground-level Street View (not aerial)
3. The Alamo must be identifiable in the image
4. Trajectory proves the agent actually performed the task

SCORING BREAKDOWN (100 points):
- File exists at correct path: 15 points
- Valid image format and size: 10 points
- File created during task (anti-gaming): 10 points
- VLM: Street View mode visible: 20 points
- VLM: The Alamo visible and identifiable: 25 points
- VLM: Front facade properly shown: 15 points
- VLM: Trajectory shows progression: 5 points

Pass threshold: 65 points with BOTH file exists AND Alamo visible

CRITICAL IMPLEMENTATION NOTES:
- Uses copy_from_env, NOT exec_in_env
- Uses trajectory frames for VLM, not just final screenshot
- Includes timestamp verification to prevent gaming
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ================================================================
# VLM PROMPTS
# ================================================================

STREET_VIEW_DETECTION_PROMPT = """Analyze this screenshot from Google Earth.

TASK: Determine if this shows Street View mode (ground-level panoramic view).

Street View characteristics:
- Ground-level perspective (as if standing on a street)
- 360-degree panoramic view capability
- May show navigation arrows on the ground
- May show a compass or exit button
- Shows buildings/structures from pedestrian viewpoint
- NOT an aerial/satellite view looking down from above

Key question: Is this a ground-level Street View, or an aerial satellite view?

Respond in JSON format:
{
    "is_street_view": true/false,
    "is_aerial_view": true/false,
    "street_view_indicators": ["list any Street View UI elements visible"],
    "perspective": "ground-level" or "aerial" or "unclear",
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""

ALAMO_IDENTIFICATION_PROMPT = """Analyze this screenshot to identify The Alamo in San Antonio, Texas.

TASK: Determine if The Alamo building is visible in this image.

The Alamo's distinctive features:
- Tan/beige limestone facade
- Curved parapet (distinctive scalloped/curved roofline at top)
- Spanish colonial mission architecture style
- Central wooden double doors (main entrance)
- Pilaster columns on the facade
- Historic building, relatively small footprint
- Located on Alamo Plaza with trees and open area in front

This may be a Street View image showing the building from ground level.

Respond in JSON format:
{
    "alamo_visible": true/false,
    "facade_visible": true/false,
    "curved_parapet_visible": true/false,
    "main_entrance_visible": true/false,
    "is_front_view": true/false,
    "building_features_identified": ["list features you can see"],
    "confidence": "low"/"medium"/"high",
    "reasoning": "describe what you see and why you think it is/isn't The Alamo"
}
"""

TRAJECTORY_PROGRESSION_PROMPT = """Analyze this sequence of screenshots showing an agent's progression through a task.

TASK: Navigate to The Alamo and capture a Street View screenshot.

Expected progression:
1. Google Earth globe/default view
2. Search or navigation to San Antonio/Texas area
3. Zoom to The Alamo area
4. Street View mode activation (ground-level view)
5. View adjustment to face The Alamo

Look for evidence of:
- Navigation/search activity
- Zoom progression
- Mode change from aerial to Street View
- View rotation/adjustment

Respond in JSON format:
{
    "shows_progression": true/false,
    "navigation_visible": true/false,
    "street_view_transition_visible": true/false,
    "meaningful_state_changes": true/false,
    "stages_observed": ["list stages you can identify"],
    "confidence": "low"/"medium"/"high"
}
"""


# ================================================================
# HELPER FUNCTIONS
# ================================================================

def safe_vlm_query(query_vlm, prompt: str, image=None, images=None) -> Optional[Dict]:
    """Safely execute VLM query with error handling."""
    if not query_vlm:
        logger.warning("VLM query function not available")
        return None
    
    if not image and not images:
        logger.warning("No image provided for VLM query")
        return None
    
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result.get("success"):
            return result.get("parsed", {})
        else:
            logger.warning(f"VLM query failed: {result.get('error', 'unknown')}")
            return None
    except Exception as e:
        logger.error(f"VLM query exception: {e}")
        return None


def get_trajectory_frames(traj: Dict[str, Any], n: int = 5) -> list:
    """Sample n frames from trajectory for VLM verification."""
    frames = traj.get('frames', [])
    if not frames:
        # Try alternate locations
        frames = traj.get('screenshots', [])
    
    if not frames:
        logger.warning("No trajectory frames found")
        return []
    
    # Sample evenly across trajectory
    if len(frames) <= n:
        return frames
    
    step = len(frames) // n
    sampled = [frames[i * step] for i in range(n)]
    
    # Always include the last frame
    if frames[-1] not in sampled:
        sampled[-1] = frames[-1]
    
    return sampled


def get_final_screenshot(traj: Dict[str, Any]) -> Optional[str]:
    """Get the final screenshot from trajectory."""
    frames = traj.get('frames', [])
    if frames:
        return frames[-1]
    
    screenshots = traj.get('screenshots', [])
    if screenshots:
        return screenshots[-1]
    
    # Check episode directory for final screenshot
    episode_dir = traj.get('episode_dir', '')
    if episode_dir:
        final_path = os.path.join(episode_dir, 'final_screenshot.png')
        if os.path.exists(final_path):
            return final_path
    
    return None


# ================================================================
# MAIN VERIFICATION FUNCTION
# ================================================================

def verify_street_view_heritage_alamo(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify Street View Heritage Documentation task completion.
    
    Multi-criteria verification using:
    1. Programmatic file checks (existence, timestamps, dimensions)
    2. VLM verification of screenshot content
    3. Trajectory analysis to prove work was done
    
    Args:
        traj: Trajectory data with frames, steps, episode_dir
        env_info: Environment info with copy_from_env function
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
            "feedback": "❌ Copy function not available - cannot verify task"
        }
    
    metadata = task_info.get('metadata', {})
    feedback_parts = []
    details = {}
    score = 0
    
    # ================================================================
    # STEP 1: Copy and parse task result from container
    # ================================================================
    
    result_data = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
        details['result_data'] = result_data
    except Exception as e:
        logger.warning(f"Could not read task result: {e}")
        details['result_read_error'] = str(e)
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # CRITERION 1: Output file exists (15 points)
    # ================================================================
    
    output_exists = result_data.get('output_exists', False)
    output_file = result_data.get('output_file', '')
    
    if output_exists and output_file:
        score += 15
        feedback_parts.append("✅ Screenshot file exists")
        details['file_exists'] = True
    else:
        feedback_parts.append("❌ Screenshot file not found at ~/Documents/alamo_streetview.png")
        details['file_exists'] = False
        # If no file, we can still do partial VLM verification on trajectory
    
    # ================================================================
    # CRITERION 2: Valid image format and size (10 points)
    # ================================================================
    
    image_width = result_data.get('image_width', 0)
    image_height = result_data.get('image_height', 0)
    image_format = result_data.get('image_format', 'none')
    output_size = result_data.get('output_size_bytes', 0)
    
    min_width = metadata.get('min_image_width', 640)
    min_height = metadata.get('min_image_height', 480)
    
    if output_exists:
        if image_format in ['PNG', 'JPEG', 'JPG']:
            if image_width >= min_width and image_height >= min_height:
                score += 10
                feedback_parts.append(f"✅ Valid image: {image_width}x{image_height} {image_format}")
                details['valid_image'] = True
            else:
                score += 3
                feedback_parts.append(f"⚠️ Image too small: {image_width}x{image_height}")
                details['valid_image'] = False
        else:
            score += 2
            feedback_parts.append(f"⚠️ Unexpected format: {image_format}")
            details['valid_image'] = False
    
    # ================================================================
    # CRITERION 3: File created during task - Anti-gaming (10 points)
    # ================================================================
    
    file_created_during_task = result_data.get('file_created_during_task', False)
    task_start = result_data.get('task_start_time', 0)
    output_mtime = result_data.get('output_mtime', 0)
    
    if output_exists:
        if file_created_during_task:
            score += 10
            feedback_parts.append("✅ File created during task execution")
            details['created_during_task'] = True
        else:
            feedback_parts.append("⚠️ File may predate task (possible gaming)")
            details['created_during_task'] = False
            details['timestamp_warning'] = f"mtime={output_mtime}, task_start={task_start}"
    
    # ================================================================
    # CRITERION 4: VLM - Street View mode verification (20 points)
    # ================================================================
    
    street_view_score = 0
    
    if query_vlm:
        # First try with the saved output image
        output_image_path = None
        if output_exists and output_file:
            temp_output = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            try:
                copy_from_env(output_file, temp_output.name)
                output_image_path = temp_output.name
            except Exception as e:
                logger.warning(f"Could not copy output image: {e}")
            
        # Also get the final screenshot from trajectory
        final_screenshot = get_final_screenshot(traj)
        
        # Use whichever image we have
        image_for_vlm = output_image_path or final_screenshot
        
        if image_for_vlm:
            sv_result = safe_vlm_query(query_vlm, STREET_VIEW_DETECTION_PROMPT, image=image_for_vlm)
            details['street_view_vlm'] = sv_result
            
            if sv_result:
                is_street_view = sv_result.get('is_street_view', False)
                confidence = sv_result.get('confidence', 'low')
                
                if is_street_view:
                    if confidence == 'high':
                        street_view_score = 20
                    elif confidence == 'medium':
                        street_view_score = 15
                    else:
                        street_view_score = 10
                    feedback_parts.append(f"✅ Street View mode detected ({confidence} confidence)")
                else:
                    # Check if it's aerial view (partial credit if at least in GE)
                    is_aerial = sv_result.get('is_aerial_view', False)
                    if is_aerial:
                        street_view_score = 5
                        feedback_parts.append("⚠️ Aerial view shown (not Street View)")
                    else:
                        feedback_parts.append("❌ Could not confirm Street View mode")
            else:
                feedback_parts.append("⚠️ Street View VLM check inconclusive")
        else:
            feedback_parts.append("⚠️ No image available for Street View check")
        
        # Clean up temp file
        if output_image_path and os.path.exists(output_image_path):
            os.unlink(output_image_path)
    else:
        feedback_parts.append("⚠️ VLM not available for Street View verification")
    
    score += street_view_score
    details['street_view_score'] = street_view_score
    
    # ================================================================
    # CRITERION 5: VLM - The Alamo identification (25 points)
    # ================================================================
    
    alamo_score = 0
    alamo_visible = False
    
    if query_vlm:
        # Get image for Alamo check
        image_for_alamo = None
        if output_exists and output_file:
            temp_alamo = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            try:
                copy_from_env(output_file, temp_alamo.name)
                image_for_alamo = temp_alamo.name
            except:
                pass
        
        if not image_for_alamo:
            image_for_alamo = get_final_screenshot(traj)
        
        if image_for_alamo:
            alamo_result = safe_vlm_query(query_vlm, ALAMO_IDENTIFICATION_PROMPT, image=image_for_alamo)
            details['alamo_vlm'] = alamo_result
            
            if alamo_result:
                alamo_visible = alamo_result.get('alamo_visible', False)
                facade_visible = alamo_result.get('facade_visible', False)
                confidence = alamo_result.get('confidence', 'low')
                
                if alamo_visible:
                    if confidence == 'high':
                        alamo_score = 25
                    elif confidence == 'medium':
                        alamo_score = 20
                    else:
                        alamo_score = 15
                    feedback_parts.append(f"✅ The Alamo identified ({confidence} confidence)")
                elif facade_visible:
                    # Some building visible but not confirmed as Alamo
                    alamo_score = 8
                    feedback_parts.append("⚠️ Building facade visible but Alamo not confirmed")
                else:
                    feedback_parts.append("❌ The Alamo not identified in image")
            else:
                feedback_parts.append("⚠️ Alamo identification VLM check inconclusive")
            
            # Clean up
            if image_for_alamo and os.path.exists(image_for_alamo) and image_for_alamo.startswith('/tmp'):
                try:
                    os.unlink(image_for_alamo)
                except:
                    pass
        else:
            feedback_parts.append("⚠️ No image available for Alamo identification")
    else:
        feedback_parts.append("⚠️ VLM not available for Alamo identification")
    
    score += alamo_score
    details['alamo_score'] = alamo_score
    details['alamo_visible'] = alamo_visible
    
    # ================================================================
    # CRITERION 6: VLM - Facade orientation (15 points)
    # ================================================================
    
    facade_score = 0
    
    if query_vlm and alamo_visible:
        # Use the already-parsed alamo_result
        alamo_result = details.get('alamo_vlm', {})
        if alamo_result:
            is_front_view = alamo_result.get('is_front_view', False)
            main_entrance_visible = alamo_result.get('main_entrance_visible', False)
            curved_parapet_visible = alamo_result.get('curved_parapet_visible', False)
            
            if is_front_view and main_entrance_visible:
                facade_score = 15
                feedback_parts.append("✅ Front facade properly oriented")
            elif is_front_view or main_entrance_visible:
                facade_score = 10
                feedback_parts.append("✅ Facade partially visible")
            elif curved_parapet_visible:
                facade_score = 5
                feedback_parts.append("⚠️ Alamo visible but not front view")
            else:
                feedback_parts.append("⚠️ Facade orientation unclear")
    
    score += facade_score
    details['facade_score'] = facade_score
    
    # ================================================================
    # CRITERION 7: Trajectory progression check (5 points)
    # ================================================================
    
    trajectory_score = 0
    
    if query_vlm:
        traj_frames = get_trajectory_frames(traj, n=4)
        
        if len(traj_frames) >= 2:
            traj_result = safe_vlm_query(query_vlm, TRAJECTORY_PROGRESSION_PROMPT, images=traj_frames)
            details['trajectory_vlm'] = traj_result
            
            if traj_result:
                shows_progression = traj_result.get('shows_progression', False)
                meaningful_changes = traj_result.get('meaningful_state_changes', False)
                
                if shows_progression and meaningful_changes:
                    trajectory_score = 5
                    feedback_parts.append("✅ Trajectory shows task progression")
                elif shows_progression or meaningful_changes:
                    trajectory_score = 3
                    feedback_parts.append("✅ Some task progression visible")
                else:
                    feedback_parts.append("⚠️ Limited progression evidence in trajectory")
            else:
                trajectory_score = 2  # Give benefit of doubt if VLM fails
                feedback_parts.append("⚠️ Trajectory check inconclusive")
        else:
            trajectory_score = 2
            feedback_parts.append("⚠️ Insufficient trajectory frames")
    
    score += trajectory_score
    details['trajectory_score'] = trajectory_score
    
    # ================================================================
    # FINAL SCORING AND PASS DETERMINATION
    # ================================================================
    
    # Key criteria: file must exist AND Alamo must be visible (or high overall score)
    key_criteria_met = (
        (output_exists and alamo_visible) or
        (score >= 75)  # Allow pass on very high score even if one criterion missed
    )
    
    # Pass threshold: 65 points with key criteria
    passed = score >= 65 and key_criteria_met
    
    # Build final feedback
    feedback = " | ".join(feedback_parts)
    feedback += f" | Final score: {score}/100"
    
    if passed:
        feedback = f"✅ PASSED: {feedback}"
    else:
        if not output_exists:
            feedback = f"❌ FAILED (no output file): {feedback}"
        elif not alamo_visible:
            feedback = f"❌ FAILED (Alamo not visible): {feedback}"
        else:
            feedback = f"❌ FAILED (score {score} < 65): {feedback}"
    
    details['key_criteria_met'] = key_criteria_met
    details['pass_threshold'] = 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }