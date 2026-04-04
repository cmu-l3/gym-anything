#!/usr/bin/env python3
"""
Verifier for view_history_navigation task.

TASK: Navigate to three locations in sequence, use view history (Previous button)
to return to the first location (Niagara Falls), and save a screenshot.

VERIFICATION STRATEGY (Multi-Signal):
1. Output file exists and is valid PNG (15 points)
2. File was created during task - anti-gaming (15 points)
3. Image is valid with reasonable dimensions (10 points)
4. VLM: Final screenshot/output shows Niagara Falls (35 points)
5. VLM: Trajectory shows multi-location navigation + history use (25 points)

Pass threshold: 60 points AND key criteria (file created + Niagara Falls visible)

CRITICAL: Uses copy_from_env (NOT exec_in_env) and trajectory frames for VLM.
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

NIAGARA_FALLS_VERIFICATION_PROMPT = """You are verifying a Google Earth screenshot for a navigation task.

The user was asked to navigate to Niagara Falls, Ontario and save a screenshot.

Analyze this image and determine:

1. IS_GOOGLE_EARTH: Is this Google Earth satellite/aerial imagery? (NOT a photo, NOT Google Maps)
   Look for: satellite view perspective, Google Earth UI elements, terrain rendering

2. SHOWS_NIAGARA_FALLS: Does this show Niagara Falls area? Look for:
   - The distinctive horseshoe-shaped waterfall (Horseshoe Falls)
   - The Niagara River and gorge
   - Urban areas on both sides (Niagara Falls, NY and Niagara Falls, Ontario)
   - The smaller American Falls nearby
   - Green parks (Queen Victoria Park, Niagara Falls State Park)

3. VIEW_QUALITY: Is the view appropriately zoomed to show the landmark?
   - Can you clearly identify the waterfall area?
   - Is the falls region reasonably centered?

Respond in JSON format:
{
    "is_google_earth": true/false,
    "shows_niagara_falls": true/false,
    "horseshoe_falls_visible": true/false,
    "niagara_river_visible": true/false,
    "urban_areas_visible": true/false,
    "view_quality": "good"/"acceptable"/"poor",
    "confidence": "high"/"medium"/"low",
    "reasoning": "brief explanation of what you see"
}
"""

TRAJECTORY_VERIFICATION_PROMPT = """You are analyzing a sequence of Google Earth screenshots from an agent performing a navigation task.

EXPECTED WORKFLOW:
1. Navigate to Niagara Falls, Ontario (first location)
2. Navigate to Grand Canyon National Park, Arizona (second location)  
3. Navigate to Golden Gate Bridge, San Francisco (third location)
4. Use Previous/Back button to return to Niagara Falls
5. Save screenshot of Niagara Falls

The images are sampled chronologically from earliest to latest.

Analyze this sequence and determine:

1. MULTI_LOCATION_VISITED: Did the agent visit multiple distinct geographic locations?
   Look for significant changes in terrain, urban patterns, or landmarks between frames.
   - Niagara Falls: Waterfall, gorge, border region
   - Grand Canyon: Red/brown canyon terrain, desert
   - Golden Gate: Red bridge, San Francisco Bay, urban area

2. THREE_LOCATIONS_CONFIRMED: Can you identify at least 3 different major locations?

3. WORKFLOW_PROGRESSION: Do the frames show meaningful navigation progression?
   (Not just the same view repeated)

4. RETURN_TO_FIRST: Does the final frame appear to show the same location as an earlier frame?
   (This would indicate use of history navigation)

Respond in JSON format:
{
    "multi_location_visited": true/false,
    "locations_identified": ["list of locations you can identify"],
    "num_distinct_locations": <number>,
    "workflow_progression": true/false,
    "appears_to_return": true/false,
    "confidence": "high"/"medium"/"low",
    "observations": "describe what you see across the sequence"
}
"""


# ================================================================
# HELPER FUNCTIONS
# ================================================================

def get_trajectory_frames(traj: Dict[str, Any], n: int = 5) -> list:
    """
    Sample n frames from trajectory for VLM analysis.
    Returns list of frame paths or base64 images.
    """
    frames = []
    
    # Try to get frames from trajectory data
    if 'frames' in traj and traj['frames']:
        all_frames = traj['frames']
        if len(all_frames) <= n:
            frames = all_frames
        else:
            # Sample evenly across trajectory
            indices = [int(i * (len(all_frames) - 1) / (n - 1)) for i in range(n)]
            frames = [all_frames[i] for i in indices]
    
    # Alternative: check episode_dir for screenshots
    elif 'episode_dir' in traj:
        episode_dir = traj['episode_dir']
        if os.path.isdir(episode_dir):
            screenshot_files = sorted([
                os.path.join(episode_dir, f) 
                for f in os.listdir(episode_dir) 
                if f.endswith('.png') and 'screenshot' in f.lower()
            ])
            if screenshot_files:
                if len(screenshot_files) <= n:
                    frames = screenshot_files
                else:
                    indices = [int(i * (len(screenshot_files) - 1) / (n - 1)) for i in range(n)]
                    frames = [screenshot_files[i] for i in indices]
    
    return frames


def get_final_screenshot(traj: Dict[str, Any]) -> Optional[str]:
    """Get the final screenshot from trajectory."""
    # Check for explicit final frame
    if 'final_frame' in traj:
        return traj['final_frame']
    
    # Get last frame from frames list
    if 'frames' in traj and traj['frames']:
        return traj['frames'][-1]
    
    # Check episode directory
    if 'episode_dir' in traj:
        episode_dir = traj['episode_dir']
        if os.path.isdir(episode_dir):
            screenshot_files = sorted([
                os.path.join(episode_dir, f)
                for f in os.listdir(episode_dir)
                if f.endswith('.png')
            ])
            if screenshot_files:
                return screenshot_files[-1]
    
    return None


# ================================================================
# MAIN VERIFICATION FUNCTION
# ================================================================

def verify_view_history_navigation(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify view history navigation task completion.
    
    Uses multiple independent signals:
    1. File existence and timestamp (programmatic)
    2. Image validity (programmatic)
    3. VLM content verification on output file
    4. VLM trajectory verification for workflow
    
    Args:
        traj: Trajectory data with frames
        env_info: Environment info with copy_from_env and query_vlm
        task_info: Task metadata
        
    Returns:
        dict with 'passed', 'score', 'feedback'
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "❌ copy_from_env function not available"
        }
    
    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/niagara_history_return.png')
    min_file_size_kb = metadata.get('min_file_size_kb', 50)
    
    feedback_parts = []
    score = 0
    details = {}
    
    # ================================================================
    # STEP 1: Copy and parse result JSON from container
    # ================================================================
    result = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        details['export_result'] = result
    except Exception as e:
        logger.warning(f"Failed to read task result: {e}")
        details['export_error'] = str(e)
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # CRITERION 1: Output file exists (15 points)
    # ================================================================
    output_exists = result.get('output_exists', False)
    output_size = result.get('output_size_bytes', 0)
    
    if output_exists and output_size > 0:
        score += 15
        feedback_parts.append(f"✅ Output file exists ({output_size} bytes)")
        details['output_exists'] = True
    else:
        feedback_parts.append("❌ Output file not found")
        details['output_exists'] = False
        # Can't verify much else without the file
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: File created during task - ANTI-GAMING (15 points)
    # ================================================================
    file_created_during_task = result.get('file_created_during_task', False)
    task_start = result.get('task_start', 0)
    output_mtime = result.get('output_mtime', 0)
    
    if file_created_during_task:
        score += 15
        feedback_parts.append("✅ File created during task (timestamp valid)")
        details['timestamp_valid'] = True
    elif output_mtime > 0 and task_start > 0:
        # File exists but was created before task started - suspicious
        feedback_parts.append("⚠️ File timestamp predates task start")
        details['timestamp_valid'] = False
        score += 5  # Partial credit - file exists but timing suspicious
    else:
        feedback_parts.append("⚠️ Could not verify file timestamp")
        details['timestamp_valid'] = None
        score += 7  # Some credit if we can't determine
    
    # ================================================================
    # CRITERION 3: Valid image with reasonable dimensions (10 points)
    # ================================================================
    image_valid = result.get('image_valid', False)
    image_width = result.get('image_width', 0)
    image_height = result.get('image_height', 0)
    image_format = result.get('image_format', 'unknown')
    
    if image_valid and image_width >= 800 and image_height >= 600:
        score += 10
        feedback_parts.append(f"✅ Valid image ({image_width}x{image_height} {image_format})")
        details['image_valid'] = True
    elif image_valid:
        score += 5
        feedback_parts.append(f"⚠️ Image valid but small ({image_width}x{image_height})")
        details['image_valid'] = True
    else:
        feedback_parts.append(f"❌ Invalid image or format issue ({image_format})")
        details['image_valid'] = False
    
    # ================================================================
    # CRITERION 4: VLM - Output shows Niagara Falls (35 points)
    # ================================================================
    vlm_content_score = 0
    
    if query_vlm:
        # Copy the output image to verify content
        temp_image = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env(expected_output_path, temp_image.name)
            
            # Query VLM to verify content
            vlm_result = query_vlm(
                prompt=NIAGARA_FALLS_VERIFICATION_PROMPT,
                image=temp_image.name
            )
            details['vlm_content_result'] = vlm_result
            
            if vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                
                is_google_earth = parsed.get('is_google_earth', False)
                shows_niagara = parsed.get('shows_niagara_falls', False)
                confidence = parsed.get('confidence', 'low')
                view_quality = parsed.get('view_quality', 'poor')
                
                # Calculate VLM content score
                if shows_niagara and is_google_earth:
                    if confidence == 'high':
                        vlm_content_score = 35
                    elif confidence == 'medium':
                        vlm_content_score = 28
                    else:
                        vlm_content_score = 20
                    feedback_parts.append(f"✅ VLM confirms Niagara Falls ({confidence} confidence)")
                elif is_google_earth:
                    vlm_content_score = 10
                    feedback_parts.append(f"⚠️ Google Earth view but Niagara Falls not confirmed")
                else:
                    feedback_parts.append(f"❌ VLM could not confirm Niagara Falls")
                
                details['shows_niagara_falls'] = shows_niagara
                details['vlm_confidence'] = confidence
            else:
                feedback_parts.append(f"⚠️ VLM content check failed: {vlm_result.get('error', 'unknown')}")
                vlm_content_score = 0
                
        except Exception as e:
            logger.warning(f"Failed to verify output image: {e}")
            feedback_parts.append(f"⚠️ Could not copy output for VLM verification")
            details['vlm_copy_error'] = str(e)
        finally:
            if os.path.exists(temp_image.name):
                os.unlink(temp_image.name)
    else:
        feedback_parts.append("⚠️ VLM not available for content verification")
    
    score += vlm_content_score
    details['vlm_content_score'] = vlm_content_score
    
    # ================================================================
    # CRITERION 5: VLM - Trajectory shows proper workflow (25 points)
    # ================================================================
    vlm_trajectory_score = 0
    
    if query_vlm:
        trajectory_frames = get_trajectory_frames(traj, n=6)
        
        if trajectory_frames and len(trajectory_frames) >= 3:
            try:
                vlm_traj_result = query_vlm(
                    prompt=TRAJECTORY_VERIFICATION_PROMPT,
                    images=trajectory_frames
                )
                details['vlm_trajectory_result'] = vlm_traj_result
                
                if vlm_traj_result.get('success'):
                    parsed = vlm_traj_result.get('parsed', {})
                    
                    multi_location = parsed.get('multi_location_visited', False)
                    num_locations = parsed.get('num_distinct_locations', 0)
                    workflow_progression = parsed.get('workflow_progression', False)
                    appears_to_return = parsed.get('appears_to_return', False)
                    confidence = parsed.get('confidence', 'low')
                    
                    # Score based on trajectory evidence
                    if multi_location and num_locations >= 3 and workflow_progression:
                        if appears_to_return:
                            vlm_trajectory_score = 25
                            feedback_parts.append(f"✅ Trajectory shows 3+ locations with history return")
                        else:
                            vlm_trajectory_score = 18
                            feedback_parts.append(f"✅ Trajectory shows multi-location navigation")
                    elif multi_location and num_locations >= 2:
                        vlm_trajectory_score = 12
                        feedback_parts.append(f"⚠️ Trajectory shows {num_locations} locations")
                    elif workflow_progression:
                        vlm_trajectory_score = 8
                        feedback_parts.append(f"⚠️ Some navigation activity detected")
                    else:
                        feedback_parts.append(f"❌ Trajectory does not show expected workflow")
                    
                    details['num_locations_detected'] = num_locations
                    details['workflow_progression'] = workflow_progression
                else:
                    feedback_parts.append(f"⚠️ VLM trajectory check failed")
                    
            except Exception as e:
                logger.warning(f"Trajectory VLM check failed: {e}")
                feedback_parts.append(f"⚠️ Trajectory verification error")
                details['vlm_trajectory_error'] = str(e)
        else:
            feedback_parts.append(f"⚠️ Insufficient trajectory frames ({len(trajectory_frames) if trajectory_frames else 0})")
            # Give partial credit if we couldn't get trajectory
            vlm_trajectory_score = 5
    else:
        feedback_parts.append("⚠️ VLM not available for trajectory verification")
        vlm_trajectory_score = 5  # Partial credit
    
    score += vlm_trajectory_score
    details['vlm_trajectory_score'] = vlm_trajectory_score
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    max_score = 100
    details['score_breakdown'] = {
        'file_exists': 15 if output_exists else 0,
        'timestamp_valid': 15 if file_created_during_task else (5 if output_exists else 0),
        'image_valid': 10 if (image_valid and image_width >= 800) else (5 if image_valid else 0),
        'vlm_content': vlm_content_score,
        'vlm_trajectory': vlm_trajectory_score
    }
    
    # Key criteria for passing:
    # - File must exist and be created during task
    # - VLM must confirm Niagara Falls content (score > 15 for this criterion)
    key_criteria_met = (
        output_exists and 
        (file_created_during_task or details.get('timestamp_valid') is None) and
        vlm_content_score >= 15
    )
    
    passed = score >= 60 and key_criteria_met
    
    # Final feedback
    feedback = " | ".join(feedback_parts)
    if passed:
        feedback = f"✅ PASSED (Score: {score}/{max_score}) | " + feedback
    else:
        feedback = f"❌ FAILED (Score: {score}/{max_score}) | " + feedback
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }