#!/usr/bin/env python3
"""
Verifier for glacier_terminus_width task.

TASK: Measure the width of the Perito Moreno Glacier terminus by creating
a path along the ice front and documenting with a placemark and KML export.

VERIFICATION STRATEGY:
1. KML file exists and was created during task (15 pts)
2. Valid KML structure with parseable content (5 pts)
3. Path element present with correct name (15 pts)
4. Path coordinates in correct geographic region (15 pts)
5. Path length is reasonable (4-6 km) (15 pts)
6. Path has sufficient detail (>=10 points) (5 pts)
7. Placemark present with correct name (10 pts)
8. Placemark positioned within path region (10 pts)
9. Measurement documented in description (5 pts)
10. VLM trajectory verification (5 pts)

Pass threshold: 60 points with valid path in correct region
"""

import json
import tempfile
import os
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Perito Moreno Glacier terminus region bounds
GLACIER_LAT_MIN = -50.55
GLACIER_LAT_MAX = -50.45
GLACIER_LON_MIN = -73.25
GLACIER_LON_MAX = -73.05

# Expected terminus width
EXPECTED_LENGTH_MIN_KM = 4.0
EXPECTED_LENGTH_MAX_KM = 6.0
MIN_PATH_POINTS = 10


def verify_glacier_terminus_width(traj, env_info, task_info):
    """
    Verify that the glacier terminus was measured correctly.
    
    Uses multiple independent signals to prevent gaming.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    feedback_parts = []
    score = 0
    details = {}
    
    # ================================================================
    # Copy result file from container
    # ================================================================
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
        details['export_result'] = result
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to read task result: {e}",
            "details": {"error": str(e)}
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
    
    # ================================================================
    # CRITERION 1: KML file exists and was created during task (15 pts)
    # ================================================================
    output_exists = result.get('output_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    output_size = result.get('output_size_bytes', 0)
    
    if output_exists and file_created_during_task:
        score += 15
        feedback_parts.append(f"✅ KML file created during task ({output_size} bytes)")
    elif output_exists:
        score += 5
        feedback_parts.append(f"⚠️ KML file exists but may have pre-existed")
    else:
        feedback_parts.append("❌ KML file NOT found at ~/Documents/glacier_terminus.kml")
        # Early exit - nothing else to verify
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: Valid KML structure (5 pts)
    # ================================================================
    kml_valid = result.get('kml_valid', False)
    
    if kml_valid:
        score += 5
        feedback_parts.append("✅ Valid KML structure")
    else:
        feedback_parts.append("❌ Invalid KML structure")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 3: Path element present with correct name (15 pts)
    # ================================================================
    path_found = result.get('path_found', False)
    path_name = result.get('path_name', '')
    expected_path_name = metadata.get('expected_path_name', 'Perito_Moreno_Terminus')
    
    if path_found:
        # Check if name matches (case-insensitive partial match)
        name_matches = (
            expected_path_name.lower() in path_name.lower() or
            'terminus' in path_name.lower() or
            'perito' in path_name.lower() or
            'glacier' in path_name.lower()
        )
        
        if name_matches:
            score += 15
            feedback_parts.append(f"✅ Path found: '{path_name}'")
        else:
            score += 8
            feedback_parts.append(f"⚠️ Path found but name '{path_name}' doesn't match expected")
    else:
        feedback_parts.append("❌ No path (LineString) found in KML")
    
    # ================================================================
    # CRITERION 4: Path coordinates in correct geographic region (15 pts)
    # ================================================================
    path_lat_min = result.get('path_lat_min', 0)
    path_lat_max = result.get('path_lat_max', 0)
    path_lon_min = result.get('path_lon_min', 0)
    path_lon_max = result.get('path_lon_max', 0)
    
    lat_in_range = (GLACIER_LAT_MIN <= path_lat_min <= GLACIER_LAT_MAX and 
                   GLACIER_LAT_MIN <= path_lat_max <= GLACIER_LAT_MAX)
    lon_in_range = (GLACIER_LON_MIN <= path_lon_min <= GLACIER_LON_MAX and 
                   GLACIER_LON_MIN <= path_lon_max <= GLACIER_LON_MAX)
    
    coords_valid = lat_in_range and lon_in_range
    details['path_coords'] = {
        'lat_range': [path_lat_min, path_lat_max],
        'lon_range': [path_lon_min, path_lon_max],
        'expected_lat': [GLACIER_LAT_MIN, GLACIER_LAT_MAX],
        'expected_lon': [GLACIER_LON_MIN, GLACIER_LON_MAX],
        'in_range': coords_valid
    }
    
    if coords_valid:
        score += 15
        feedback_parts.append(f"✅ Path coordinates in Perito Moreno region")
    elif path_found:
        # Check if close to expected region (within ~50km)
        lat_close = abs(path_lat_min - (-50.5)) < 0.5 or abs(path_lat_max - (-50.5)) < 0.5
        lon_close = abs(path_lon_min - (-73.15)) < 0.5 or abs(path_lon_max - (-73.15)) < 0.5
        
        if lat_close and lon_close:
            score += 5
            feedback_parts.append(f"⚠️ Path near expected region but not exact")
        else:
            feedback_parts.append(f"❌ Path coordinates NOT in Perito Moreno region")
    
    # ================================================================
    # CRITERION 5: Path length is reasonable (4-6 km) (15 pts)
    # ================================================================
    path_length_km = result.get('path_length_km', 0)
    details['path_length_km'] = path_length_km
    
    length_valid = EXPECTED_LENGTH_MIN_KM <= path_length_km <= EXPECTED_LENGTH_MAX_KM
    
    if length_valid:
        score += 15
        feedback_parts.append(f"✅ Path length {path_length_km:.2f} km (expected: 4-6 km)")
    elif path_length_km > 0:
        # Partial credit for close measurements
        if 3.0 <= path_length_km <= 7.0:
            score += 8
            feedback_parts.append(f"⚠️ Path length {path_length_km:.2f} km (slightly outside 4-6 km)")
        elif 2.0 <= path_length_km <= 8.0:
            score += 3
            feedback_parts.append(f"⚠️ Path length {path_length_km:.2f} km (outside expected range)")
        else:
            feedback_parts.append(f"❌ Path length {path_length_km:.2f} km (far from expected 4-6 km)")
    else:
        feedback_parts.append("❌ Could not calculate path length")
    
    # ================================================================
    # CRITERION 6: Path has sufficient detail (>=10 points) (5 pts)
    # ================================================================
    path_point_count = result.get('path_point_count', 0)
    details['path_point_count'] = path_point_count
    
    if path_point_count >= MIN_PATH_POINTS:
        score += 5
        feedback_parts.append(f"✅ Path has {path_point_count} points (traced, not straight line)")
    elif path_point_count >= 5:
        score += 2
        feedback_parts.append(f"⚠️ Path has only {path_point_count} points (expected >= {MIN_PATH_POINTS})")
    else:
        feedback_parts.append(f"❌ Path has only {path_point_count} points (too simple)")
    
    # ================================================================
    # CRITERION 7: Placemark present with correct name (10 pts)
    # ================================================================
    placemark_found = result.get('placemark_found', False)
    placemark_name = result.get('placemark_name', '')
    expected_placemark_name = metadata.get('expected_placemark_name', 'Terminus_Center')
    
    if placemark_found:
        name_matches = (
            expected_placemark_name.lower() in placemark_name.lower() or
            'center' in placemark_name.lower() or
            'terminus' in placemark_name.lower() or
            'mid' in placemark_name.lower()
        )
        
        if name_matches:
            score += 10
            feedback_parts.append(f"✅ Placemark found: '{placemark_name}'")
        else:
            score += 5
            feedback_parts.append(f"⚠️ Placemark found but name '{placemark_name}' doesn't match expected")
    else:
        feedback_parts.append("❌ No placemark (Point) found in KML")
    
    # ================================================================
    # CRITERION 8: Placemark positioned within path region (10 pts)
    # ================================================================
    placemark_lat = result.get('placemark_lat', 0)
    placemark_lon = result.get('placemark_lon', 0)
    
    if placemark_found and path_found:
        # Check if placemark is within the path's bounding box (with some tolerance)
        tolerance = 0.02  # ~2km tolerance
        lat_in_path = (path_lat_min - tolerance) <= placemark_lat <= (path_lat_max + tolerance)
        lon_in_path = (path_lon_min - tolerance) <= placemark_lon <= (path_lon_max + tolerance)
        
        placemark_in_region = lat_in_path and lon_in_path
        details['placemark_position'] = {
            'lat': placemark_lat,
            'lon': placemark_lon,
            'in_path_region': placemark_in_region
        }
        
        if placemark_in_region:
            score += 10
            feedback_parts.append(f"✅ Placemark positioned within path region")
        else:
            # Check if at least in glacier region
            if (GLACIER_LAT_MIN <= placemark_lat <= GLACIER_LAT_MAX and
                GLACIER_LON_MIN <= placemark_lon <= GLACIER_LON_MAX):
                score += 5
                feedback_parts.append(f"⚠️ Placemark in glacier region but not centered on path")
            else:
                feedback_parts.append(f"❌ Placemark NOT positioned in path region")
    elif placemark_found:
        feedback_parts.append("⚠️ Cannot verify placemark position (no path)")
    
    # ================================================================
    # CRITERION 9: Measurement documented in description (5 pts)
    # ================================================================
    measurement_in_desc = result.get('measurement_in_description', False)
    measurement_value = result.get('measurement_value_km', 0)
    placemark_desc = result.get('placemark_description', '')
    
    if measurement_in_desc:
        score += 5
        feedback_parts.append(f"✅ Measurement ({measurement_value} km) documented in description")
    elif placemark_desc:
        # Check for any numeric value in description
        score += 2
        feedback_parts.append(f"⚠️ Description exists but no clear measurement found")
    else:
        feedback_parts.append("❌ No measurement documented in placemark description")
    
    # ================================================================
    # CRITERION 10: VLM trajectory verification (5 pts)
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    vlm_score = 0
    
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Get trajectory frames
            frames = sample_trajectory_frames(traj, n=5)
            final_frame = get_final_screenshot(traj)
            
            if frames or final_frame:
                all_frames = (frames or []) + ([final_frame] if final_frame else [])
                
                vlm_prompt = """You are verifying if an agent measured a glacier terminus in Google Earth.

The task was to trace the Perito Moreno Glacier terminus (ice front) in Argentina.

Looking at these screenshots from the agent's work, assess:
1. GLACIER_VISIBLE: Is a glacier/ice feature visible (white/blue ice meeting water)?
2. PATH_TOOL_USED: Is there evidence of the path/line tool being used (drawing lines)?
3. PLACEMARK_CREATED: Is there evidence of placemark creation dialog?
4. GOOGLE_EARTH_USED: Is this clearly Google Earth satellite imagery?
5. PROGRESSION: Do the frames show meaningful work progression?

Respond in JSON format:
{
    "glacier_visible": true/false,
    "path_tool_used": true/false,
    "placemark_created": true/false,
    "google_earth_used": true/false,
    "meaningful_progression": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description"
}
"""
                
                vlm_result = query_vlm(
                    prompt=vlm_prompt,
                    images=all_frames
                )
                
                details['vlm_result'] = vlm_result
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    
                    # Count positive signals
                    signals = [
                        parsed.get('glacier_visible', False),
                        parsed.get('path_tool_used', False),
                        parsed.get('google_earth_used', False),
                        parsed.get('meaningful_progression', False)
                    ]
                    
                    positive_signals = sum(signals)
                    confidence = parsed.get('confidence', 'low')
                    
                    if positive_signals >= 3 and confidence in ['medium', 'high']:
                        vlm_score = 5
                        feedback_parts.append(f"✅ VLM confirms glacier measurement workflow")
                    elif positive_signals >= 2:
                        vlm_score = 3
                        feedback_parts.append(f"⚠️ VLM partially confirms work ({positive_signals}/4 signals)")
                    else:
                        feedback_parts.append(f"❌ VLM could not confirm glacier work")
                else:
                    feedback_parts.append(f"⚠️ VLM verification inconclusive")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback_parts.append(f"⚠️ VLM verification error: {str(e)[:50]}")
    else:
        feedback_parts.append("⚠️ VLM not available for verification")
    
    score += vlm_score
    
    # ================================================================
    # DETERMINE PASS/FAIL
    # ================================================================
    # Key criteria: file created during task + path in correct region
    key_criteria_met = (
        file_created_during_task and 
        path_found and 
        coords_valid
    )
    
    passed = score >= 60 and key_criteria_met
    
    details['score_breakdown'] = {
        'file_created': 15 if (output_exists and file_created_during_task) else (5 if output_exists else 0),
        'kml_valid': 5 if kml_valid else 0,
        'path_found': 15 if path_found else 0,
        'coords_valid': 15 if coords_valid else 0,
        'length_valid': 15 if length_valid else 0,
        'path_detail': 5 if path_point_count >= MIN_PATH_POINTS else 0,
        'placemark_found': 10 if placemark_found else 0,
        'placemark_position': 10 if (placemark_found and coords_valid) else 0,
        'measurement_doc': 5 if measurement_in_desc else 0,
        'vlm': vlm_score
    }
    
    details['key_criteria'] = {
        'file_created_during_task': file_created_during_task,
        'path_found': path_found,
        'coords_valid': coords_valid,
        'all_met': key_criteria_met
    }
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }