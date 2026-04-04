#!/usr/bin/env python3
"""
Verifier for L'Enfant Plan Ground Overlay task.

MULTI-SIGNAL VERIFICATION:
1. Overlay exists in My Places (15 points)
2. Overlay has correct name pattern (15 points)
3. Overlay references correct image file (20 points)
4. Overlay positioned over Washington D.C. (20 points)
5. Overlay has transparency applied (15 points)
6. VLM trajectory verification - workflow completed (15 points)

Pass threshold: 70 points with overlay created and positioned correctly.

IMPORTANT: Uses copy_from_env (NOT exec_in_env) and trajectory frames for VLM.
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_lenfant_overlay(traj, env_info, task_info):
    """
    Verify that the L'Enfant Plan ground overlay was created correctly.
    
    Uses multiple independent signals to prevent gaming.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available"
        }
    
    # Get metadata from task_info
    metadata = task_info.get('metadata', {})
    expected_name_patterns = metadata.get('overlay_name_patterns', ['lenfant', "l'enfant", '1791', 'plan'])
    expected_image_filename = metadata.get('image_filename', 'lenfant_plan_1791.jpg')
    expected_center_lat = metadata.get('center_lat', 38.889)
    expected_center_lon = metadata.get('center_lon', -77.035)
    tolerance_degrees = metadata.get('tolerance_degrees', 0.05)
    dc_bounds = metadata.get('dc_bounds', {
        'north': 38.95,
        'south': 38.85,
        'east': -76.95,
        'west': -77.10
    })
    
    feedback_parts = []
    score = 0
    details = {}
    
    # ================================================================
    # Copy result file from container
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
    # Copy My Places KML for detailed analysis
    # ================================================================
    myplaces_content = ""
    temp_kml = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
    try:
        copy_from_env("/tmp/myplaces_final.kml", temp_kml.name)
        with open(temp_kml.name, 'r', encoding='utf-8', errors='ignore') as f:
            myplaces_content = f.read()
        details['myplaces_copied'] = True
    except Exception as e:
        logger.warning(f"Could not copy My Places KML: {e}")
        details['myplaces_copied'] = False
    finally:
        if os.path.exists(temp_kml.name):
            os.unlink(temp_kml.name)
    
    # ================================================================
    # Copy overlay details JSON
    # ================================================================
    overlay_details = {}
    temp_overlay = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/overlay_details.json", temp_overlay.name)
        with open(temp_overlay.name, 'r') as f:
            overlay_details = json.load(f)
        details['overlay_details'] = overlay_details
    except Exception as e:
        logger.warning(f"Could not read overlay_details.json: {e}")
    finally:
        if os.path.exists(temp_overlay.name):
            os.unlink(temp_overlay.name)
    
    # ================================================================
    # CRITERION 1: Overlay exists in My Places (15 points)
    # ================================================================
    overlay_added = result.get('overlay_added', False)
    final_count = result.get('final_overlay_count', 0)
    initial_count = result.get('initial_overlay_count', 0)
    
    if overlay_added or final_count > initial_count:
        score += 15
        feedback_parts.append(f"✅ Overlay added to My Places ({final_count} total)")
    elif final_count > 0:
        score += 8
        feedback_parts.append(f"⚠️ Overlays exist ({final_count}) but unclear if new")
    else:
        feedback_parts.append("❌ No overlay found in My Places")
    
    # ================================================================
    # CRITERION 2: Overlay has correct name pattern (15 points)
    # ================================================================
    lenfant_overlay = overlay_details.get('lenfant_overlay', {})
    overlay_name = result.get('overlay_name_found', '') or lenfant_overlay.get('name', '')
    
    name_matches = False
    if overlay_name:
        name_lower = overlay_name.lower()
        for pattern in expected_name_patterns:
            if pattern in name_lower:
                name_matches = True
                break
    
    if name_matches:
        score += 15
        feedback_parts.append(f"✅ Overlay name correct: '{overlay_name}'")
    elif overlay_name:
        score += 5
        feedback_parts.append(f"⚠️ Overlay exists but name doesn't match: '{overlay_name}'")
    else:
        feedback_parts.append("❌ Overlay name not found or doesn't match expected pattern")
    
    # ================================================================
    # CRITERION 3: Overlay references correct image file (20 points)
    # ================================================================
    overlay_href = result.get('overlay_href_found', '') or lenfant_overlay.get('href', '')
    
    image_correct = False
    if overlay_href:
        if expected_image_filename in overlay_href:
            image_correct = True
    
    if image_correct:
        score += 20
        feedback_parts.append(f"✅ Image file correctly linked")
    elif overlay_href:
        score += 5
        feedback_parts.append(f"⚠️ Image linked but not expected file: {overlay_href}")
    else:
        feedback_parts.append("❌ Image file not correctly linked")
    
    # ================================================================
    # CRITERION 4: Overlay positioned over Washington D.C. (20 points)
    # ================================================================
    position_correct = False
    center_lat = None
    center_lon = None
    
    if lenfant_overlay:
        north = lenfant_overlay.get('north')
        south = lenfant_overlay.get('south')
        east = lenfant_overlay.get('east')
        west = lenfant_overlay.get('west')
        
        if all(v is not None for v in [north, south, east, west]):
            center_lat = (north + south) / 2
            center_lon = (east + west) / 2
            
            # Check if center is within DC bounds
            in_dc_bounds = (
                dc_bounds['south'] <= center_lat <= dc_bounds['north'] and
                dc_bounds['west'] <= center_lon <= dc_bounds['east']
            )
            
            # Check if close to expected center
            lat_diff = abs(center_lat - expected_center_lat)
            lon_diff = abs(center_lon - expected_center_lon)
            
            if lat_diff <= tolerance_degrees and lon_diff <= tolerance_degrees:
                position_correct = True
                score += 20
                feedback_parts.append(f"✅ Position correct: ({center_lat:.4f}°N, {center_lon:.4f}°W)")
            elif in_dc_bounds:
                score += 12
                feedback_parts.append(f"⚠️ Position in DC area but not centered: ({center_lat:.4f}°N, {center_lon:.4f}°W)")
            elif lat_diff <= tolerance_degrees * 3 and lon_diff <= tolerance_degrees * 3:
                score += 8
                feedback_parts.append(f"⚠️ Position roughly correct: ({center_lat:.4f}°N, {center_lon:.4f}°W)")
            else:
                feedback_parts.append(f"❌ Position incorrect: ({center_lat:.4f}°N, {center_lon:.4f}°W)")
        else:
            feedback_parts.append("❌ Could not determine overlay position (missing bounds)")
    else:
        feedback_parts.append("❌ No overlay found for position verification")
    
    details['overlay_position'] = {
        'center_lat': center_lat,
        'center_lon': center_lon,
        'position_correct': position_correct
    }
    
    # ================================================================
    # CRITERION 5: Overlay has transparency applied (15 points)
    # ================================================================
    transparency_applied = False
    transparency_percent = None
    
    if lenfant_overlay:
        color = lenfant_overlay.get('color', 'ffffffff')
        if color and len(color) >= 2:
            try:
                # KML color format is AABBGGRR (alpha, blue, green, red)
                alpha = int(color[:2], 16)
                # Convert to transparency percentage (255 = opaque = 0% transparency)
                transparency_percent = 100 - (alpha / 255 * 100)
                
                # Check if transparency is in acceptable range (30-70%)
                if 30 <= transparency_percent <= 70:
                    transparency_applied = True
                    score += 15
                    feedback_parts.append(f"✅ Transparency correct: {transparency_percent:.0f}%")
                elif 10 <= transparency_percent <= 90:
                    transparency_applied = True
                    score += 10
                    feedback_parts.append(f"⚠️ Transparency applied but outside ideal range: {transparency_percent:.0f}%")
                elif transparency_percent < 10:
                    score += 3
                    feedback_parts.append(f"⚠️ Overlay is nearly opaque: {transparency_percent:.0f}% transparency")
                else:
                    feedback_parts.append(f"❌ Overlay is nearly invisible: {transparency_percent:.0f}% transparency")
            except (ValueError, TypeError):
                feedback_parts.append("⚠️ Could not parse transparency value")
        else:
            feedback_parts.append("⚠️ No color/transparency information found")
    else:
        feedback_parts.append("❌ No overlay found for transparency verification")
    
    details['transparency'] = {
        'percent': transparency_percent,
        'applied': transparency_applied
    }
    
    # ================================================================
    # CRITERION 6: VLM Trajectory Verification (15 points)
    # ================================================================
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm and traj:
        # Use trajectory frames, NOT just final screenshot
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Sample frames across the trajectory
            trajectory_frames = sample_trajectory_frames(traj, n=5)
            final_frame = get_final_screenshot(traj)
            
            if trajectory_frames or final_frame:
                frames_to_check = trajectory_frames if trajectory_frames else []
                if final_frame:
                    frames_to_check.append(final_frame)
                
                vlm_prompt = """You are verifying if an agent successfully created a ground overlay in Google Earth Pro.

The agent's task was to:
1. Open the Image Overlay dialog (Add > Image Overlay)
2. Name the overlay "L'Enfant Plan 1791"
3. Select a historical map image file
4. Position the overlay over Washington D.C.
5. Set transparency to ~50%
6. Save the overlay

Look at these screenshots from the agent's work and assess:
1. IMAGE_OVERLAY_DIALOG: Did the agent open the Image Overlay dialog at any point?
2. OVERLAY_POSITIONED: Is there evidence of positioning green handles on an overlay?
3. OVERLAY_VISIBLE: Is a semi-transparent historical map overlay visible over Washington D.C.?
4. DC_LOCATION: Does the view show Washington D.C. / National Mall area?
5. WORKFLOW_PROGRESS: Did the agent make meaningful progress through the workflow?

Respond in JSON format:
{
    "image_overlay_dialog_seen": true/false,
    "overlay_positioned": true/false,
    "overlay_visible": true/false,
    "dc_location_visible": true/false,
    "workflow_progress": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see across the frames"
}"""
                
                vlm_result = query_vlm(prompt=vlm_prompt, images=frames_to_check)
                details['vlm_result'] = vlm_result
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    
                    vlm_criteria_met = sum([
                        parsed.get('image_overlay_dialog_seen', False),
                        parsed.get('overlay_positioned', False),
                        parsed.get('overlay_visible', False),
                        parsed.get('dc_location_visible', False),
                        parsed.get('workflow_progress', False)
                    ])
                    
                    confidence = parsed.get('confidence', 'low')
                    confidence_mult = {'high': 1.0, 'medium': 0.85, 'low': 0.7}.get(confidence, 0.7)
                    
                    vlm_score = int((vlm_criteria_met / 5) * 15 * confidence_mult)
                    score += vlm_score
                    
                    if vlm_score >= 10:
                        feedback_parts.append(f"✅ VLM: Workflow verified ({vlm_criteria_met}/5 criteria, {confidence} confidence)")
                    elif vlm_score >= 5:
                        feedback_parts.append(f"⚠️ VLM: Partial workflow ({vlm_criteria_met}/5 criteria)")
                    else:
                        feedback_parts.append(f"❌ VLM: Workflow not verified ({vlm_criteria_met}/5 criteria)")
                    
                    if parsed.get('observations'):
                        details['vlm_observations'] = parsed['observations']
                else:
                    feedback_parts.append("⚠️ VLM verification failed")
            else:
                feedback_parts.append("⚠️ No trajectory frames available for VLM")
        except ImportError:
            logger.warning("Could not import VLM utilities")
            feedback_parts.append("⚠️ VLM utilities not available")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            feedback_parts.append(f"⚠️ VLM error: {e}")
    else:
        feedback_parts.append("⚠️ VLM not available for trajectory verification")
    
    details['vlm_score'] = vlm_score
    
    # ================================================================
    # Anti-Gaming: Timestamp check
    # ================================================================
    task_start = result.get('task_start', 0)
    task_end = result.get('task_end', 0)
    
    if task_start > 0 and task_end > 0:
        duration = task_end - task_start
        if duration < 5:
            feedback_parts.append("⚠️ Task completed suspiciously fast")
            score = max(0, score - 10)
        details['task_duration'] = duration
    
    # ================================================================
    # Final Assessment
    # ================================================================
    max_score = 100
    
    # Key criteria for passing
    has_overlay = result.get('has_lenfant_overlay', False) or overlay_added or final_count > 0
    has_correct_position = position_correct or (center_lat is not None and 
                                                  dc_bounds['south'] <= center_lat <= dc_bounds['north'])
    
    key_criteria_met = has_overlay and (name_matches or image_correct)
    
    passed = score >= 70 and key_criteria_met
    
    # Summary
    if passed:
        feedback_parts.append(f"\n✅ TASK PASSED with score {score}/{max_score}")
    else:
        feedback_parts.append(f"\n❌ TASK FAILED with score {score}/{max_score} (need 70 with key criteria)")
        if not has_overlay:
            feedback_parts.append("   - Missing: Overlay not found")
        if not (name_matches or image_correct):
            feedback_parts.append("   - Missing: Name or image not correctly configured")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }