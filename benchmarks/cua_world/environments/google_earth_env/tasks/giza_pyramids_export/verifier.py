#!/usr/bin/env python3
"""
Verifier for giza_pyramids_export task.

ROBUST MULTI-SIGNAL VERIFICATION:
1. Output file exists at correct path (15 points)
2. Valid PNG image format (10 points)
3. Resolution meets minimum requirements (10 points)
4. Non-trivial image content (5 points)
5. File created during task execution (15 points) - ANTI-GAMING
6. VLM: Image shows Pyramids of Giza (25 points)
7. VLM: All three major pyramids visible (10 points)
8. VLM: Aerial/top-down view (10 points)

Pass threshold: 60% AND key criteria (file created + pyramids visible)
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

CONTENT_VERIFICATION_PROMPT = """You are verifying an aerial/satellite image that should show the Pyramids of Giza in Egypt.

Analyze this image and determine:

1. LOCATION: Does this image show the Pyramids of Giza in Egypt?
   - Look for distinctive pyramid shapes (square bases, triangular sides)
   - Desert/sandy terrain surrounding the structures
   - The characteristic layout of the Giza pyramid complex

2. PYRAMID_COUNT: How many major pyramid structures are clearly visible?
   - The three main pyramids are: Great Pyramid (Khufu), Khafre, and Menkaure
   - Count only clear pyramid structures, not small queens' pyramids

