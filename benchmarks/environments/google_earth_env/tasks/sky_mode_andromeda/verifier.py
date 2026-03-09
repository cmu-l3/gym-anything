#!/usr/bin/env python3
"""
Verifier for Sky Mode Andromeda task.

HYBRID VERIFICATION STRATEGY:
1. Programmatic checks (from export_result.json):
   - Output file exists and is valid JPEG (20 points)
   - File created during task - anti-gaming (10 points)
   - Image resolution meets requirements (15 points)
   - File size indicates substantial content (5 points)

2. VLM trajectory verification (multiple frames):
   - Sky mode was activated - starfield visible (15 points)
   - M31/Andromeda Galaxy was located (20 points)
   - Saved image shows galaxy content (15 points)

Total: 100 points
Pass threshold: 60 points with key criteria (file created + resolution ok)
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

TRAJECTORY_VERIFICATION_PROMPT = """You are analyzing a sequence of screenshots from an agent using Google Earth Pro to document the Andromeda Galaxy.

The task required the agent to:
1. Switch from Earth view to Sky mode (shows stars instead of Earth)
2. Search for and locate the Andromeda Galaxy (M31)
3. Save an image of the galaxy

Analyze these trajectory screenshots (ordered earliest to latest) and determine:

1. SKY_MODE_ACTIVATED: Did the view change from Earth (globe/terrain) to Sky (starfield with stars/nebulae)?
   - Earth mode shows: blue oceans, continents, terrain, satellite imagery
   - Sky mode shows: black background with stars, constellations, galaxies, nebulae

2. SEARCH_PERFORMED: Is there evidence of using the search panel to find "Andromeda", "M31", or "Messier 31"?
   - Look for search panel open with text entered
   - Or navigation to a specific celestial object

3. ANDROMEDA_VISIBLE: At any point, is a large spiral/elliptical galaxy visible?
   - Andromeda (M31) appears as a large, elongated fuzzy elliptical shape
   - It's much larger than other galaxies in the field
   - May show spiral arm structure or bright central core

4. SAVE_DIALOG_USED: Is there evidence of using File > Save > Save Image dialog?
   - File dialog windows
   - Save/export interface

Respond in JSON format:
{
    "sky_mode_activated": true/false,
    "search_performed": true/false,
    "andromeda_visible": true/false,
    "save_dialog_used": true/false,
    "mode_transition_observed": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see across the frames"
}
"""

IMAGE_CONTENT_PROMPT = """You are verifying if a saved image shows the Andromeda Galaxy from Google Earth's Sky mode.

The Andromeda Galaxy (M31) characteristics:
- Large elliptical/spiral shape, tilted at an angle (about 77 degrees to our line of sight)
- Bright central core/bulge
- Extends across a large portion of the view (larger than most other galaxies)
- May show spiral arm structure
- Surrounded by background stars
- NOT: Earth terrain, satellite imagery, or the Earth globe

Analyze this image and determine:

1. IS_SKY_MODE_IMAGE: Does this show a starfield/space view (not Earth)?
   - Black background with stars
   - No Earth terrain, oceans, or satellite imagery

2. SHOWS_GALAXY: Is there a galaxy (elliptical/spiral structure) visible?
   - Fuzzy elliptical or spiral shape
   - Not just point-like stars

3. LIKELY_ANDROMEDA: Does the visible galaxy match Andromeda characteristics?
   - Large, dominant galaxy in the field
   - Elliptical/tilted spiral shape
   - Bright central core

4. IMAGE_QUALITY: Is the image clear and properly captured?
   - Not a screenshot of empty desktop
   - Not corrupted or blank
   - Shows actual celestial content

Respond in JSON format:
{
    "is_sky_mode_image": true/false,
    "shows_galaxy": true/false,
    "likely_andromeda": true/false,
    "image_quality_acceptable": true/false,
    "confidence": "low"/"medium"/"high",
    "description": "describe what you see in the image"
}
"""


def verify_sky_mode_andromeda(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the Sky Mode Andromeda task using hybrid verification.
    
    Uses MULTIPLE INDEPENDENT SIGNALS:
    1. Programmatic: File existence, timestamps, resolution
    2. VLM Trajectory: Process verification across multiple frames
    3. VLM Content: Saved image content analysis
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available for verification"
        }
    
    metadata = task_info.get('metadata', {})
    expected_output = metadata.get('expected_output_path', '/home/ga/Documents/andromeda_m31.jpg')
    min_width = metadata.get('min_resolution_width', 1920)
    min_height = metadata.get('min_resolution_height', 1080)
    min_file_size_kb = metadata.get('min_file_size_kb', 100)
    
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
        logger.warning(f"Could not read task_result.json: {e}")
        feedback_parts.append(f"⚠️ Could not read export result: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # CRITERION 1: Output file exists and is valid (20 points)
    # ================================================================
    output_exists = result.get('output_exists', False)
    image_format = result.get('image_format', 'none')
    output_size = result.get('output_size_bytes', 0)
    
    if output_exists and image_format.upper() in ['JPEG', 'JPG']:
        score += 20
        feedback_parts.append(f"✅ Output file exists (JPEG, {output_size} bytes)")
        details['file_valid'] = True
    elif output_exists:
        score += 10
        feedback_parts.append(f"⚠️ Output file exists but format is {image_format}")
        details['file_valid'] = False
    else:
        feedback_parts.append("❌ Output file NOT found")
        details['file_valid'] = False
    
    # ================================================================
    # CRITERION 2: File created during task - ANTI-GAMING (10 points)
    # ================================================================
    file_created_during_task = result.get('file_created_during_task', False)
    task_start = result.get('task_start', 0)
    output_mtime = result.get('output_mtime', 0)
    
    if file_created_during_task:
        score += 10
        feedback_parts.append("✅ File created during task execution")
        details['timestamp_valid'] = True
    elif output_exists:
        feedback_parts.append("⚠️ File may have existed before task (timestamp issue)")
        details['timestamp_valid'] = False
    else:
        details['timestamp_valid'] = False
    
    # ================================================================
    # CRITERION 3: Image resolution meets requirements (15 points)
    # ================================================================
    image_width = result.get('image_width', 0)
    image_height = result.get('image_height', 0)
    
    width_ok = image_width >= min_width
    height_ok = image_height >= min_height
    
    if width_ok and height_ok:
        score += 15
        feedback_parts.append(f"✅ Resolution OK ({image_width}x{image_height})")
        details['resolution_ok'] = True
    elif image_width > 0 and image_height > 0:
        # Partial credit for smaller resolution
        score += 7
        feedback_parts.append(f"⚠️ Resolution below target ({image_width}x{image_height}, need {min_width}x{min_height})")
        details['resolution_ok'] = False
    else:
        feedback_parts.append("❌ Could not determine image resolution")
        details['resolution_ok'] = False
    
    # ================================================================
    # CRITERION 4: File size indicates content (5 points)
    # ================================================================
    file_size_kb = output_size / 1024 if output_size else 0
    
    if file_size_kb >= min_file_size_kb:
        score += 5
        feedback_parts.append(f"✅ File size OK ({file_size_kb:.1f} KB)")
        details['size_ok'] = True
    elif file_size_kb > 10:
        score += 2
        feedback_parts.append(f"⚠️ File size small ({file_size_kb:.1f} KB)")
        details['size_ok'] = False
    else:
        feedback_parts.append(f"❌ File too small ({file_size_kb:.1f} KB)")
        details['size_ok'] = False
    
    # ================================================================
    # VLM VERIFICATION (if available)
    # ================================================================
    vlm_trajectory_score = 0
    vlm_content_score = 0
    
    if query_vlm:
        # ============================================================
        # CRITERION 5: Trajectory verification - Sky mode + search (15 points)
        # ============================================================
        try:
            # Get trajectory frames (sample across the episode)
            frames = traj.get('frames', [])
            if frames and len(frames) > 0:
                # Sample frames across trajectory
                num_frames = len(frames)
                if num_frames <= 5:
                    sampled_indices = list(range(num_frames))
                else:
                    # Sample 5 frames evenly distributed
                    step = num_frames // 5
                    sampled_indices = [i * step for i in range(5)]
                    if sampled_indices[-1] != num_frames - 1:
                        sampled_indices[-1] = num_frames - 1
                
                sampled_frames = [frames[i] for i in sampled_indices if i < len(frames)]
                
                if sampled_frames:
                    vlm_result = query_vlm(
                        prompt=TRAJECTORY_VERIFICATION_PROMPT,
                        images=sampled_frames
                    )
                    
                    if vlm_result.get('success'):
                        parsed = vlm_result.get('parsed', {})
                        details['vlm_trajectory'] = parsed
                        
                        sky_mode = parsed.get('sky_mode_activated', False)
                        andromeda_vis = parsed.get('andromeda_visible', False)
                        confidence = parsed.get('confidence', 'low')
                        
                        if sky_mode:
                            vlm_trajectory_score += 8
                            feedback_parts.append("✅ VLM: Sky mode activation confirmed")
                        else:
                            feedback_parts.append("⚠️ VLM: Sky mode not clearly detected")
                        
                        if andromeda_vis:
                            vlm_trajectory_score += 7
                            feedback_parts.append("✅ VLM: Andromeda Galaxy visible in trajectory")
                        else:
                            feedback_parts.append("⚠️ VLM: Andromeda not clearly visible")
                        
                        # Confidence adjustment
                        if confidence == 'low':
                            vlm_trajectory_score = int(vlm_trajectory_score * 0.7)
                    else:
                        feedback_parts.append(f"⚠️ VLM trajectory query failed: {vlm_result.get('error', 'unknown')}")
        except Exception as e:
            logger.warning(f"VLM trajectory verification failed: {e}")
            feedback_parts.append(f"⚠️ VLM trajectory error: {e}")
        
        score += vlm_trajectory_score
        
        # ============================================================
        # CRITERION 6: Content verification - saved image (20 points)
        # ============================================================
        if output_exists:
            try:
                # Copy the saved image for VLM analysis
                temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.jpg')
                try:
                    copy_from_env(expected_output, temp_img.name)
                    
                    # Query VLM about the saved image content
                    vlm_content_result = query_vlm(
                        prompt=IMAGE_CONTENT_PROMPT,
                        image=temp_img.name
                    )
                    
                    if vlm_content_result.get('success'):
                        content_parsed = vlm_content_result.get('parsed', {})
                        details['vlm_content'] = content_parsed
                        
                        is_sky = content_parsed.get('is_sky_mode_image', False)
                        shows_galaxy = content_parsed.get('shows_galaxy', False)
                        likely_andromeda = content_parsed.get('likely_andromeda', False)
                        quality_ok = content_parsed.get('image_quality_acceptable', False)
                        content_confidence = content_parsed.get('confidence', 'low')
                        
                        if is_sky and shows_galaxy:
                            if likely_andromeda:
                                vlm_content_score = 20
                                feedback_parts.append("✅ VLM: Image shows Andromeda Galaxy in Sky mode")
                            else:
                                vlm_content_score = 12
                                feedback_parts.append("⚠️ VLM: Image shows a galaxy, may not be Andromeda")
                        elif is_sky:
                            vlm_content_score = 8
                            feedback_parts.append("⚠️ VLM: Image shows Sky mode but galaxy not clear")
                        elif quality_ok:
                            vlm_content_score = 4
                            feedback_parts.append("⚠️ VLM: Image captured but not Sky mode content")
                        else:
                            feedback_parts.append("❌ VLM: Image content does not match expectations")
                        
                        # Confidence adjustment
                        if content_confidence == 'low':
                            vlm_content_score = int(vlm_content_score * 0.8)
                    else:
                        feedback_parts.append(f"⚠️ VLM content query failed: {vlm_content_result.get('error', 'unknown')}")
                finally:
                    if os.path.exists(temp_img.name):
                        os.unlink(temp_img.name)
            except Exception as e:
                logger.warning(f"VLM content verification failed: {e}")
                feedback_parts.append(f"⚠️ VLM content error: {e}")
        
        score += vlm_content_score
        
        # ============================================================
        # CRITERION 7: M31 located (additional trajectory check) (15 points)
        # ============================================================
        # This is covered by trajectory verification above, but we can add
        # extra points if we have high confidence
        if details.get('vlm_trajectory', {}).get('andromeda_visible', False):
            if details.get('vlm_trajectory', {}).get('confidence') == 'high':
                score += 15
                feedback_parts.append("✅ High confidence M31 location confirmed")
            elif details.get('vlm_trajectory', {}).get('confidence') == 'medium':
                score += 10
                feedback_parts.append("✓ Medium confidence M31 location")
            else:
                score += 5
    else:
        # No VLM available - give partial credit based on programmatic checks
        feedback_parts.append("⚠️ VLM not available for visual verification")
        # Award some points if file exists and was created during task
        if output_exists and file_created_during_task:
            score += 15  # Partial VLM points
            feedback_parts.append("✓ File evidence suggests task completion")
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    details['programmatic_score'] = 50  # Max from programmatic checks
    details['vlm_score'] = vlm_trajectory_score + vlm_content_score
    details['total_score'] = score
    
    # Key criteria for passing
    key_criteria_met = (
        output_exists and 
        file_created_during_task and 
        (image_width >= min_width * 0.8 or vlm_content_score >= 10)
    )
    
    passed = score >= 60 and key_criteria_met
    
    # Build final feedback
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": feedback,
        "details": details
    }