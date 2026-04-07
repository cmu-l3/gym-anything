#!/usr/bin/env python3
"""
Verifier for GPX Track Import and Terrain Visualization task.

VERIFICATION STRATEGY:
1. Output file exists at correct path (15 points)
2. File size indicates real content (10 points)
3. Image dimensions meet minimum (10 points)
4. File created during task - anti-gaming (10 points)
5. Google Earth was running (10 points)
6. VLM: Track/path visible in image (20 points)
7. VLM: Correct geographic location - Zion/canyon (15 points)
8. VLM: 3D terrain perspective (10 points)

Pass threshold: 60 points with output file created during task
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_gpx_track_import(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that GPX track was imported and visualization was exported.
    
    Uses multiple independent signals to prevent gaming:
    - File-based checks (existence, size, timestamp)
    - VLM trajectory verification (proves actual work was done)
    
    Args:
        traj: Trajectory data with frames, steps, episode_dir
        env_info: Environment info with copy_from_env, query_vlm
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
            "feedback": "❌ Copy function not available"
        }
    
    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/Documents/angels_landing_visualization.jpg')
    min_file_size_kb = metadata.get('min_file_size_kb', 100)
    expected_min_width = metadata.get('expected_min_width', 1920)
    expected_min_height = metadata.get('expected_min_height', 1080)
    
    feedback_parts = []
    score = 0
    max_score = 100
    details = {}
    
    # ================================================================
    # Copy result JSON from container
    # ================================================================
    result = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        details['result_loaded'] = True
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
        details['result_error'] = str(e)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Failed to read task result: {e}",
            "details": details
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    output_info = result.get('output_file', {})
    ge_info = result.get('google_earth', {})
    evidence = result.get('evidence', {})
    
    # ================================================================
    # CRITERION 1: Output file exists (15 points)
    # ================================================================
    output_exists = output_info.get('exists', False)
    
    if output_exists:
        score += 15
        feedback_parts.append("✅ Output image file exists")
        details['file_exists'] = True
    else:
        feedback_parts.append("❌ Output image file NOT found")
        details['file_exists'] = False
        # Early termination - can't verify much without the file
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts) + " - No output file created",
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: File size indicates real content (10 points)
    # ================================================================
    file_size_bytes = output_info.get('size_bytes', 0)
    file_size_kb = file_size_bytes / 1024
    details['file_size_kb'] = file_size_kb
    
    if file_size_kb >= 500:  # Large, detailed image
        score += 10
        feedback_parts.append(f"✅ Good file size ({file_size_kb:.1f}KB)")
    elif file_size_kb >= min_file_size_kb:
        score += 7
        feedback_parts.append(f"✅ Acceptable file size ({file_size_kb:.1f}KB)")
    elif file_size_kb >= 50:
        score += 4
        feedback_parts.append(f"⚠️ Small file size ({file_size_kb:.1f}KB)")
    else:
        feedback_parts.append(f"❌ File too small ({file_size_kb:.1f}KB)")
    
    # ================================================================
    # CRITERION 3: Image dimensions meet minimum (10 points)
    # ================================================================
    image_width = output_info.get('width', 0)
    image_height = output_info.get('height', 0)
    details['dimensions'] = f"{image_width}x{image_height}"
    
    width_ok = image_width >= expected_min_width
    height_ok = image_height >= expected_min_height
    
    if width_ok and height_ok:
        score += 10
        feedback_parts.append(f"✅ Image dimensions ({image_width}x{image_height})")
    elif image_width >= 1280 and image_height >= 720:
        score += 5
        feedback_parts.append(f"⚠️ Image dimensions below target ({image_width}x{image_height})")
    elif image_width > 0 and image_height > 0:
        score += 2
        feedback_parts.append(f"⚠️ Small image dimensions ({image_width}x{image_height})")
    else:
        feedback_parts.append("❌ Could not determine image dimensions")
    
    # ================================================================
    # CRITERION 4: File created during task - ANTI-GAMING (10 points)
    # ================================================================
    file_created_during_task = output_info.get('created_during_task', False)
    task_start = result.get('task_start_time', 0)
    file_mtime = output_info.get('mtime', 0)
    details['file_created_during_task'] = file_created_during_task
    details['task_start'] = task_start
    details['file_mtime'] = file_mtime
    
    if file_created_during_task:
        score += 10
        feedback_parts.append("✅ File created during task execution")
    else:
        feedback_parts.append("❌ File NOT created during task (possible pre-staged)")
        # This is a critical anti-gaming check
        details['anti_gaming_flag'] = True
    
    # ================================================================
    # CRITERION 5: Google Earth was running (10 points)
    # ================================================================
    ge_running = ge_info.get('running', False)
    details['google_earth_running'] = ge_running
    
    if ge_running:
        score += 10
        feedback_parts.append("✅ Google Earth Pro was running")
    else:
        score += 5  # Partial - might have closed after saving
        feedback_parts.append("⚠️ Google Earth Pro not detected running")
    
    # ================================================================
    # VLM VERIFICATION (45 points total)
    # Uses trajectory frames to verify actual work was done
    # ================================================================
    
    vlm_score = 0
    vlm_details = {}
    
    if query_vlm:
        # Get final screenshot from container
        temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        final_screenshot_path = None
        
        try:
            copy_from_env("/tmp/task_final_state.png", temp_screenshot.name)
            if os.path.exists(temp_screenshot.name) and os.path.getsize(temp_screenshot.name) > 1000:
                final_screenshot_path = temp_screenshot.name
        except Exception as e:
            logger.warning(f"Could not copy final screenshot: {e}")
        
        # Also try to get the exported image itself
        temp_output = tempfile.NamedTemporaryFile(delete=False, suffix='.jpg')
        output_image_path = None
        
        try:
            copy_from_env(expected_output_path, temp_output.name)
            if os.path.exists(temp_output.name) and os.path.getsize(temp_output.name) > 1000:
                output_image_path = temp_output.name
        except Exception as e:
            logger.warning(f"Could not copy output image: {e}")
        
        # Sample trajectory frames for process verification
        trajectory_frames = []
        try:
            from gym_anything.vlm import sample_trajectory_frames
            trajectory_frames = sample_trajectory_frames(traj, n=5)
        except Exception as e:
            logger.warning(f"Could not sample trajectory frames: {e}")
        
        # ================================================================
        # VLM Check 1: Trajectory Process Verification (15 points)
        # ================================================================
        if trajectory_frames and len(trajectory_frames) >= 3:
            process_prompt = """Analyze these screenshots showing an agent working in Google Earth Pro.