3. VIEW_TYPE: What type of view is this?
   - "top-down" = looking straight down (bird's eye)
   - "angled" = tilted view showing pyramid sides
   - "ground-level" = horizontal view from ground
   - "not_giza" = this is not the Giza pyramids at all

4. IMAGE_QUALITY: Is the image clear enough to identify the structures?

Respond in JSON format:
{
    "shows_giza_pyramids": true/false,
    "pyramid_count": 0/1/2/3,
    "view_type": "top-down"/"angled"/"ground-level"/"not_giza",
    "image_quality_acceptable": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation of what you observe"
}
"""

TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from a Google Earth session where the agent should be:
1. Navigating to the Pyramids of Giza in Egypt
2. Configuring an aerial view
3. Saving an image

The images are sampled chronologically from the agent's full interaction.

For each screenshot, identify what stage the agent is at:
- SEARCH: Using the search box or navigation controls
- NAVIGATION: View is changing, flying to location
- GIZA_VISIBLE: Pyramids of Giza are visible in the view
- SAVE_DIALOG: A save/export dialog is open
- OTHER: Other interface states

Assess:
1. WORKFLOW_PROGRESSION: Did the agent progress through search → navigation → giza visible → save?
2. GIZA_REACHED: At any point, are the Giza pyramids visible?
3. SAVE_ATTEMPTED: Is there evidence of opening a save dialog?
4. MEANINGFUL_WORK: Do the frames show actual work being done (not static)?

Respond in JSON format:
{
    "workflow_progression": true/false,
    "giza_reached": true/false,
    "save_attempted": true/false,
    "meaningful_work": true/false,
    "stages_observed": ["list of stages seen"],
    "confidence": "low"/"medium"/"high",
    "observations": "describe the progression"
}
"""


def verify_giza_pyramids_export(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that agent exported an aerial image of the Giza pyramids.
    
    Uses MULTIPLE INDEPENDENT SIGNALS to prevent gaming:
    - File-based checks (existence, format, timestamps)
    - VLM verification on output image content
    - VLM verification on trajectory frames (workflow progression)
    
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
            "feedback": "❌ Copy function not available"
        }
    
    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/Desktop/giza_pyramids.png')
    min_width = metadata.get('min_width', 800)
    min_height = metadata.get('min_height', 600)
    min_file_size_kb = metadata.get('min_file_size_kb', 50)
    
    feedback_parts = []
    score = 0
    result_details = {}
    
    # ================================================================
    # STEP 1: Copy and parse task result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        result_details['task_result'] = result
    except Exception as e:
        logger.error(f"Failed to read task result: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Failed to read task result: {e}",
            "details": result_details
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # CRITERION 1: Output file exists at correct path (15 points)
    # ================================================================
    output_exists = result.get('output_exists', False)
    
    if output_exists:
        score += 15
        feedback_parts.append("✅ Output file exists at correct path")
    else:
        feedback_parts.append("❌ Output file NOT found at /home/ga/Desktop/giza_pyramids.png")
        # Early exit - nothing else meaningful to check
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": result_details
        }
    
    # ================================================================
    # CRITERION 2: Valid PNG image format (10 points)
    # ================================================================
    image_format = result.get('image_format', 'unknown')
    
    if image_format == 'PNG':
        score += 10
        feedback_parts.append("✅ Valid PNG format")
    elif image_format in ['JPEG', 'JPG', 'BMP', 'TIFF']:
        score += 5
        feedback_parts.append(f"⚠️ Image saved as {image_format} (not PNG)")
    else:
        feedback_parts.append(f"❌ Invalid/unknown format: {image_format}")
    
    # ================================================================
    # CRITERION 3: Resolution meets minimum requirements (10 points)
    # ================================================================
    image_width = result.get('image_width', 0)
    image_height = result.get('image_height', 0)
    
    if image_width >= min_width and image_height >= min_height:
        score += 10
        feedback_parts.append(f"✅ Resolution OK ({image_width}x{image_height})")
    elif image_width >= min_width * 0.5 and image_height >= min_height * 0.5:
        score += 5
        feedback_parts.append(f"⚠️ Resolution below optimal ({image_width}x{image_height})")
    else:
        feedback_parts.append(f"❌ Resolution too low ({image_width}x{image_height})")
    
    # ================================================================
    # CRITERION 4: Non-trivial image content (5 points)
    # ================================================================
    color_diversity = result.get('color_diversity', 0)
    file_size_kb = result.get('output_size_bytes', 0) / 1024
    
    if color_diversity >= 1000 or file_size_kb >= 100:
        score += 5
        feedback_parts.append(f"✅ Image has complex content ({color_diversity} colors, {file_size_kb:.1f}KB)")
    elif color_diversity >= 100 or file_size_kb >= min_file_size_kb:
        score += 3
        feedback_parts.append(f"⚠️ Image has moderate content ({color_diversity} colors)")
    else:
        feedback_parts.append(f"❌ Image appears trivial ({color_diversity} colors)")
    
    # ================================================================
    # CRITERION 5: File created during task execution (15 points) - ANTI-GAMING
    # ================================================================
    file_created_during_task = result.get('file_created_during_task', False)
    task_start = result.get('task_start', 0)
    output_mtime = result.get('output_mtime', 0)
    
    if file_created_during_task:
        score += 15
        feedback_parts.append("✅ File created during task execution")
    else:
        feedback_parts.append("❌ GAMING DETECTED: File predates task start")
        result_details['gaming_detected'] = True
    
    # ================================================================
    # VLM VERIFICATION ON OUTPUT IMAGE (45 points total)
    # ================================================================
    vlm_score = 0
    vlm_content_result = None
    
    if query_vlm and output_exists:
        # Copy the output image from container
        temp_image = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env(expected_output_path, temp_image.name)
            
            # Check if file is valid
            if os.path.exists(temp_image.name) and os.path.getsize(temp_image.name) > 0:
                # Query VLM on the output image content
                vlm_content_result = query_vlm(
                    prompt=CONTENT_VERIFICATION_PROMPT,
                    image=temp_image.name
                )
                result_details['vlm_content_result'] = vlm_content_result
                
                if vlm_content_result and vlm_content_result.get('success'):
                    parsed = vlm_content_result.get('parsed', {})
                    
                    # CRITERION 6: Shows Giza pyramids (25 points)
                    shows_giza = parsed.get('shows_giza_pyramids', False)
                    if shows_giza:
                        vlm_score += 25
                        feedback_parts.append("✅ VLM: Image shows Giza pyramids")
                    else:
                        feedback_parts.append("❌ VLM: Image does NOT show Giza pyramids")
                    
                    # CRITERION 7: All three pyramids visible (10 points)
                    pyramid_count = parsed.get('pyramid_count', 0)
                    if pyramid_count >= 3:
                        vlm_score += 10
                        feedback_parts.append(f"✅ VLM: All 3 major pyramids visible")
                    elif pyramid_count >= 2:
                        vlm_score += 5
                        feedback_parts.append(f"⚠️ VLM: Only {pyramid_count} pyramids visible")
                    elif pyramid_count >= 1:
                        vlm_score += 2
                        feedback_parts.append(f"⚠️ VLM: Only {pyramid_count} pyramid visible")
                    else:
                        feedback_parts.append("❌ VLM: No pyramids detected")
                    
                    # CRITERION 8: Aerial/top-down view (10 points)
                    view_type = parsed.get('view_type', 'unknown')
                    if view_type == 'top-down':
                        vlm_score += 10
                        feedback_parts.append("✅ VLM: Top-down aerial view")
                    elif view_type == 'angled':
                        vlm_score += 7
                        feedback_parts.append("⚠️ VLM: Angled aerial view (not top-down)")
                    else:
                        feedback_parts.append(f"❌ VLM: View type is {view_type}")
                    
                    # Add confidence info
                    confidence = parsed.get('confidence', 'unknown')
                    reasoning = parsed.get('reasoning', '')
                    result_details['vlm_confidence'] = confidence
                    result_details['vlm_reasoning'] = reasoning
                else:
                    feedback_parts.append("⚠️ VLM content analysis failed")
        except Exception as e:
            logger.warning(f"Failed to copy/analyze output image: {e}")
            feedback_parts.append(f"⚠️ Could not analyze output image: {e}")
        finally:
            if os.path.exists(temp_image.name):
                os.unlink(temp_image.name)
    else:
        feedback_parts.append("⚠️ VLM not available for content verification")
    
    score += vlm_score
    
    # ================================================================
    # TRAJECTORY VERIFICATION (bonus confidence, not scored separately)
    # ================================================================
    if query_vlm and traj:
        try:
            # Import trajectory utilities
            from gym_anything.vlm import sample_trajectory_frames
            
            # Sample frames from trajectory
            traj_frames = sample_trajectory_frames(traj, n=5)
            
            if traj_frames and len(traj_frames) > 0:
                traj_result = query_vlm(
                    prompt=TRAJECTORY_PROCESS_PROMPT,
                    images=traj_frames
                )
                result_details['trajectory_vlm_result'] = traj_result
                
                if traj_result and traj_result.get('success'):
                    parsed = traj_result.get('parsed', {})
                    
                    if parsed.get('giza_reached', False):
                        feedback_parts.append("✅ Trajectory: Agent navigated to Giza")
                    if parsed.get('meaningful_work', False):
                        feedback_parts.append("✅ Trajectory: Meaningful work observed")
                    
                    result_details['trajectory_stages'] = parsed.get('stages_observed', [])
        except ImportError:
            logger.warning("Could not import trajectory utilities")
        except Exception as e:
            logger.warning(f"Trajectory verification failed: {e}")
    
    # ================================================================
    # FINAL SCORING AND PASS/FAIL DETERMINATION
    # ================================================================
    max_score = 100
    pass_threshold = 60
    
    # Key criteria for passing
    key_criteria_met = (
        output_exists and 
        file_created_during_task and
        (vlm_content_result is None or 
         (vlm_content_result.get('success') and 
          vlm_content_result.get('parsed', {}).get('shows_giza_pyramids', False)))
    )
    
    passed = score >= pass_threshold and key_criteria_met
    
    # Final feedback
    feedback = " | ".join(feedback_parts)
    feedback += f" | Final score: {score}/{max_score}"
    
    result_details['score_breakdown'] = {
        'file_exists': 15 if output_exists else 0,
        'valid_format': 10 if image_format == 'PNG' else (5 if image_format in ['JPEG', 'JPG'] else 0),
        'resolution': 10 if (image_width >= min_width and image_height >= min_height) else 0,
        'non_trivial': 5 if color_diversity >= 1000 else 0,
        'created_during_task': 15 if file_created_during_task else 0,
        'vlm_content': vlm_score
    }
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": result_details
    }