#!/usr/bin/env python3
"""
Verifier for Stonehenge Solstice Shadows task.

VERIFICATION STRATEGY:
1. Programmatic checks (from export_result.sh):
   - Output file exists and is valid PNG (10 pts)
   - File was created during task (10 pts) - anti-gaming
   - File size reasonable (implicit in validity)

2. VLM verification using TRAJECTORY frames (not just final):
   - Stonehenge monument visible (25 pts)
   - Sunlight mode evidence (20 pts)
   - Long shadows visible (20 pts)
   - 3D tilted perspective (15 pts)

Pass threshold: 65 points AND screenshot file exists AND stonehenge visible
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any, Optional, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_stonehenge_solstice_shadows(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any]
) -> Dict[str, Any]:
    """
    Verify the Stonehenge solstice shadows task completion.
    
    Uses MULTIPLE INDEPENDENT SIGNALS:
    1. File-based verification (from container)
    2. VLM trajectory verification (framework-captured, tamper-proof)
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
    scoring = metadata.get('scoring', {})
    
    score = 0
    max_score = 100
    feedback_parts = []
    result_details = {}
    
    # ================================================================
    # PART 1: Programmatic File Verification
    # ================================================================
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        result_details['export_result'] = result
    except Exception as e:
        logger.warning(f"Failed to read task result: {e}")
        result = {}
        result_details['export_error'] = str(e)
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # Extract output info
    output_info = result.get('output', {})
    output_exists = output_info.get('exists', False)
    output_size = output_info.get('size_bytes', 0)
    created_during_task = output_info.get('created_during_task', False)
    image_valid = output_info.get('image_valid', False)
    image_width = output_info.get('image_width', 0)
    image_height = output_info.get('image_height', 0)
    image_format = output_info.get('image_format', 'unknown')
    
    # CRITERION 1: Screenshot file exists (10 points)
    if output_exists and image_valid:
        score += scoring.get('file_exists', 10)
        feedback_parts.append(f"✅ Screenshot exists ({image_format}, {output_size} bytes)")
    elif output_exists:
        score += 5
        feedback_parts.append(f"⚠️ File exists but may be invalid (format: {image_format})")
    else:
        feedback_parts.append("❌ Screenshot file NOT found at ~/Pictures/stonehenge_solstice.png")
        # Cannot continue without output file
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": result_details
        }
    
    # CRITERION 2: File created during task (10 points) - ANTI-GAMING
    if created_during_task:
        score += scoring.get('file_valid', 10)
        feedback_parts.append("✅ File created during task execution")
    else:
        feedback_parts.append("❌ File NOT created during task (possible gaming)")
        result_details['anti_gaming_failed'] = True
        # This is a serious issue - return failing score
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts) + " | Anti-gaming check failed",
            "details": result_details
        }
    
    # Check image dimensions are reasonable
    if image_width >= 800 and image_height >= 600:
        feedback_parts.append(f"✅ Image dimensions OK ({image_width}x{image_height})")
    else:
        feedback_parts.append(f"⚠️ Image small ({image_width}x{image_height})")
    
    # ================================================================
    # PART 2: VLM Verification using Trajectory Frames
    # ================================================================
    
    if not query_vlm:
        feedback_parts.append("⚠️ VLM not available - using programmatic score only")
        # Give partial credit based on programmatic checks alone
        return {
            "passed": score >= 20,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": result_details
        }
    
    # Get trajectory frames (captured by framework - tamper-proof)
    trajectory_frames = _get_trajectory_frames(traj, n_samples=5)
    
    # Get the output image from container
    output_image_path = None
    temp_output = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    try:
        copy_from_env("/tmp/task_evidence/output_copy.png", temp_output.name)
        if os.path.exists(temp_output.name) and os.path.getsize(temp_output.name) > 1000:
            output_image_path = temp_output.name
    except Exception as e:
        logger.warning(f"Could not copy output image: {e}")
        # Try the original path
        try:
            copy_from_env("/home/ga/Pictures/stonehenge_solstice.png", temp_output.name)
            if os.path.exists(temp_output.name) and os.path.getsize(temp_output.name) > 1000:
                output_image_path = temp_output.name
        except Exception as e2:
            logger.warning(f"Could not copy from original path either: {e2}")
    
    # VLM verification on trajectory + output
    vlm_score, vlm_feedback, vlm_details = _verify_with_vlm(
        query_vlm=query_vlm,
        trajectory_frames=trajectory_frames,
        output_image_path=output_image_path,
        scoring=scoring
    )
    
    score += vlm_score
    feedback_parts.extend(vlm_feedback)
    result_details['vlm_verification'] = vlm_details
    
    # Cleanup temp file
    if os.path.exists(temp_output.name):
        os.unlink(temp_output.name)
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    
    # Key criteria: file exists + created during task + stonehenge visible
    stonehenge_visible = vlm_details.get('stonehenge_visible', False)
    key_criteria_met = output_exists and created_during_task and stonehenge_visible
    
    passed = score >= 65 and key_criteria_met
    
    result_details['final_score'] = score
    result_details['key_criteria_met'] = key_criteria_met
    result_details['stonehenge_visible'] = stonehenge_visible
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result_details
    }


def _get_trajectory_frames(traj: Dict[str, Any], n_samples: int = 5) -> List[str]:
    """
    Extract trajectory frame paths from the trajectory data.
    Returns list of file paths to trajectory screenshots.
    """
    frames = []
    
    # Try different possible locations for trajectory frames
    episode_dir = traj.get('episode_dir', '')
    
    # Method 1: Direct frames list
    if 'frames' in traj and isinstance(traj['frames'], list):
        all_frames = traj['frames']
        if len(all_frames) > 0:
            # Sample evenly across trajectory
            step = max(1, len(all_frames) // n_samples)
            frames = [all_frames[i] for i in range(0, len(all_frames), step)][:n_samples]
    
    # Method 2: Check episode directory for screenshots
    if not frames and episode_dir and os.path.isdir(episode_dir):
        import glob
        pattern = os.path.join(episode_dir, "*.png")
        all_files = sorted(glob.glob(pattern))
        if all_files:
            step = max(1, len(all_files) // n_samples)
            frames = [all_files[i] for i in range(0, len(all_files), step)][:n_samples]
    
    # Method 3: Steps with screenshots
    if not frames and 'steps' in traj:
        for step in traj.get('steps', []):
            if 'screenshot' in step and step['screenshot']:
                frames.append(step['screenshot'])
            if len(frames) >= n_samples:
                break
    
    return frames


def _verify_with_vlm(
    query_vlm,
    trajectory_frames: List[str],
    output_image_path: Optional[str],
    scoring: Dict[str, int]
) -> tuple:
    """
    Perform VLM verification on trajectory frames and output image.
    
    Returns: (score, feedback_list, details_dict)
    """
    vlm_score = 0
    feedback = []
    details = {
        'stonehenge_visible': False,
        'sunlight_active': False,
        'long_shadows': False,
        'perspective_3d': False
    }
    
    # ================================================================
    # VLM CHECK 1: Trajectory Process Verification
    # Uses multiple frames to verify actual work was done
    # ================================================================
    
    if trajectory_frames:
        process_prompt = """You are analyzing a sequence of screenshots from an agent using Google Earth Pro.

The TASK was to:
1. Navigate to Stonehenge, UK
2. Enable sunlight simulation
3. Set date to June 21 (summer solstice)
4. Set time to early morning (~5 AM)
5. Tilt view to show shadows
6. Save a screenshot

Examine these trajectory frames (in chronological order) and determine:
1. Was Google Earth Pro being used?
2. Did the agent navigate to a location (search/fly-to)?
3. Is there evidence of sunlight mode being enabled (sun icon, time slider)?
4. Was the view manipulated (zooming, tilting)?

Respond in JSON format:
{
    "google_earth_used": true/false,
    "navigation_performed": true/false,
    "sunlight_mode_evidence": true/false,
    "view_manipulation": true/false,
    "workflow_confidence": "low"/"medium"/"high",
    "observations": "brief description of what you observe across frames"
}
"""
        
        try:
            # Query VLM with trajectory frames
            traj_result = query_vlm(
                prompt=process_prompt,
                images=trajectory_frames[:5]  # Use up to 5 frames
            )
            
            if traj_result.get('success'):
                parsed = traj_result.get('parsed', {})
                details['trajectory_analysis'] = parsed
                
                # Small bonus for clear workflow evidence
                if parsed.get('google_earth_used') and parsed.get('navigation_performed'):
                    if parsed.get('workflow_confidence') == 'high':
                        vlm_score += 5
                        feedback.append("✅ Clear workflow in trajectory")
        except Exception as e:
            logger.warning(f"Trajectory VLM check failed: {e}")
    
    # ================================================================
    # VLM CHECK 2: Output Image Content Verification
    # This is the main VLM verification for scoring
    # ================================================================
    
    if output_image_path and os.path.exists(output_image_path):
        content_prompt = """You are verifying a screenshot saved from Google Earth Pro.

The TASK was to capture Stonehenge during simulated summer solstice sunrise.

Examine this screenshot and determine:

1. STONEHENGE_VISIBLE: Does this show Stonehenge - the famous prehistoric stone circle monument in Wiltshire, England? Look for the distinctive arrangement of large standing stones in a circular pattern. Answer true/false.

2. SUNLIGHT_ACTIVE: Is there evidence that Google Earth's sunlight simulation is active? Look for:
   - A time slider at the top of the screen
   - Sun icon highlighted in toolbar
   - Visible shadows cast by objects/terrain
   Answer true/false.

3. LONG_SHADOWS: Are there visible long shadows (as would occur during early morning sunrise)? Long shadows extend significantly from objects rather than being short/directly below. Answer true/false.

4. TILTED_3D_VIEW: Is this a tilted 3D perspective view showing the ground/terrain from an angle, rather than a flat top-down satellite view? A tilted view shows horizon or terrain depth. Answer true/false.

5. IMAGE_QUALITY: Is this a genuine Google Earth screenshot (not an error screen, blank image, or unrelated content)? Answer true/false.

Respond in JSON format:
{
    "stonehenge_visible": true/false,
    "sunlight_active": true/false,
    "long_shadows": true/false,
    "tilted_3d_view": true/false,
    "image_quality_ok": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation of what you see"
}
"""
        
        try:
            content_result = query_vlm(
                prompt=content_prompt,
                image=output_image_path
            )
            
            if content_result.get('success'):
                parsed = content_result.get('parsed', {})
                details['content_analysis'] = parsed
                confidence = parsed.get('confidence', 'low')
                
                # Apply confidence multiplier
                conf_multiplier = {'high': 1.0, 'medium': 0.9, 'low': 0.75}.get(confidence, 0.75)
                
                # CRITERION 3: Stonehenge visible (25 points)
                if parsed.get('stonehenge_visible'):
                    points = int(scoring.get('stonehenge_visible', 25) * conf_multiplier)
                    vlm_score += points
                    details['stonehenge_visible'] = True
                    feedback.append(f"✅ Stonehenge monument visible ({confidence} confidence)")
                else:
                    feedback.append("❌ Stonehenge not identified in screenshot")
                
                # CRITERION 4: Sunlight mode active (20 points)
                if parsed.get('sunlight_active'):
                    points = int(scoring.get('sunlight_active', 20) * conf_multiplier)
                    vlm_score += points
                    details['sunlight_active'] = True
                    feedback.append("✅ Sunlight simulation appears active")
                else:
                    feedback.append("⚠️ Sunlight mode not clearly visible")
                
                # CRITERION 5: Long shadows visible (20 points)
                if parsed.get('long_shadows'):
                    points = int(scoring.get('long_shadows', 20) * conf_multiplier)
                    vlm_score += points
                    details['long_shadows'] = True
                    feedback.append("✅ Long morning shadows visible")
                else:
                    feedback.append("⚠️ Long shadows not clearly visible")
                
                # CRITERION 6: 3D tilted perspective (15 points)
                if parsed.get('tilted_3d_view'):
                    points = int(scoring.get('perspective_3d', 15) * conf_multiplier)
                    vlm_score += points
                    details['perspective_3d'] = True
                    feedback.append("✅ 3D tilted perspective view")
                else:
                    # Partial credit for top-down view (still valid screenshot)
                    vlm_score += 5
                    feedback.append("⚠️ Top-down view (3D tilt preferred)")
                
                # Check image quality
                if not parsed.get('image_quality_ok', True):
                    feedback.append("⚠️ Image quality concerns noted")
                    
            else:
                error = content_result.get('error', 'Unknown VLM error')
                feedback.append(f"⚠️ VLM content check failed: {error}")
                details['vlm_error'] = error
                
        except Exception as e:
            logger.error(f"VLM content verification failed: {e}")
            feedback.append(f"⚠️ VLM verification error: {str(e)}")
            details['vlm_exception'] = str(e)
    else:
        feedback.append("⚠️ Output image not available for VLM verification")
    
    return vlm_score, feedback, details