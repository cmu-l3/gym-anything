#!/usr/bin/env python3
"""
Verifier for Hawaii Elevation Profile task.

VERIFICATION STRATEGY:
Uses TRAJECTORY FRAMES (not just final screenshot) for VLM verification,
combined with programmatic file checks.

SCORING (100 points total):
1. Screenshot file exists and valid (10 points)
2. File created during task - anti-gaming (10 points)
3. File size indicates real screenshot (5 points)
4. Google Earth was running (5 points)
5. VLM: Hawaii visible in trajectory (15 points)
6. VLM: Path/line visible on map (15 points)
7. VLM: Elevation profile panel visible (20 points)
8. VLM: Profile shows volcano shape (15 points)
9. Path saved to My Places (5 points)

Pass threshold: 60 points with elevation profile visible
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any, List, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_hawaii_elevation_profile(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the Hawaii elevation profile task completion.
    
    Uses MULTIPLE INDEPENDENT SIGNALS to prevent gaming:
    - Programmatic checks on files and timestamps
    - VLM verification on TRAJECTORY frames (not just final)
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
    expected_output_path = metadata.get('expected_output_path', '/home/ga/hawaii_elevation_profile.png')
    min_file_size_kb = metadata.get('min_file_size_kb', 100)
    
    feedback_parts = []
    score = 0
    details = {}
    
    # ================================================================
    # STEP 1: Copy and parse result JSON from container
    # ================================================================
    result_data = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
        details['result_data'] = result_data
    except Exception as e:
        logger.warning(f"Could not read task result JSON: {e}")
        feedback_parts.append("⚠️ Could not read task result data")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # CRITERION 1: Screenshot file exists and is valid (10 points)
    # ================================================================
    output_exists = result_data.get('output_exists', False)
    image_format = result_data.get('image_format', 'none')
    
    if output_exists and image_format.upper() in ['PNG', 'JPEG', 'JPG', 'BMP', 'TIFF']:
        score += 10
        feedback_parts.append(f"✅ Screenshot file exists ({image_format})")
        details['file_exists'] = True
    elif output_exists:
        score += 5
        feedback_parts.append(f"⚠️ Screenshot exists but format unclear ({image_format})")
        details['file_exists'] = True
    else:
        feedback_parts.append("❌ Screenshot file NOT found at expected path")
        details['file_exists'] = False
    
    # ================================================================
    # CRITERION 2: File created during task - ANTI-GAMING (10 points)
    # ================================================================
    file_created_during_task = result_data.get('file_created_during_task', False)
    
    if file_created_during_task:
        score += 10
        feedback_parts.append("✅ File created during task execution")
        details['created_during_task'] = True
    else:
        if output_exists:
            feedback_parts.append("⚠️ File existed before task or timestamp unclear")
        details['created_during_task'] = False
    
    # ================================================================
    # CRITERION 3: File size indicates real screenshot (5 points)
    # ================================================================
    output_size_kb = result_data.get('output_size_bytes', 0) / 1024
    
    if output_size_kb >= min_file_size_kb:
        score += 5
        feedback_parts.append(f"✅ File size adequate ({output_size_kb:.1f} KB)")
        details['file_size_ok'] = True
    elif output_size_kb >= 50:
        score += 3
        feedback_parts.append(f"⚠️ File size marginal ({output_size_kb:.1f} KB)")
        details['file_size_ok'] = True
    elif output_size_kb > 0:
        score += 1
        feedback_parts.append(f"⚠️ File size small ({output_size_kb:.1f} KB)")
        details['file_size_ok'] = False
    else:
        details['file_size_ok'] = False
    
    # ================================================================
    # CRITERION 4: Google Earth was running (5 points)
    # ================================================================
    ge_running = result_data.get('google_earth_running', False)
    
    if ge_running:
        score += 5
        feedback_parts.append("✅ Google Earth was running")
        details['app_running'] = True
    else:
        feedback_parts.append("⚠️ Google Earth not detected as running")
        details['app_running'] = False
    
    # ================================================================
    # CRITERION 5-8: VLM Verification using TRAJECTORY FRAMES
    # ================================================================
    vlm_score = 0
    vlm_details = {}
    
    if query_vlm:
        # Get trajectory frames - CRITICAL: use multiple frames, not just final
        trajectory_frames = _get_trajectory_frames(traj, n_samples=5)
        final_screenshot = _get_final_screenshot(traj)
        
        # Also try to get the saved screenshot from container
        saved_screenshot = None
        if output_exists:
            temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            try:
                copy_from_env(expected_output_path, temp_screenshot.name)
                if os.path.exists(temp_screenshot.name) and os.path.getsize(temp_screenshot.name) > 1000:
                    saved_screenshot = temp_screenshot.name
            except Exception as e:
                logger.warning(f"Could not copy saved screenshot: {e}")
            # Don't delete yet - we'll use it for VLM
        
        # Combine trajectory frames with saved/final screenshot
        all_images = trajectory_frames.copy() if trajectory_frames else []
        if saved_screenshot:
            all_images.append(saved_screenshot)
        elif final_screenshot:
            all_images.append(final_screenshot)
        
        if all_images:
            # VLM Query 1: Process verification using trajectory frames
            trajectory_result = _vlm_verify_trajectory(query_vlm, all_images)
            vlm_details['trajectory_verification'] = trajectory_result
            
            if trajectory_result:
                # Criterion 5: Hawaii visible (15 points)
                if trajectory_result.get('hawaii_visible', False):
                    vlm_score += 15
                    feedback_parts.append("✅ Hawaii visible in trajectory")
                else:
                    feedback_parts.append("❌ Hawaii not detected in trajectory")
                
                # Criterion 6: Path/line visible (15 points)
                if trajectory_result.get('path_visible', False):
                    vlm_score += 15
                    feedback_parts.append("✅ Path/measurement line visible")
                else:
                    feedback_parts.append("❌ Path/line not detected")
                
                # Criterion 7: Elevation profile panel visible (20 points)
                if trajectory_result.get('elevation_profile_visible', False):
                    vlm_score += 20
                    feedback_parts.append("✅ Elevation profile panel visible")
                else:
                    feedback_parts.append("❌ Elevation profile not detected")
                
                # Criterion 8: Profile shows volcano shape (15 points)
                if trajectory_result.get('volcano_shape_visible', False):
                    vlm_score += 15
                    feedback_parts.append("✅ Elevation profile shows volcano shape")
                elif trajectory_result.get('elevation_profile_visible', False):
                    # Partial credit if profile visible but shape not confirmed
                    vlm_score += 7
                    feedback_parts.append("⚠️ Profile visible but shape not confirmed")
                else:
                    feedback_parts.append("❌ Volcano profile shape not detected")
        else:
            feedback_parts.append("⚠️ No images available for VLM verification")
        
        # Cleanup temp screenshot
        if saved_screenshot and os.path.exists(saved_screenshot):
            try:
                os.unlink(saved_screenshot)
            except:
                pass
    else:
        feedback_parts.append("⚠️ VLM not available - visual verification skipped")
    
    score += vlm_score
    details['vlm_score'] = vlm_score
    details['vlm_details'] = vlm_details
    
    # ================================================================
    # CRITERION 9: Path saved to My Places (5 points)
    # ================================================================
    hawaii_path_saved = result_data.get('hawaii_path_saved', False)
    
    if hawaii_path_saved:
        score += 5
        feedback_parts.append("✅ Hawaii path saved to My Places")
        details['path_saved'] = True
    else:
        feedback_parts.append("⚠️ Path not found in My Places")
        details['path_saved'] = False
    
    # ================================================================
    # DETERMINE PASS/FAIL
    # ================================================================
    # Must have at least 60 points AND elevation profile must be visible
    elevation_profile_detected = vlm_details.get('trajectory_verification', {}).get('elevation_profile_visible', False)
    
    passed = score >= 60 and elevation_profile_detected
    
    # Add summary
    if passed:
        feedback_parts.insert(0, f"✅ PASSED (Score: {score}/100)")
    else:
        if not elevation_profile_detected:
            feedback_parts.insert(0, f"❌ FAILED - Elevation profile not detected (Score: {score}/100)")
        else:
            feedback_parts.insert(0, f"❌ FAILED - Score below threshold (Score: {score}/100)")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }


def _get_trajectory_frames(traj: Dict[str, Any], n_samples: int = 5) -> List[str]:
    """
    Extract trajectory frame paths, sampling across the episode.
    
    Returns list of file paths to trajectory screenshots.
    """
    frames = []
    
    try:
        # Try to get frames from trajectory data
        if 'frames' in traj and traj['frames']:
            all_frames = traj['frames']
            if len(all_frames) <= n_samples:
                frames = all_frames
            else:
                # Sample evenly across trajectory
                step = len(all_frames) // n_samples
                frames = [all_frames[i * step] for i in range(n_samples)]
                # Always include the last frame
                if all_frames[-1] not in frames:
                    frames.append(all_frames[-1])
        
        # Alternative: check episode_dir for screenshot files
        elif 'episode_dir' in traj and traj['episode_dir']:
            episode_dir = traj['episode_dir']
            if os.path.isdir(episode_dir):
                # Find screenshot files
                import glob
                screenshot_files = sorted(glob.glob(os.path.join(episode_dir, "*.png")))
                if screenshot_files:
                    if len(screenshot_files) <= n_samples:
                        frames = screenshot_files
                    else:
                        step = len(screenshot_files) // n_samples
                        frames = [screenshot_files[i * step] for i in range(n_samples)]
                        if screenshot_files[-1] not in frames:
                            frames.append(screenshot_files[-1])
    except Exception as e:
        logger.warning(f"Error getting trajectory frames: {e}")
    
    # Filter to only existing files
    frames = [f for f in frames if f and os.path.exists(f)]
    
    return frames


def _get_final_screenshot(traj: Dict[str, Any]) -> Optional[str]:
    """Get the final screenshot from trajectory."""
    try:
        if 'frames' in traj and traj['frames']:
            final = traj['frames'][-1]
            if os.path.exists(final):
                return final
        
        if 'episode_dir' in traj and traj['episode_dir']:
            episode_dir = traj['episode_dir']
            if os.path.isdir(episode_dir):
                import glob
                screenshots = sorted(glob.glob(os.path.join(episode_dir, "*.png")))
                if screenshots:
                    return screenshots[-1]
    except Exception as e:
        logger.warning(f"Error getting final screenshot: {e}")
    
    return None


def _vlm_verify_trajectory(query_vlm, images: List[str]) -> Dict[str, Any]:
    """
    Use VLM to verify the task completion using trajectory images.
    
    This checks for workflow progression across multiple frames.
    """
    
    if not query_vlm or not images:
        return {}
    
    # Filter to valid images
    valid_images = [img for img in images if img and os.path.exists(img)]
    if not valid_images:
        return {}
    
    prompt = """You are verifying if an agent completed a Hawaii elevation profile task in Google Earth.

The task was to:
1. Navigate to the Big Island of Hawaii
2. Draw a path from Hilo (east coast) across Mauna Kea to Kailua-Kona (west coast)
3. Display the elevation profile showing the volcanic shield shape
4. Save a screenshot

You are looking at multiple screenshots from the agent's work session (in chronological order).

Analyze ALL images and determine:

1. HAWAII_VISIBLE: Is the Big Island of Hawaii visible in ANY of the images? 
   Look for: The distinctive island shape, Hawaiian coastline, or Hawaiian place names (Hilo, Kona, Mauna Kea)

2. PATH_VISIBLE: Is there a measurement path/line visible crossing the island in ANY image?
   Look for: A yellow or colored line drawn across Hawaii, ruler tool indicators, path markers

3. ELEVATION_PROFILE_VISIBLE: Is an elevation profile panel/window visible in ANY image?
   Look for: A chart/graph showing elevation, a profile window with terrain data, x-y plot showing height changes

4. VOLCANO_SHAPE_VISIBLE: Does the elevation profile show the characteristic shield volcano shape?
   Look for: A profile rising from low elevation (~0 ft at sea level) to a peak (~10,000-14,000 ft) and descending back to low elevation
   This should look like a broad dome or rounded mountain shape

Respond in JSON format:
{
    "hawaii_visible": true/false,
    "path_visible": true/false,
    "elevation_profile_visible": true/false,
    "volcano_shape_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see across the images"
}
"""
    
    try:
        result = query_vlm(prompt=prompt, images=valid_images)
        
        if result.get('success'):
            parsed = result.get('parsed', {})
            return {
                'hawaii_visible': parsed.get('hawaii_visible', False),
                'path_visible': parsed.get('path_visible', False),
                'elevation_profile_visible': parsed.get('elevation_profile_visible', False),
                'volcano_shape_visible': parsed.get('volcano_shape_visible', False),
                'confidence': parsed.get('confidence', 'low'),
                'observations': parsed.get('observations', ''),
                'vlm_success': True
            }
        else:
            logger.warning(f"VLM query failed: {result.get('error', 'unknown')}")
            return {'vlm_success': False, 'error': result.get('error', 'unknown')}
            
    except Exception as e:
        logger.warning(f"VLM verification exception: {e}")
        return {'vlm_success': False, 'error': str(e)}