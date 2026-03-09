#!/usr/bin/env python3
"""
Verifier for Urban Shadow Assessment task.

VERIFICATION STRATEGY:
Uses VLM-hybrid approach combining:
1. Programmatic file checks (existence, timestamp, size, resolution)
2. VLM trajectory analysis (process verification across multiple frames)
3. VLM final screenshot analysis (content verification)

SCORING (100 points total):
- File exists and valid format: 10 points
- File created during task (anti-gaming): 10 points  
- Image resolution adequate: 10 points
- Location correct (Dubai Marina): 20 points (VLM)
- View tilted (3D oblique): 15 points (VLM)
- Shadows visible: 20 points (VLM)
- Shadow direction correct (WNW for 4PM): 15 points (VLM)

PASS THRESHOLD: 70 points with location_correct AND shadows_visible met
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any, Optional, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ================================================================
# VLM PROMPTS
# ================================================================

TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent using Google Earth Pro to perform an urban shadow assessment task.

The images are sampled chronologically from the agent's interaction (earliest to latest).

For successful task completion, the agent should progress through these stages:
1. Google Earth Pro open - the application interface is visible
2. Navigation to Dubai Marina - zoomed view of a coastal urban area with tall buildings and a curved marina
3. Sunlight feature enabled - time slider visible OR shadows appearing on buildings/ground
4. View tilted - 3D oblique perspective showing building heights and shadows
5. Screenshot saved - though this may not be visible in the trajectory

Dubai Marina distinctive features:
- Curved marina waterway surrounded by tall residential towers
- Dense cluster of skyscrapers (30+ floors) 
- Marina Walk promenade along the water
- Distinctive buildings like Cayan Tower (twisted), Princess Tower, Marina Torch

Assess:
1. WORKFLOW_PROGRESSED: Did the agent navigate to a location and manipulate the view?
2. DUBAI_MARINA_VISIBLE: At any point, is the distinctive Dubai Marina area visible?
3. SHADOWS_APPEAR: At any point, do building shadows become visible on ground/water?
4. VIEW_CHANGES: Do the frames show meaningful state changes (not static)?

Respond in JSON format:
{
    "workflow_progressed": true/false,
    "dubai_marina_visible": true/false,
    "shadows_appear": true/false,
    "view_changes": true/false,
    "stages_observed": ["list what stages you can identify"],
    "confidence": "low"/"medium"/"high",
    "observations": "describe the progression you see"
}
"""

FINAL_CONTENT_PROMPT = """You are verifying a screenshot from Google Earth Pro showing an urban shadow assessment.

TASK: Document shadow patterns at Dubai Marina at 4:00 PM on June 21st.

Analyze this screenshot and assess:

1. IS_GOOGLE_EARTH: Is this Google Earth Pro (satellite imagery interface, not a photo)?

2. SHOWS_DUBAI_MARINA: Is Dubai Marina, UAE visible? Look for:
   - Curved marina waterway
   - Cluster of very tall residential towers (30-80 floors)
   - Dense waterfront development
   - Distinctive tower shapes (twisted Cayan Tower, tall Marina Torch)
   
3. VIEW_IS_TILTED: Is the view at an oblique 3D angle (not top-down)?
   - Buildings should appear in 3D showing their height
   - Perspective should show building sides, not just roofs
   - Horizon may be visible
   
4. SHADOWS_VISIBLE: Are building shadows clearly visible?
   - Dark shadow areas on ground, water, or other buildings
   - Shadows cast by tall structures
   - Clear contrast between sunlit and shaded areas
   
5. SHADOW_DIRECTION: Are shadows extending roughly west-northwest (WNW)?
   - At 4 PM in June, sun is in the southeast
   - Shadows should extend away from southeast toward WNW
   - Look at shadow orientation relative to buildings

6. TIME_SLIDER_VISIBLE: Is the sun/time slider interface visible?
   - Usually appears at top or side of screen when Sun feature is enabled
   - Shows date and time controls

Respond in JSON format:
{
    "is_google_earth": true/false,
    "shows_dubai_marina": true/false,
    "view_is_tilted": true/false,
    "shadows_visible": true/false,
    "shadow_direction_correct": true/false,
    "time_slider_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "detailed explanation of what you observe"
}
"""


# ================================================================
# HELPER FUNCTIONS
# ================================================================

def get_trajectory_frames(traj: Dict[str, Any], n: int = 5) -> List[str]:
    """Sample n frames evenly from trajectory."""
    frames = traj.get('frames', [])
    if not frames:
        return []
    
    if len(frames) <= n:
        return frames
    
    # Sample evenly across trajectory
    indices = [int(i * (len(frames) - 1) / (n - 1)) for i in range(n)]
    return [frames[i] for i in indices]


def get_final_screenshot(traj: Dict[str, Any]) -> Optional[str]:
    """Get the final screenshot from trajectory."""
    frames = traj.get('frames', [])
    if frames:
        return frames[-1]
    
    # Fallback to episode directory
    episode_dir = traj.get('episode_dir')
    if episode_dir:
        final_path = os.path.join(episode_dir, 'final_screenshot.png')
        if os.path.exists(final_path):
            return final_path
    
    return None


def query_vlm_safe(query_vlm, prompt: str, image: str = None, images: List[str] = None) -> Optional[Dict]:
    """Safely query VLM with error handling."""
    if not query_vlm:
        return None
    
    try:
        if images:
            result = query_vlm(prompt=prompt, images=images)
        elif image:
            result = query_vlm(prompt=prompt, image=image)
        else:
            return None
        
        if result.get("success"):
            return result.get("parsed", {})
        else:
            logger.warning(f"VLM query failed: {result.get('error', 'unknown')}")
            return None
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
        return None


# ================================================================
# MAIN VERIFICATION FUNCTION
# ================================================================

def verify_urban_shadow_assessment(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the Urban Shadow Assessment task.
    
    Uses multi-criteria scoring with VLM hybrid verification.
    
    Args:
        traj: Trajectory data with frames, steps, episode_dir
        env_info: Environment info with copy_from_env and query_vlm
        task_info: Task info with metadata
        
    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    metadata = task_info.get('metadata', {})
    
    feedback_parts = []
    score = 0
    details = {}
    
    # ================================================================
    # CRITERION 1: Copy and parse result file (10 points for file exists)
    # ================================================================
    result = None
    if copy_from_env:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
            details['result_file'] = result
        except Exception as e:
            logger.warning(f"Failed to read result file: {e}")
            details['result_file_error'] = str(e)
        finally:
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)
    
    if not result:
        feedback_parts.append("❌ Could not read task result file")
        # Continue with trajectory-based verification only
        result = {}
    
    # Extract file info from result
    output_info = result.get('output_file', {})
    output_exists = output_info.get('exists', False)
    output_size = output_info.get('size_bytes', 0)
    file_created_during_task = output_info.get('created_during_task', False)
    image_width = output_info.get('width', 0)
    image_height = output_info.get('height', 0)
    image_format = output_info.get('format', 'unknown')
    
    # Check file exists and is valid format
    if output_exists and image_format.upper() in ['PNG', 'JPEG', 'JPG', 'BMP', 'TIFF']:
        score += 10
        feedback_parts.append(f"✅ Output file exists ({image_format})")
        details['file_exists'] = True
    elif output_exists:
        score += 5
        feedback_parts.append(f"⚠️ Output file exists (format: {image_format})")
        details['file_exists'] = True
    else:
        feedback_parts.append("❌ Output file NOT found at /home/ga/shadow_assessment.png")
        details['file_exists'] = False
    
    # ================================================================
    # CRITERION 2: File created during task - anti-gaming (10 points)
    # ================================================================
    if file_created_during_task:
        score += 10
        feedback_parts.append("✅ File created during task execution")
        details['file_timestamp_valid'] = True
    elif output_exists:
        feedback_parts.append("⚠️ File may have existed before task (timestamp check failed)")
        details['file_timestamp_valid'] = False
    else:
        details['file_timestamp_valid'] = False
    
    # ================================================================
    # CRITERION 3: Image resolution (10 points)
    # ================================================================
    min_width = 1280
    min_height = 720
    
    if image_width >= min_width and image_height >= min_height:
        score += 10
        feedback_parts.append(f"✅ Good resolution: {image_width}x{image_height}")
        details['resolution_ok'] = True
    elif image_width >= 800 and image_height >= 600:
        score += 5
        feedback_parts.append(f"⚠️ Acceptable resolution: {image_width}x{image_height}")
        details['resolution_ok'] = True
    elif output_exists:
        feedback_parts.append(f"❌ Low resolution: {image_width}x{image_height}")
        details['resolution_ok'] = False
    else:
        details['resolution_ok'] = False
    
    # ================================================================
    # CRITERION 4-7: VLM-based verification (70 points total)
    # ================================================================
    
    vlm_score = 0
    location_correct = False
    shadows_visible = False
    
    if query_vlm:
        # First, analyze trajectory for process verification
        traj_frames = get_trajectory_frames(traj, n=5)
        if traj_frames:
            traj_result = query_vlm_safe(query_vlm, TRAJECTORY_PROCESS_PROMPT, images=traj_frames)
            details['trajectory_analysis'] = traj_result
            
            if traj_result:
                if traj_result.get('workflow_progressed', False):
                    feedback_parts.append("✅ Trajectory shows task progression")
                
                if traj_result.get('dubai_marina_visible', False):
                    feedback_parts.append("✅ Dubai Marina visible in trajectory")
                
                if traj_result.get('shadows_appear', False):
                    feedback_parts.append("✅ Shadows appeared during task")
        
        # Then, analyze final screenshot or saved output for content
        # Try to get the saved screenshot from container
        output_image = None
        if copy_from_env and output_exists:
            temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            try:
                copy_from_env("/home/ga/shadow_assessment.png", temp_img.name)
                if os.path.exists(temp_img.name) and os.path.getsize(temp_img.name) > 1000:
                    output_image = temp_img.name
            except Exception as e:
                logger.warning(f"Could not copy output image: {e}")
            
        # Fall back to final trajectory frame if needed
        if not output_image:
            output_image = get_final_screenshot(traj)
        
        if output_image:
            content_result = query_vlm_safe(query_vlm, FINAL_CONTENT_PROMPT, image=output_image)
            details['content_analysis'] = content_result
            
            if content_result:
                confidence = content_result.get('confidence', 'low')
                conf_multiplier = {'high': 1.0, 'medium': 0.85, 'low': 0.7}.get(confidence, 0.7)
                
                # CRITERION 4: Location correct (20 points)
                if content_result.get('is_google_earth', False):
                    if content_result.get('shows_dubai_marina', False):
                        location_correct = True
                        location_points = int(20 * conf_multiplier)
                        vlm_score += location_points
                        feedback_parts.append(f"✅ Dubai Marina location confirmed ({location_points} pts)")
                    else:
                        feedback_parts.append("❌ Location is not Dubai Marina")
                else:
                    feedback_parts.append("❌ Screenshot is not from Google Earth")
                
                # CRITERION 5: View tilted (15 points)
                if content_result.get('view_is_tilted', False):
                    tilt_points = int(15 * conf_multiplier)
                    vlm_score += tilt_points
                    feedback_parts.append(f"✅ View properly tilted for 3D shadows ({tilt_points} pts)")
                else:
                    feedback_parts.append("❌ View not tilted (top-down perspective)")
                
                # CRITERION 6: Shadows visible (20 points)
                if content_result.get('shadows_visible', False):
                    shadows_visible = True
                    shadow_points = int(20 * conf_multiplier)
                    vlm_score += shadow_points
                    feedback_parts.append(f"✅ Building shadows clearly visible ({shadow_points} pts)")
                else:
                    feedback_parts.append("❌ No visible shadows (sunlight feature may not be enabled)")
                
                # CRITERION 7: Shadow direction correct (15 points)
                if content_result.get('shadow_direction_correct', False):
                    dir_points = int(15 * conf_multiplier)
                    vlm_score += dir_points
                    feedback_parts.append(f"✅ Shadow direction correct for 4PM June ({dir_points} pts)")
                elif shadows_visible:
                    feedback_parts.append("⚠️ Shadow direction unclear or incorrect")
                
                # Bonus: time slider visible
                if content_result.get('time_slider_visible', False):
                    feedback_parts.append("✓ Sun/time slider visible in UI")
                
                details['vlm_reasoning'] = content_result.get('reasoning', '')
        else:
            feedback_parts.append("⚠️ No image available for VLM content verification")
        
        # Clean up temp image if we created one
        if output_image and output_image.startswith('/tmp/') and 'shadow_assessment' not in output_image:
            try:
                os.unlink(output_image)
            except:
                pass
    else:
        feedback_parts.append("⚠️ VLM not available - using file checks only")
    
    score += vlm_score
    details['vlm_score'] = vlm_score
    
    # ================================================================
    # FINAL SCORING AND PASS/FAIL DETERMINATION
    # ================================================================
    
    # Pass requires:
    # 1. Score >= 70 points
    # 2. Location must be correct (Dubai Marina)
    # 3. Shadows must be visible (sunlight feature was used)
    
    key_criteria_met = location_correct and shadows_visible
    passed = score >= 70 and key_criteria_met
    
    details['score_breakdown'] = {
        'file_checks': score - vlm_score,
        'vlm_checks': vlm_score,
        'total': score,
        'location_correct': location_correct,
        'shadows_visible': shadows_visible,
        'key_criteria_met': key_criteria_met
    }
    
    # Provide clear feedback on why task failed (if it did)
    if not passed:
        if score < 70:
            feedback_parts.append(f"❌ Score {score}/100 below 70 point threshold")
        if not location_correct:
            feedback_parts.append("❌ REQUIRED: Dubai Marina location not confirmed")
        if not shadows_visible:
            feedback_parts.append("❌ REQUIRED: Building shadows not visible (enable Sun feature)")
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }