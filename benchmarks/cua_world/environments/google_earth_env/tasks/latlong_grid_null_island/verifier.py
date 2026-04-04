#!/usr/bin/env python3
"""
Verifier for latlong_grid_null_island task.

VERIFICATION STRATEGY:
This task requires the agent to:
1. Navigate to 0°N, 0°E (Null Island in Gulf of Guinea)
2. Enable the latitude/longitude grid overlay (View > Grid)
3. Save a screenshot showing the grid lines over the ocean

MULTI-SIGNAL VERIFICATION:
1. Output file exists at /home/ga/null_island_grid.png (15 points)
2. File was created during task window (15 points) - anti-gaming
3. Image has valid format and minimum dimensions (10 points)
4. VLM trajectory: Shows progression through navigation and grid enablement (25 points)
5. VLM final: Grid lines visible in screenshot (20 points)
6. VLM final: Correct location - ocean/Gulf of Guinea area (15 points)

Pass threshold: 60 points AND file exists AND (file created during task OR grid visible)
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ================================================================
# VLM PROMPTS
# ================================================================

TRAJECTORY_VERIFICATION_PROMPT = """You are analyzing a sequence of screenshots from an agent working in Google Earth Pro.

The agent's task was to:
1. Navigate to coordinates 0, 0 (Null Island - Gulf of Guinea, west of Africa)
2. Enable the latitude/longitude grid overlay (View > Grid)
3. Save a screenshot

These images are sampled chronologically from the agent's interaction (earliest to latest).

Analyze the progression and determine:
1. GOOGLE_EARTH_VISIBLE: Is Google Earth Pro the application being used?
2. NAVIGATION_OCCURRED: Did the agent navigate/search for a location? Look for:
   - Search dialog or search bar being used
   - View changing from one location to another
   - Globe/map moving or zooming
3. GRID_ENABLED: At any point, are latitude/longitude grid lines visible? (Yellow/white lines forming a grid pattern over the Earth)
4. OCEAN_VISIBLE: Is ocean/water visible in any frame? (The Gulf of Guinea is open ocean)
5. MEANINGFUL_WORK: Did the agent perform meaningful actions (not just sitting idle)?

Respond in JSON format:
{
    "google_earth_visible": true/false,
    "navigation_occurred": true/false,
    "grid_enabled": true/false,
    "ocean_visible": true/false,
    "meaningful_work": true/false,
    "stages_observed": ["list what you observed: 'app open', 'search used', 'navigation', 'grid visible', etc."],
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what the agent did across the frames"
}
"""

FINAL_IMAGE_VERIFICATION_PROMPT = """You are verifying a screenshot that should show a latitude/longitude grid visualization in Google Earth Pro.

The expected output is:
- Google Earth showing the Gulf of Guinea area (0°N, 0°E - open ocean west of Africa)
- Latitude and longitude grid lines visible (yellow or white lines forming a coordinate grid)
- The view should show ocean with possibly some African coastline visible in the distance

Analyze this image and determine:

1. IS_GOOGLE_EARTH: Is this a Google Earth screenshot (satellite imagery, not a photo)?
2. GRID_LINES_VISIBLE: Are latitude/longitude grid lines visible? These are:
   - Straight lines forming a grid pattern
   - Usually yellow or white in color
   - Cross the entire view horizontally and vertically
   - Spaced at regular intervals (degrees)
3. SHOWS_OCEAN: Does the image show open ocean/water? The Gulf of Guinea is dark blue Atlantic Ocean.
4. CORRECT_REGION: Does this appear to be near the equator and prime meridian? Look for:
   - Tropical Atlantic Ocean
   - Possibly African coastline (Ghana, Nigeria area) visible to the east/north
   - Ocean area characteristic of Gulf of Guinea
5. GRID_INTERSECTION_VISIBLE: Can you see where grid lines cross each other?

Respond in JSON format:
{
    "is_google_earth": true/false,
    "grid_lines_visible": true/false,
    "shows_ocean": true/false,
    "correct_region": true/false,
    "grid_intersection_visible": true/false,
    "num_grid_lines_estimated": 0,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation of what you see in the image"
}
"""


# ================================================================
# HELPER FUNCTIONS
# ================================================================

def get_trajectory_frames(traj: Dict[str, Any], n: int = 5) -> list:
    """Sample n frames from the trajectory for VLM verification."""
    try:
        from gym_anything.vlm import sample_trajectory_frames
        return sample_trajectory_frames(traj, n=n)
    except ImportError:
        logger.warning("Could not import sample_trajectory_frames, falling back to manual extraction")
        
    # Fallback: try to extract frames manually
    frames = traj.get('frames', [])
    if not frames:
        return []
    
    if len(frames) <= n:
        return frames
    
    # Sample evenly across trajectory
    indices = [int(i * (len(frames) - 1) / (n - 1)) for i in range(n)]
    return [frames[i] for i in indices]


def get_final_screenshot(traj: Dict[str, Any]):
    """Get the final screenshot from trajectory."""
    try:
        from gym_anything.vlm import get_final_screenshot as gfs
        return gfs(traj)
    except ImportError:
        pass
    
    # Fallback
    frames = traj.get('frames', [])
    if frames:
        return frames[-1]
    return None


def query_vlm_safe(query_vlm, prompt: str, image=None, images=None) -> Dict[str, Any]:
    """Safely query VLM with error handling."""
    if not query_vlm:
        return {"success": False, "error": "VLM query function not available"}
    
    try:
        if images:
            result = query_vlm(prompt=prompt, images=images)
        elif image:
            result = query_vlm(prompt=prompt, image=image)
        else:
            return {"success": False, "error": "No image provided"}
        
        return result
    except Exception as e:
        logger.error(f"VLM query failed: {e}")
        return {"success": False, "error": str(e)}


# ================================================================
# MAIN VERIFICATION FUNCTION
# ================================================================

def verify_latlong_grid_null_island(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the latlong_grid_null_island task.
    
    Uses MULTIPLE INDEPENDENT SIGNALS to prevent gaming:
    1. File existence and properties (from container via copy_from_env)
    2. Timestamp verification (anti-gaming)
    3. VLM trajectory analysis (proves work was done)
    4. VLM final image analysis (verifies content)
    
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
            "feedback": "❌ Copy function not available - cannot verify task"
        }
    
    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/null_island_grid.png')
    min_width = metadata.get('min_image_width', 1024)
    min_height = metadata.get('min_image_height', 768)
    
    feedback_parts = []
    score = 0
    result_details = {}
    
    # ================================================================
    # STEP 1: Copy and parse result JSON from container
    # ================================================================
    
    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            result = json.load(f)
        result_details['export_result'] = result
    except Exception as e:
        logger.error(f"Failed to read task result: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Failed to read task result: {e}"
        }
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)
    
    # ================================================================
    # CRITERION 1: Output file exists (15 points)
    # ================================================================
    
    output_exists = result.get('output_exists', False)
    
    if output_exists:
        score += 15
        feedback_parts.append("✅ Output file exists at /home/ga/null_island_grid.png (+15)")
    else:
        feedback_parts.append("❌ Output file NOT found - task incomplete (+0)")
        # Can't proceed without output file
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": result_details
        }
    
    # ================================================================
    # CRITERION 2: File created during task (15 points) - ANTI-GAMING
    # ================================================================
    
    file_created_during_task = result.get('file_created_during_task', False)
    
    if file_created_during_task:
        score += 15
        feedback_parts.append("✅ File created during task window (+15)")
    else:
        feedback_parts.append("⚠️ File timestamp suspicious - may have existed before task (+0)")
    
    # ================================================================
    # CRITERION 3: Valid image format and dimensions (10 points)
    # ================================================================
    
    image_width = result.get('image_width', 0)
    image_height = result.get('image_height', 0)
    image_format = result.get('image_format', 'unknown')
    
    valid_format = image_format.upper() in ['PNG', 'JPEG', 'JPG', 'BMP', 'TIFF']
    size_ok = image_width >= min_width and image_height >= min_height
    
    if valid_format and size_ok:
        score += 10
        feedback_parts.append(f"✅ Valid image: {image_format} {image_width}x{image_height} (+10)")
    elif valid_format:
        score += 5
        feedback_parts.append(f"⚠️ Image format OK but small: {image_width}x{image_height} (+5)")
    else:
        feedback_parts.append(f"❌ Invalid image format or dimensions (+0)")
    
    # ================================================================
    # CRITERION 4: VLM Trajectory Verification (25 points)
    # Proves agent actually did work, not just created a file
    # ================================================================
    
    trajectory_score = 0
    
    if query_vlm:
        trajectory_frames = get_trajectory_frames(traj, n=5)
        
        if trajectory_frames:
            vlm_traj_result = query_vlm_safe(
                query_vlm,
                prompt=TRAJECTORY_VERIFICATION_PROMPT,
                images=trajectory_frames
            )
            result_details['vlm_trajectory'] = vlm_traj_result
            
            if vlm_traj_result.get('success'):
                parsed = vlm_traj_result.get('parsed', {})
                
                ge_visible = parsed.get('google_earth_visible', False)
                navigation = parsed.get('navigation_occurred', False)
                grid_enabled = parsed.get('grid_enabled', False)
                meaningful = parsed.get('meaningful_work', False)
                confidence = parsed.get('confidence', 'low')
                
                # Score trajectory criteria
                traj_criteria = sum([ge_visible, navigation, grid_enabled, meaningful])
                
                if confidence == 'high':
                    trajectory_score = int((traj_criteria / 4) * 25)
                elif confidence == 'medium':
                    trajectory_score = int((traj_criteria / 4) * 22)
                else:
                    trajectory_score = int((traj_criteria / 4) * 18)
                
                score += trajectory_score
                
                stages = parsed.get('stages_observed', [])
                feedback_parts.append(f"✅ Trajectory analysis: {traj_criteria}/4 criteria met (+{trajectory_score})")
                if stages:
                    feedback_parts.append(f"   Observed: {', '.join(stages[:3])}")
            else:
                feedback_parts.append(f"⚠️ Trajectory VLM failed: {vlm_traj_result.get('error', 'unknown')}")
        else:
            feedback_parts.append("⚠️ No trajectory frames available for verification")
    else:
        feedback_parts.append("⚠️ VLM not available for trajectory verification")
    
    # ================================================================
    # CRITERION 5 & 6: VLM Final Image Verification (35 points total)
    # - Grid lines visible: 20 points
    # - Correct location (ocean): 15 points
    # ================================================================
    
    grid_verified = False
    location_verified = False
    
    if query_vlm:
        # Try to copy the actual output image for VLM analysis
        temp_output_file = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env(expected_output_path, temp_output_file.name)
            
            # Read image for VLM
            with open(temp_output_file.name, 'rb') as f:
                output_image_data = f.read()
            
            if output_image_data:
                vlm_final_result = query_vlm_safe(
                    query_vlm,
                    prompt=FINAL_IMAGE_VERIFICATION_PROMPT,
                    image=temp_output_file.name
                )
                result_details['vlm_final_image'] = vlm_final_result
                
                if vlm_final_result.get('success'):
                    parsed = vlm_final_result.get('parsed', {})
                    
                    is_ge = parsed.get('is_google_earth', False)
                    grid_visible = parsed.get('grid_lines_visible', False)
                    shows_ocean = parsed.get('shows_ocean', False)
                    correct_region = parsed.get('correct_region', False)
                    confidence = parsed.get('confidence', 'low')
                    reasoning = parsed.get('reasoning', '')
                    
                    # Grid lines visible (20 points)
                    if grid_visible and is_ge:
                        grid_verified = True
                        if confidence == 'high':
                            score += 20
                            feedback_parts.append("✅ Grid lines clearly visible (+20)")
                        elif confidence == 'medium':
                            score += 16
                            feedback_parts.append("✅ Grid lines visible (+16)")
                        else:
                            score += 12
                            feedback_parts.append("⚠️ Grid lines possibly visible (+12)")
                    elif grid_visible:
                        score += 8
                        feedback_parts.append("⚠️ Grid detected but unclear context (+8)")
                    else:
                        feedback_parts.append("❌ Grid lines NOT detected in output image (+0)")
                    
                    # Correct location - ocean/Gulf of Guinea (15 points)
                    if shows_ocean and (correct_region or is_ge):
                        location_verified = True
                        if correct_region and confidence in ['high', 'medium']:
                            score += 15
                            feedback_parts.append("✅ Gulf of Guinea/ocean area confirmed (+15)")
                        else:
                            score += 10
                            feedback_parts.append("✅ Ocean area visible (+10)")
                    elif shows_ocean:
                        score += 7
                        feedback_parts.append("⚠️ Ocean visible, location uncertain (+7)")
                    else:
                        feedback_parts.append("❌ Expected ocean area not detected (+0)")
                    
                    if reasoning:
                        feedback_parts.append(f"   VLM: {reasoning[:100]}")
                else:
                    feedback_parts.append(f"⚠️ Final image VLM failed: {vlm_final_result.get('error', 'unknown')}")
        except Exception as e:
            logger.warning(f"Could not analyze output image: {e}")
            feedback_parts.append(f"⚠️ Could not analyze output image: {e}")
        finally:
            if os.path.exists(temp_output_file.name):
                os.unlink(temp_output_file.name)
    else:
        # Without VLM, award partial points if file checks pass
        if output_exists and file_created_during_task and size_ok:
            score += 20
            feedback_parts.append("⚠️ VLM unavailable - awarding partial points for valid file (+20)")
    
    # ================================================================
    # CALCULATE FINAL RESULT
    # ================================================================
    
    # Key criteria: file must exist AND (created during task OR grid verified)
    key_criteria_met = output_exists and (file_created_during_task or grid_verified)
    
    # Pass threshold: 60 points AND key criteria
    passed = score >= 60 and key_criteria_met
    
    # Build final feedback
    feedback = " | ".join(feedback_parts)
    feedback += f" | Final score: {score}/100"
    
    if passed:
        feedback = "✅ PASSED: " + feedback
    else:
        if not key_criteria_met:
            feedback = "❌ FAILED (key criteria not met): " + feedback
        else:
            feedback = "❌ FAILED (score below threshold): " + feedback
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": result_details
    }