The agent's task was to:
1. Import a GPX track file (Angel's Landing hiking trail)
2. View the track overlaid on 3D terrain
3. Export an image of the visualization

Look for evidence of this workflow:
- Google Earth interface visible
- File import dialog or menu
- GPS track/path line visible on terrain
- 3D tilted terrain view
- Save/export dialog

Respond in JSON:
{
    "google_earth_visible": true/false,
    "import_workflow_visible": true/false,
    "track_line_visible": true/false,
    "terrain_3d_visible": true/false,
    "meaningful_progression": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "what you see across the frames"
}"""
            
            try:
                vlm_result = query_vlm(prompt=process_prompt, images=trajectory_frames)
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    vlm_details['process_verification'] = parsed
                    
                    process_score = 0
                    if parsed.get('google_earth_visible', False):
                        process_score += 4
                    if parsed.get('import_workflow_visible', False):
                        process_score += 4
                    if parsed.get('track_line_visible', False):
                        process_score += 4
                    if parsed.get('meaningful_progression', False):
                        process_score += 3
                    
                    vlm_score += process_score
                    if process_score >= 10:
                        feedback_parts.append("✅ VLM: Workflow progression verified")
                    elif process_score >= 5:
                        feedback_parts.append("⚠️ VLM: Partial workflow evidence")
                    else:
                        feedback_parts.append("❌ VLM: Workflow not clearly visible")
            except Exception as e:
                logger.warning(f"VLM process verification failed: {e}")
                vlm_details['process_error'] = str(e)
        
        # ================================================================
        # VLM Check 2: Output Image Content (20 points)
        # ================================================================
        if output_image_path:
            content_prompt = """Analyze this exported image from Google Earth Pro.

The image should show a GPX hiking track visualization of the Angel's Landing trail in Zion National Park.

Look for:
1. GPS TRACK LINE: A colored line/path overlay (could be red, yellow, blue, purple, or other color) tracing a hiking route
2. TERRAIN: Red/orange sandstone canyon terrain characteristic of Zion National Park
3. GEOGRAPHIC FEATURES: Deep canyons, cliff formations, desert landscape

Respond in JSON:
{
    "track_line_visible": true/false,
    "track_line_color": "describe if visible",
    "canyon_terrain_visible": true/false,
    "red_rock_landscape": true/false,
    "appears_to_be_zion": true/false,
    "confidence": "low"/"medium"/"high",
    "description": "what you see in the image"
}"""
            
            try:
                vlm_result = query_vlm(prompt=content_prompt, image=output_image_path)
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    vlm_details['content_verification'] = parsed
                    
                    content_score = 0
                    if parsed.get('track_line_visible', False):
                        content_score += 10  # Critical - track must be visible
                        feedback_parts.append("✅ VLM: GPS track visible in image")
                    else:
                        feedback_parts.append("❌ VLM: GPS track NOT visible")
                    
                    if parsed.get('canyon_terrain_visible', False) or parsed.get('red_rock_landscape', False):
                        content_score += 5
                    if parsed.get('appears_to_be_zion', False):
                        content_score += 5
                    
                    vlm_score += content_score
            except Exception as e:
                logger.warning(f"VLM content verification failed: {e}")
                vlm_details['content_error'] = str(e)
        
        # ================================================================
        # VLM Check 3: 3D Perspective (10 points)
        # ================================================================
        check_image = output_image_path or final_screenshot_path
        if check_image:
            perspective_prompt = """Look at this Google Earth image.

Is the view showing 3D terrain with a tilted perspective? Look for:
- Terrain tilted to show elevation/depth (not flat top-down view)
- Visible cliff faces or canyon walls
- Horizon visible or terrain fading into distance
- Shadows indicating 3D rendering

Respond in JSON:
{
    "is_3d_tilted_view": true/false,
    "shows_elevation_depth": true/false,
    "is_flat_overhead": true/false,
    "confidence": "low"/"medium"/"high"
}"""
            
            try:
                vlm_result = query_vlm(prompt=perspective_prompt, image=check_image)
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    vlm_details['perspective_verification'] = parsed
                    
                    if parsed.get('is_3d_tilted_view', False) and not parsed.get('is_flat_overhead', True):
                        vlm_score += 10
                        feedback_parts.append("✅ VLM: 3D terrain perspective")
                    elif parsed.get('shows_elevation_depth', False):
                        vlm_score += 5
                        feedback_parts.append("⚠️ VLM: Some 3D elements visible")
                    else:
                        feedback_parts.append("❌ VLM: Flat/overhead view")
            except Exception as e:
                logger.warning(f"VLM perspective verification failed: {e}")
                vlm_details['perspective_error'] = str(e)
        
        # Cleanup temp files
        for temp_path in [temp_screenshot.name, temp_output.name]:
            try:
                if os.path.exists(temp_path):
                    os.unlink(temp_path)
            except:
                pass
    else:
        feedback_parts.append("⚠️ VLM not available - visual verification skipped")
        # Give partial credit when VLM unavailable but file checks pass
        if score >= 45:  # File-based checks largely passed
            vlm_score = 20  # Assume partial VLM success
    
    score += vlm_score
    details['vlm_score'] = vlm_score
    details['vlm_details'] = vlm_details
    
    # ================================================================
    # FINAL SCORING AND PASS/FAIL DETERMINATION
    # ================================================================
    
    # Key criteria for passing:
    # 1. Output file must exist
    # 2. File must have been created during task (anti-gaming)
    # 3. Minimum score threshold
    
    key_criteria_met = (
        output_exists and 
        file_created_during_task and
        file_size_kb >= 50
    )
    
    passed = score >= 60 and key_criteria_met
    
    # Generate summary
    if passed:
        summary = f"✅ Task PASSED ({score}/{max_score} points)"
    else:
        reasons = []
        if not output_exists:
            reasons.append("no output file")
        if not file_created_during_task:
            reasons.append("file not created during task")
        if score < 60:
            reasons.append(f"score below threshold ({score}/60)")
        summary = f"❌ Task FAILED ({score}/{max_score} points) - {', '.join(reasons)}"
    
    feedback_parts.insert(0, summary)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }