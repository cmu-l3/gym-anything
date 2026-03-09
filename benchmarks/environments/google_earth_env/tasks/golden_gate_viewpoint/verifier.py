#!/usr/bin/env python3
"""
Verifier for golden_gate_viewpoint task.

TASK: Create a cinematic viewpoint placemark of the Golden Gate Bridge
with specific camera parameters (tilt, heading, range) and save it
with the name "Golden Gate Hero Shot".

VERIFICATION STRATEGY:
1. Programmatic: Parse KML export for placemark existence and LookAt parameters
2. Anti-gaming: Check file modification timestamps
3. VLM: Verify trajectory shows navigation and view manipulation
4. VLM: Verify final screenshot shows Golden Gate Bridge at angle

SCORING (100 points):
- Placemark exists with correct name: 10 pts
- Description present: 5 pts
- LookAt element saved: 5 pts
- Location accuracy (lat/lon): 30 pts
- Range appropriate: 15 pts
- Tilt angle correct: 20 pts
- Heading correct: 15 pts

PASS: >= 70 points AND tilt > 30 degrees (must not be flat top-down view)
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_golden_gate_viewpoint(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the Golden Gate viewpoint task completion.
    
    Uses multiple verification signals:
    1. KML file analysis for placemark and camera parameters
    2. Timestamp checks for anti-gaming
    3. VLM trajectory verification
    """
    
    # Get copy_from_env function
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available for verification"
        }
    
    # Get metadata with expected values
    metadata = task_info.get('metadata', {})
    target_lat = metadata.get('target_latitude', 37.8199)
    target_lon = metadata.get('target_longitude', -122.4783)
    lat_tol = metadata.get('latitude_tolerance', 0.01)
    lon_tol = metadata.get('longitude_tolerance', 0.01)
    range_min = metadata.get('range_min', 1000)
    range_max = metadata.get('range_max', 2000)
    tilt_min = metadata.get('tilt_min', 50)
    tilt_max = metadata.get('tilt_max', 80)
    heading_min = metadata.get('heading_min', 190)
    heading_max = metadata.get('heading_max', 250)
    
    feedback_parts = []
    score = 0
    details = {}
    
    # ================================================================
    # STEP 1: Copy result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        details['result_loaded'] = True
    except Exception as e:
        logger.error(f"Failed to read task result: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Failed to read task result: {e}",
            "details": {"error": str(e)}
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # STEP 2: Anti-gaming checks
    # ================================================================
    kml_modified = result.get('kml_modified', False)
    google_earth_running = result.get('google_earth_running', False)
    task_duration = result.get('task_duration_seconds', 0)
    
    details['kml_modified'] = kml_modified
    details['google_earth_running'] = google_earth_running
    details['task_duration'] = task_duration
    
    if not kml_modified:
        feedback_parts.append("⚠️ KML file not modified (possible do-nothing)")
    
    if not google_earth_running:
        feedback_parts.append("⚠️ Google Earth not running at end")
    
    # ================================================================
    # STEP 3: Check placemark existence and name (10 points)
    # ================================================================
    placemark_found = result.get('placemark_found', False)
    placemark_name = result.get('placemark_name', '')
    
    details['placemark_found'] = placemark_found
    details['placemark_name'] = placemark_name
    
    if placemark_found:
        # Check if name matches expected
        name_lower = placemark_name.lower()
        if 'golden gate hero shot' in name_lower:
            score += 10
            feedback_parts.append("✅ Placemark name correct: 'Golden Gate Hero Shot'")
        elif 'golden gate' in name_lower or 'hero shot' in name_lower:
            score += 7
            feedback_parts.append(f"⚠️ Placemark name partial match: '{placemark_name}'")
        else:
            score += 3
            feedback_parts.append(f"⚠️ Placemark found but wrong name: '{placemark_name}'")
    else:
        feedback_parts.append("❌ No placemark found near Golden Gate Bridge")
    
    # ================================================================
    # STEP 4: Check description (5 points)
    # ================================================================
    placemark_desc = result.get('placemark_description', '')
    details['placemark_description'] = placemark_desc
    
    if placemark_desc:
        if 'marketing viewpoint' in placemark_desc.lower():
            score += 5
            feedback_parts.append("✅ Description contains 'Marketing viewpoint'")
        elif 'marin' in placemark_desc.lower() or 'headlands' in placemark_desc.lower():
            score += 3
            feedback_parts.append("⚠️ Description partially matches")
        else:
            score += 1
            feedback_parts.append("⚠️ Description present but doesn't match expected")
    else:
        feedback_parts.append("❌ No description set")
    
    # ================================================================
    # STEP 5: Check LookAt element exists (5 points)
    # ================================================================
    has_lookat = result.get('has_lookat', False)
    lookat = result.get('lookat', {})
    details['has_lookat'] = has_lookat
    details['lookat'] = lookat
    
    if has_lookat:
        score += 5
        feedback_parts.append("✅ Camera view saved (LookAt present)")
    else:
        feedback_parts.append("❌ Camera view not saved (no LookAt element)")
        # Without LookAt, we can't verify camera parameters
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # STEP 6: Check location accuracy (30 points)
    # ================================================================
    lookat_lat = lookat.get('latitude')
    lookat_lon = lookat.get('longitude')
    
    if lookat_lat is not None and lookat_lon is not None:
        lat_diff = abs(lookat_lat - target_lat)
        lon_diff = abs(lookat_lon - target_lon)
        
        details['latitude_diff'] = lat_diff
        details['longitude_diff'] = lon_diff
        
        if lat_diff < lat_tol and lon_diff < lon_tol:
            score += 30
            feedback_parts.append(f"✅ Location accurate (lat: {lookat_lat:.4f}, lon: {lookat_lon:.4f})")
        elif lat_diff < lat_tol * 3 and lon_diff < lon_tol * 3:
            score += 20
            feedback_parts.append(f"⚠️ Location approximate (lat diff: {lat_diff:.4f}, lon diff: {lon_diff:.4f})")
        elif lat_diff < 0.1 and lon_diff < 0.1:
            score += 10
            feedback_parts.append(f"⚠️ Location in general area (lat diff: {lat_diff:.4f}, lon diff: {lon_diff:.4f})")
        else:
            feedback_parts.append(f"❌ Wrong location (lat: {lookat_lat:.4f}, lon: {lookat_lon:.4f})")
    else:
        feedback_parts.append("❌ Location coordinates missing from LookAt")
    
    # ================================================================
    # STEP 7: Check range (15 points)
    # ================================================================
    lookat_range = lookat.get('range')
    
    if lookat_range is not None:
        details['range'] = lookat_range
        
        if range_min <= lookat_range <= range_max:
            score += 15
            feedback_parts.append(f"✅ Range correct: {lookat_range:.0f}m (target: {range_min}-{range_max}m)")
        elif range_min * 0.5 <= lookat_range <= range_max * 1.5:
            score += 10
            feedback_parts.append(f"⚠️ Range acceptable: {lookat_range:.0f}m")
        elif 500 <= lookat_range <= 5000:
            score += 5
            feedback_parts.append(f"⚠️ Range in reasonable bounds: {lookat_range:.0f}m")
        else:
            feedback_parts.append(f"❌ Range out of bounds: {lookat_range:.0f}m")
    else:
        feedback_parts.append("❌ Range missing from LookAt")
    
    # ================================================================
    # STEP 8: Check tilt angle (20 points) - CRITICAL
    # ================================================================
    lookat_tilt = lookat.get('tilt')
    
    if lookat_tilt is not None:
        details['tilt'] = lookat_tilt
        
        if tilt_min <= lookat_tilt <= tilt_max:
            score += 20
            feedback_parts.append(f"✅ Tilt correct: {lookat_tilt:.1f}° (target: {tilt_min}-{tilt_max}°)")
        elif 30 <= lookat_tilt <= 85:
            score += 12
            feedback_parts.append(f"⚠️ Tilt acceptable: {lookat_tilt:.1f}° (shows angle)")
        elif lookat_tilt > 10:
            score += 5
            feedback_parts.append(f"⚠️ Tilt shows some angle: {lookat_tilt:.1f}°")
        else:
            feedback_parts.append(f"❌ Tilt too flat (top-down view): {lookat_tilt:.1f}°")
    else:
        lookat_tilt = 0  # Assume flat for pass criteria check
        feedback_parts.append("❌ Tilt missing from LookAt")
    
    # ================================================================
    # STEP 9: Check heading (15 points)
    # ================================================================
    lookat_heading = lookat.get('heading')
    
    if lookat_heading is not None:
        # Normalize heading to 0-360
        heading_normalized = lookat_heading % 360
        details['heading'] = heading_normalized
        
        if heading_min <= heading_normalized <= heading_max:
            score += 15
            feedback_parts.append(f"✅ Heading correct: {heading_normalized:.1f}° (target: {heading_min}-{heading_max}°)")
        elif (heading_min - 30) <= heading_normalized <= (heading_max + 30):
            score += 10
            feedback_parts.append(f"⚠️ Heading approximate: {heading_normalized:.1f}°")
        else:
            feedback_parts.append(f"❌ Heading incorrect: {heading_normalized:.1f}° (expected {heading_min}-{heading_max}°)")
    else:
        feedback_parts.append("❌ Heading missing from LookAt")
    
    # ================================================================
    # STEP 10: VLM Verification (bonus verification, not scored)
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    vlm_verified = False
    
    if query_vlm and traj:
        try:
            # Import VLM utilities
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Get trajectory frames for process verification
            trajectory_frames = sample_trajectory_frames(traj, n=5)
            final_screenshot = get_final_screenshot(traj)
            
            if trajectory_frames or final_screenshot:
                VLM_PROMPT = """You are verifying a Google Earth task where the agent should have:
1. Navigated to the Golden Gate Bridge in San Francisco
2. Set up an angled camera view (not top-down)
3. Created a placemark to save this view

Look at these screenshots and determine:
1. Is this Google Earth showing the Golden Gate Bridge area?
2. Is the view tilted/angled (showing the bridge from a dramatic perspective, not flat top-down)?
3. Is there any indication of placemark creation (dialog box, marker visible)?

Respond in JSON format:
{
    "shows_golden_gate": true/false,
    "view_is_angled": true/false,
    "placemark_activity": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "what you see in the images"
}
"""
                images_to_check = []
                if trajectory_frames:
                    images_to_check.extend(trajectory_frames[-3:])  # Last 3 trajectory frames
                if final_screenshot:
                    images_to_check.append(final_screenshot)
                
                if images_to_check:
                    vlm_result = query_vlm(prompt=VLM_PROMPT, images=images_to_check)
                    
                    if vlm_result.get('success'):
                        parsed = vlm_result.get('parsed', {})
                        details['vlm_result'] = parsed
                        
                        shows_gg = parsed.get('shows_golden_gate', False)
                        is_angled = parsed.get('view_is_angled', False)
                        
                        if shows_gg and is_angled:
                            vlm_verified = True
                            feedback_parts.append("✅ VLM confirms: Golden Gate at angled view")
                        elif shows_gg:
                            feedback_parts.append("⚠️ VLM: Golden Gate visible but angle unclear")
                        else:
                            feedback_parts.append("⚠️ VLM: Could not confirm Golden Gate view")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            details['vlm_error'] = str(e)
    
    # ================================================================
    # DETERMINE PASS/FAIL
    # ================================================================
    # Key criteria: must have created a placemark AND must not be a flat top-down view
    has_angled_view = lookat_tilt is not None and lookat_tilt > 30
    key_criteria_met = placemark_found and has_lookat and has_angled_view
    
    passed = score >= 70 and key_criteria_met
    
    details['score'] = score
    details['key_criteria_met'] = key_criteria_met
    details['has_angled_view'] = has_angled_view
    details['vlm_verified'] = vlm_verified
    
    # Build summary
    if passed:
        summary = f"✅ PASSED ({score}/100 points)"
    else:
        if not placemark_found:
            summary = f"❌ FAILED: No placemark created ({score}/100 points)"
        elif not has_lookat:
            summary = f"❌ FAILED: Camera view not saved ({score}/100 points)"
        elif not has_angled_view:
            summary = f"❌ FAILED: View is flat/top-down, not angled ({score}/100 points)"
        else:
            summary = f"❌ FAILED: Score below threshold ({score}/100 points)"
    
    feedback_parts.insert(0, summary)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }