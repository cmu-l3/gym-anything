#!/usr/bin/env python3
"""
Verifier for trade_route_distance task.

TASK: Create a multi-point measured path connecting five Mediterranean port cities
      (Alexandria → Heraklion → Piraeus → Ostia → Carthage) and save a screenshot
      showing the path and distance measurement.

VERIFICATION STRATEGY (Multi-Signal, Anti-Gaming):

1. FILE EXISTS & VALID (20 points)
   - Screenshot file exists at expected path
   - File is valid image with reasonable dimensions

2. TIMESTAMP ANTI-GAMING (15 points)
   - File was created/modified DURING the task
   - Prevents pre-creation of result files

3. FILE SIZE REASONABLE (10 points)
   - File size indicates actual content, not empty/minimal

4. GOOGLE EARTH WAS RUNNING (10 points)
   - Application was active during task

5. VLM TRAJECTORY VERIFICATION (25 points)
   - Multiple trajectory frames show progression
   - Agent navigated, used ruler tool, created path

6. VLM FINAL SCREENSHOT VERIFICATION (20 points)
   - Mediterranean region visible
   - Multi-point path overlay visible
   - Distance measurement displayed

Pass threshold: 60 points with (file exists + created during task + visual verification)
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_trade_route_distance(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that the Mediterranean trade route measurement task was completed.
    
    Uses MULTIPLE INDEPENDENT SIGNALS to prevent gaming.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }
    
    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/trade_route_measurement.png')
    min_file_size_kb = metadata.get('min_file_size_kb', 50)
    
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
        details['result_json'] = result
    except Exception as e:
        logger.warning(f"Could not read task result JSON: {e}")
        details['result_json_error'] = str(e)
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # CRITERION 1: Output file exists and is valid (20 points)
    # ================================================================
    output_info = result.get('output_file', {})
    output_exists = output_info.get('exists', False)
    image_valid = output_info.get('image_valid', False)
    image_width = output_info.get('image_width', 0)
    image_height = output_info.get('image_height', 0)
    image_format = output_info.get('image_format', 'unknown')
    
    if output_exists and image_valid:
        if image_width >= 800 and image_height >= 600:
            score += 20
            feedback_parts.append(f"✅ Output file exists ({image_width}x{image_height} {image_format})")
        else:
            score += 10
            feedback_parts.append(f"⚠️ Output file exists but small ({image_width}x{image_height})")
    elif output_exists:
        score += 5
        feedback_parts.append(f"⚠️ Output file exists but not valid image")
    else:
        feedback_parts.append("❌ Output file NOT found")
        # Continue checking other criteria even if file missing
    
    details['file_exists'] = output_exists
    details['image_valid'] = image_valid
    details['image_dimensions'] = f"{image_width}x{image_height}"
    
    # ================================================================
    # CRITERION 2: Timestamp anti-gaming check (15 points)
    # ================================================================
    created_during_task = output_info.get('created_during_task', False)
    newly_created = output_info.get('newly_created', False)
    file_modified = output_info.get('modified', False)
    
    if newly_created:
        score += 15
        feedback_parts.append("✅ File newly created during task")
    elif file_modified:
        score += 12
        feedback_parts.append("✅ File modified during task")
    elif created_during_task:
        score += 10
        feedback_parts.append("✅ File timestamp within task window")
    else:
        if output_exists:
            feedback_parts.append("❌ File existed BEFORE task (possible pre-creation)")
        else:
            feedback_parts.append("❌ No file to check timestamp")
    
    details['timestamp_valid'] = newly_created or file_modified or created_during_task
    
    # ================================================================
    # CRITERION 3: File size reasonable (10 points)
    # ================================================================
    file_size_bytes = output_info.get('size_bytes', 0)
    file_size_kb = file_size_bytes / 1024 if file_size_bytes else 0
    
    if file_size_kb >= 200:  # Good screenshot
        score += 10
        feedback_parts.append(f"✅ Good file size ({file_size_kb:.1f} KB)")
    elif file_size_kb >= min_file_size_kb:
        score += 7
        feedback_parts.append(f"✅ Acceptable file size ({file_size_kb:.1f} KB)")
    elif file_size_kb >= 10:
        score += 3
        feedback_parts.append(f"⚠️ Small file size ({file_size_kb:.1f} KB)")
    else:
        feedback_parts.append(f"❌ File too small ({file_size_kb:.1f} KB)")
    
    details['file_size_kb'] = file_size_kb
    
    # ================================================================
    # CRITERION 4: Google Earth was running (10 points)
    # ================================================================
    ge_info = result.get('google_earth', {})
    ge_running = ge_info.get('running', False)
    ruler_visible = ge_info.get('ruler_window_visible', False)
    
    if ge_running:
        score += 7
        feedback_parts.append("✅ Google Earth was running")
        if ruler_visible:
            score += 3
            feedback_parts.append("✅ Ruler tool detected")
    else:
        feedback_parts.append("⚠️ Google Earth not detected as running")
    
    details['google_earth_running'] = ge_running
    details['ruler_visible'] = ruler_visible
    
    # ================================================================
    # CRITERION 5: VLM Trajectory Verification (25 points)
    # ================================================================
    trajectory_score = 0
    trajectory_feedback = []
    
    if query_vlm and traj:
        # Import trajectory sampling utilities
        try:
            from gym_anything.vlm import sample_trajectory_frames
            trajectory_frames = sample_trajectory_frames(traj, n=5)
        except ImportError:
            # Fallback: try to get frames from trajectory directly
            trajectory_frames = []
            frames = traj.get('frames', [])
            if frames:
                # Sample 5 frames evenly across the trajectory
                n_frames = len(frames)
                if n_frames >= 5:
                    indices = [int(i * (n_frames - 1) / 4) for i in range(5)]
                    trajectory_frames = [frames[i] for i in indices]
                else:
                    trajectory_frames = frames
        
        if trajectory_frames and len(trajectory_frames) >= 3:
            trajectory_prompt = """You are analyzing a sequence of screenshots from an agent performing a geographic measurement task in Google Earth.

The task was to create a multi-point measured path connecting five Mediterranean port cities:
Alexandria (Egypt) → Heraklion (Crete) → Piraeus (Greece) → Ostia (Italy) → Carthage (Tunisia)

Analyze these chronological screenshots and determine:

1. GOOGLE_EARTH_VISIBLE: Is Google Earth Pro (satellite imagery interface) visible? (yes/no)
2. MEDITERRANEAN_REGION: Does any frame show the Mediterranean Sea region? (yes/no)
3. RULER_TOOL_USED: Is there evidence the Ruler/measurement tool was used (ruler dialog, measurement line)? (yes/no)
4. MULTI_POINT_PATH: Is a multi-point path or line visible connecting multiple locations? (yes/no)
5. MEANINGFUL_PROGRESSION: Do the frames show real workflow progression (navigation, tool usage, etc.)? (yes/no)

Respond in JSON format:
{
    "google_earth_visible": true/false,
    "mediterranean_region": true/false,
    "ruler_tool_used": true/false,
    "multi_point_path": true/false,
    "meaningful_progression": true/false,
    "stages_observed": ["list what you observe"],
    "confidence": "low"/"medium"/"high"
}
"""
            try:
                vlm_traj_result = query_vlm(
                    prompt=trajectory_prompt,
                    images=trajectory_frames
                )
                
                if vlm_traj_result.get('success'):
                    parsed = vlm_traj_result.get('parsed', {})
                    details['vlm_trajectory_result'] = parsed
                    
                    # Score trajectory verification
                    if parsed.get('google_earth_visible', False):
                        trajectory_score += 5
                        trajectory_feedback.append("Google Earth visible")
                    
                    if parsed.get('mediterranean_region', False):
                        trajectory_score += 5
                        trajectory_feedback.append("Mediterranean region shown")
                    
                    if parsed.get('ruler_tool_used', False):
                        trajectory_score += 7
                        trajectory_feedback.append("Ruler tool used")
                    
                    if parsed.get('multi_point_path', False):
                        trajectory_score += 5
                        trajectory_feedback.append("Multi-point path visible")
                    
                    if parsed.get('meaningful_progression', False):
                        trajectory_score += 3
                        trajectory_feedback.append("Workflow progression observed")
                    
                    # Apply confidence adjustment
                    confidence = parsed.get('confidence', 'medium')
                    if confidence == 'low':
                        trajectory_score = int(trajectory_score * 0.7)
                else:
                    trajectory_feedback.append(f"VLM query failed: {vlm_traj_result.get('error', 'unknown')}")
                    details['vlm_trajectory_error'] = vlm_traj_result.get('error')
                    
            except Exception as e:
                trajectory_feedback.append(f"VLM trajectory error: {str(e)}")
                details['vlm_trajectory_exception'] = str(e)
        else:
            trajectory_feedback.append("Insufficient trajectory frames")
    else:
        trajectory_feedback.append("VLM or trajectory not available")
    
    score += trajectory_score
    if trajectory_feedback:
        feedback_parts.append(f"📊 Trajectory: {', '.join(trajectory_feedback)} ({trajectory_score}/25 pts)")
    
    details['trajectory_score'] = trajectory_score
    
    # ================================================================
    # CRITERION 6: VLM Final Screenshot Verification (20 points)
    # ================================================================
    final_score = 0
    final_feedback = []
    
    if query_vlm and output_exists:
        # Copy the output image from container
        temp_output = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env(expected_output_path, temp_output.name)
            
            final_prompt = """Analyze this Google Earth screenshot and verify the Mediterranean trade route measurement task was completed.

TASK: Create a measured path connecting Alexandria (Egypt) → Heraklion (Crete) → Piraeus (Greece) → Ostia (Italy) → Carthage (Tunisia)

Assess:
1. MEDITERRANEAN_SEA_VISIBLE: Is the Mediterranean Sea region clearly shown (Southern Europe, North Africa)? (yes/no)
2. PATH_OVERLAY_VISIBLE: Is there a measurement path/line overlay with multiple connected points? (yes/no)
3. PATH_POINT_COUNT: Approximately how many vertices/points does the path have? (number, 0 if no path)
4. DISTANCE_MEASUREMENT_SHOWN: Is a distance measurement value (in km) visible on screen? (yes/no)
5. APPROXIMATE_DISTANCE: If distance is visible, what is the value in kilometers? (number or "not visible")
6. COASTAL_CITIES: Does the path appear to connect coastal locations across the Mediterranean? (yes/no)

Respond in JSON format:
{
    "mediterranean_sea_visible": true/false,
    "path_overlay_visible": true/false,
    "path_point_count": number,
    "distance_measurement_shown": true/false,
    "approximate_distance_km": number or null,
    "coastal_cities_connected": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "what you see in the image"
}
"""
            vlm_final_result = query_vlm(
                prompt=final_prompt,
                image=temp_output.name
            )
            
            if vlm_final_result.get('success'):
                parsed = vlm_final_result.get('parsed', {})
                details['vlm_final_result'] = parsed
                
                # Score final screenshot verification
                if parsed.get('mediterranean_sea_visible', False):
                    final_score += 5
                    final_feedback.append("Mediterranean visible")
                
                if parsed.get('path_overlay_visible', False):
                    final_score += 6
                    final_feedback.append("Path overlay visible")
                    
                    # Bonus for correct number of points
                    point_count = parsed.get('path_point_count', 0)
                    if point_count >= 4:
                        final_score += 3
                        final_feedback.append(f"{point_count} path points")
                
                if parsed.get('distance_measurement_shown', False):
                    final_score += 4
                    final_feedback.append("Distance shown")
                    
                    # Check if distance is in expected range
                    approx_dist = parsed.get('approximate_distance_km')
                    if approx_dist and isinstance(approx_dist, (int, float)):
                        if 2400 <= approx_dist <= 3400:
                            final_score += 2
                            final_feedback.append(f"Distance ~{approx_dist}km (valid range)")
                        else:
                            final_feedback.append(f"Distance ~{approx_dist}km (outside expected range)")
                
                if parsed.get('coastal_cities_connected', False):
                    final_feedback.append("Coastal route confirmed")
                
                # Confidence adjustment
                confidence = parsed.get('confidence', 'medium')
                if confidence == 'low':
                    final_score = int(final_score * 0.7)
                elif confidence == 'high':
                    final_score = min(final_score + 2, 20)
            else:
                final_feedback.append(f"VLM query failed: {vlm_final_result.get('error', 'unknown')}")
                details['vlm_final_error'] = vlm_final_result.get('error')
                
        except Exception as e:
            final_feedback.append(f"Could not verify output image: {str(e)}")
            details['vlm_final_exception'] = str(e)
        finally:
            if os.path.exists(temp_output.name):
                os.unlink(temp_output.name)
    else:
        if not output_exists:
            final_feedback.append("No output file to verify")
        else:
            final_feedback.append("VLM not available")
    
    score += final_score
    if final_feedback:
        feedback_parts.append(f"🖼️ Screenshot: {', '.join(final_feedback)} ({final_score}/20 pts)")
    
    details['final_screenshot_score'] = final_score
    
    # ================================================================
    # DETERMINE PASS/FAIL
    # ================================================================
    # Key criteria for passing:
    # 1. File must exist
    # 2. File must have been created/modified during task OR have visual verification
    # 3. Minimum score threshold
    
    key_file_criteria = output_exists and image_valid
    key_timestamp_criteria = newly_created or file_modified or created_during_task
    key_visual_criteria = (trajectory_score >= 10) or (final_score >= 10)
    
    # Pass if: score >= 60 AND file exists AND (timestamp valid OR visual verification)
    passed = (score >= 60) and key_file_criteria and (key_timestamp_criteria or key_visual_criteria)
    
    details['key_criteria'] = {
        'file_valid': key_file_criteria,
        'timestamp_valid': key_timestamp_criteria,
        'visual_verified': key_visual_criteria
    }
    
    # Build final feedback
    feedback = " | ".join(feedback_parts)
    if passed:
        feedback = f"✅ PASSED ({score}/{max_score}) | " + feedback
    else:
        feedback = f"❌ FAILED ({score}/{max_score}) | " + feedback
        if not key_file_criteria:
            feedback += " | Missing valid output file"
        elif not key_timestamp_criteria and not key_visual_criteria:
            feedback += " | Could not verify task was actually performed"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }