#!/usr/bin/env python3
"""
Verifier for Thames River Path Measurement task.

VERIFICATION STRATEGY:
1. KML file exists at correct location (15 points)
2. File was created/modified during task - anti-gaming (15 points)
3. Valid KML with parseable coordinates (10 points)
4. Start point near Tower Bridge (15 points)
5. End point near Westminster Bridge (15 points)
6. Sufficient waypoints (at least 8) (15 points)
7. VLM trajectory verification - shows path creation workflow (15 points)

Pass threshold: 70 points with start AND end points correct
"""

import json
import tempfile
import os
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def haversine_distance(lat1, lon1, lat2, lon2):
    """Calculate distance between two points in km."""
    R = 6371  # Earth's radius in km
    lat1, lon1, lat2, lon2 = map(math.radians, [lat1, lon1, lat2, lon2])
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    a = math.sin(dlat/2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon/2)**2
    c = 2 * math.asin(math.sqrt(a))
    return R * c


def calculate_path_length(coordinates):
    """Calculate total path length in km."""
    if len(coordinates) < 2:
        return 0
    total = 0
    for i in range(len(coordinates) - 1):
        c1, c2 = coordinates[i], coordinates[i+1]
        total += haversine_distance(c1['lat'], c1['lon'], c2['lat'], c2['lon'])
    return total


def check_river_corridor(coordinates, bounds):
    """Check if all coordinates fall within Thames corridor."""
    for coord in coordinates:
        if not (bounds['south'] <= coord['lat'] <= bounds['north'] and
                bounds['west'] <= coord['lon'] <= bounds['east']):
            return False
    return True


# VLM prompt for trajectory verification
TRAJECTORY_VERIFICATION_PROMPT = """You are analyzing a sequence of screenshots from an agent creating a path in Google Earth Pro.

The task was to trace the River Thames between Tower Bridge and Westminster Bridge in London.

Look at these screenshots (in chronological order) and determine:

1. GOOGLE_EARTH_VISIBLE: Is Google Earth Pro visible in these screenshots?
2. LONDON_AREA_SHOWN: Do any screenshots show London/Thames area (satellite imagery of a river through a city)?
3. PATH_TOOL_USED: Is there evidence of the path/line tool being used (yellow/white line being drawn, path dialog, or edit mode)?
4. PATH_ON_RIVER: Does a drawn path appear to follow the River Thames (a winding river through London)?
5. MEANINGFUL_WORKFLOW: Do the screenshots show progression (navigation to London → path creation → saving)?

Respond in JSON format:
{
    "google_earth_visible": true/false,
    "london_area_shown": true/false,
    "path_tool_used": true/false,
    "path_on_river": true/false,
    "meaningful_workflow": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see across the frames"
}
"""


def verify_thames_river_path(traj, env_info, task_info):
    """
    Verify Thames River path measurement task.
    
    Uses multiple independent signals:
    1. Programmatic: KML file existence, timestamps, coordinate validation
    2. VLM: Trajectory frames showing actual work
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Get metadata with expected values
    metadata = task_info.get('metadata', {})
    tower_bridge = {
        'lat': metadata.get('tower_bridge_lat', 51.5055),
        'lon': metadata.get('tower_bridge_lon', -0.0754)
    }
    westminster = {
        'lat': metadata.get('westminster_bridge_lat', 51.5007),
        'lon': metadata.get('westminster_bridge_lon', -0.1218)
    }
    coord_tolerance = metadata.get('coordinate_tolerance', 0.005)
    thames_bounds = {
        'north': metadata.get('thames_corridor_north', 51.515),
        'south': metadata.get('thames_corridor_south', 51.495),
        'west': metadata.get('thames_corridor_west', -0.135),
        'east': metadata.get('thames_corridor_east', -0.065)
    }
    min_waypoints = metadata.get('min_waypoints', 8)
    
    feedback_parts = []
    score = 0
    details = {}
    
    # ================================================================
    # Copy result file from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        details['result_loaded'] = True
    except Exception as e:
        logger.error(f"Failed to load result: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read task result: {e}",
            "details": {"error": str(e)}
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # CRITERION 1: KML file exists (15 points)
    # ================================================================
    kml_exists = result.get('kml_exists', False)
    kml_size = result.get('kml_size_bytes', 0)
    
    if kml_exists and kml_size > 100:
        score += 15
        feedback_parts.append(f"✅ KML file exists ({kml_size} bytes)")
        details['kml_exists'] = True
    elif kml_exists:
        score += 5
        feedback_parts.append(f"⚠️ KML file exists but very small ({kml_size} bytes)")
        details['kml_exists'] = True
    else:
        feedback_parts.append("❌ KML file not found at ~/Documents/thames_path.kml")
        details['kml_exists'] = False
        # Early exit if no file
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: File created/modified during task (15 points) - anti-gaming
    # ================================================================
    created_during_task = result.get('kml_created_during_task', False)
    modified_during_task = result.get('kml_modified_during_task', False)
    
    if created_during_task:
        score += 15
        feedback_parts.append("✅ File newly created during task")
        details['created_during_task'] = True
    elif modified_during_task:
        score += 10
        feedback_parts.append("✅ File modified during task")
        details['modified_during_task'] = True
    else:
        feedback_parts.append("⚠️ File may have existed before task")
        details['created_during_task'] = False
    
    # ================================================================
    # CRITERION 3: Valid KML with coordinates (10 points)
    # ================================================================
    coordinate_count = result.get('coordinate_count', 0)
    all_coordinates = result.get('all_coordinates', [])
    
    if coordinate_count > 0 and len(all_coordinates) > 0:
        score += 10
        feedback_parts.append(f"✅ Valid KML with {coordinate_count} coordinates")
        details['valid_kml'] = True
        details['coordinate_count'] = coordinate_count
    else:
        feedback_parts.append("❌ Could not parse coordinates from KML")
        details['valid_kml'] = False
        # Continue but will lose more points
    
    # ================================================================
    # CRITERION 4: Start point near Tower Bridge (15 points)
    # ================================================================
    first_lat = result.get('first_coord_lat', 0)
    first_lon = result.get('first_coord_lon', 0)
    last_lat = result.get('last_coord_lat', 0)
    last_lon = result.get('last_coord_lon', 0)
    
    start_correct = False
    end_correct = False
    
    # Check both directions (path could go either way)
    dist_first_to_tower = haversine_distance(first_lat, first_lon, tower_bridge['lat'], tower_bridge['lon'])
    dist_first_to_westminster = haversine_distance(first_lat, first_lon, westminster['lat'], westminster['lon'])
    dist_last_to_tower = haversine_distance(last_lat, last_lon, tower_bridge['lat'], tower_bridge['lon'])
    dist_last_to_westminster = haversine_distance(last_lat, last_lon, westminster['lat'], westminster['lon'])
    
    details['distances'] = {
        'first_to_tower_km': round(dist_first_to_tower, 3),
        'first_to_westminster_km': round(dist_first_to_westminster, 3),
        'last_to_tower_km': round(dist_last_to_tower, 3),
        'last_to_westminster_km': round(dist_last_to_westminster, 3)
    }
    
    # Allow path in either direction
    if dist_first_to_tower < 0.5:  # Within 500m
        start_correct = True
        score += 15
        feedback_parts.append(f"✅ Path starts near Tower Bridge ({dist_first_to_tower:.2f}km)")
    elif dist_last_to_tower < 0.5:  # Reversed direction
        start_correct = True
        score += 15
        feedback_parts.append(f"✅ Path ends near Tower Bridge ({dist_last_to_tower:.2f}km)")
    else:
        feedback_parts.append(f"❌ Path does not connect to Tower Bridge (closest: {min(dist_first_to_tower, dist_last_to_tower):.2f}km)")
    
    details['start_correct'] = start_correct
    
    # ================================================================
    # CRITERION 5: End point near Westminster Bridge (15 points)
    # ================================================================
    if dist_last_to_westminster < 0.5:
        end_correct = True
        score += 15
        feedback_parts.append(f"✅ Path ends near Westminster Bridge ({dist_last_to_westminster:.2f}km)")
    elif dist_first_to_westminster < 0.5:  # Reversed direction
        end_correct = True
        score += 15
        feedback_parts.append(f"✅ Path starts near Westminster Bridge ({dist_first_to_westminster:.2f}km)")
    else:
        feedback_parts.append(f"❌ Path does not connect to Westminster Bridge (closest: {min(dist_first_to_westminster, dist_last_to_westminster):.2f}km)")
    
    details['end_correct'] = end_correct
    
    # ================================================================
    # CRITERION 6: Sufficient waypoints (15 points)
    # ================================================================
    if coordinate_count >= min_waypoints:
        score += 15
        feedback_parts.append(f"✅ Sufficient waypoints ({coordinate_count} >= {min_waypoints})")
        details['sufficient_waypoints'] = True
    elif coordinate_count >= min_waypoints // 2:
        score += 7
        feedback_parts.append(f"⚠️ Partial waypoints ({coordinate_count} < {min_waypoints})")
        details['sufficient_waypoints'] = False
    else:
        feedback_parts.append(f"❌ Insufficient waypoints ({coordinate_count} < {min_waypoints})")
        details['sufficient_waypoints'] = False
    
    # Calculate path length for info
    if all_coordinates:
        path_length = calculate_path_length(all_coordinates)
        details['path_length_km'] = round(path_length, 2)
        feedback_parts.append(f"ℹ️ Path length: {path_length:.2f} km")
    
    # ================================================================
    # CRITERION 7: VLM trajectory verification (15 points)
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    vlm_score = 0
    
    if query_vlm:
        try:
            # Import trajectory sampling functions
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Get trajectory frames (NOT just final screenshot)
            trajectory_frames = sample_trajectory_frames(traj, n=5)
            final_frame = get_final_screenshot(traj)
            
            frames_to_analyze = []
            if trajectory_frames:
                frames_to_analyze.extend(trajectory_frames)
            if final_frame and final_frame not in frames_to_analyze:
                frames_to_analyze.append(final_frame)
            
            if frames_to_analyze:
                vlm_result = query_vlm(
                    prompt=TRAJECTORY_VERIFICATION_PROMPT,
                    images=frames_to_analyze
                )
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    details['vlm_result'] = parsed
                    
                    vlm_criteria_met = sum([
                        parsed.get('google_earth_visible', False),
                        parsed.get('london_area_shown', False),
                        parsed.get('path_tool_used', False),
                        parsed.get('path_on_river', False),
                        parsed.get('meaningful_workflow', False)
                    ])
                    
                    confidence = parsed.get('confidence', 'low')
                    confidence_multiplier = {'high': 1.0, 'medium': 0.85, 'low': 0.7}.get(confidence, 0.7)
                    
                    vlm_score = int((vlm_criteria_met / 5) * 15 * confidence_multiplier)
                    score += vlm_score
                    
                    if vlm_criteria_met >= 4:
                        feedback_parts.append(f"✅ VLM: Workflow verified ({vlm_criteria_met}/5 criteria, {confidence} confidence)")
                    elif vlm_criteria_met >= 2:
                        feedback_parts.append(f"⚠️ VLM: Partial workflow ({vlm_criteria_met}/5 criteria)")
                    else:
                        feedback_parts.append(f"❌ VLM: Workflow not verified ({vlm_criteria_met}/5 criteria)")
                else:
                    feedback_parts.append("⚠️ VLM query failed")
                    details['vlm_error'] = vlm_result.get('error', 'unknown')
            else:
                feedback_parts.append("⚠️ No trajectory frames available for VLM")
        except ImportError:
            # VLM module not available, give partial credit if other checks passed
            if score >= 55:
                vlm_score = 10
                score += vlm_score
                feedback_parts.append("⚠️ VLM not available, partial credit granted")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback_parts.append(f"⚠️ VLM verification error: {str(e)[:50]}")
            details['vlm_error'] = str(e)
    else:
        # No VLM available, give partial credit if programmatic checks pass
        if score >= 55 and start_correct and end_correct:
            vlm_score = 10
            score += vlm_score
            feedback_parts.append("⚠️ VLM not available, partial credit for strong programmatic verification")
    
    details['vlm_score'] = vlm_score
    
    # ================================================================
    # FINAL DETERMINATION
    # ================================================================
    # Pass requires:
    # 1. Score >= 70
    # 2. Both endpoints correct (or at least one endpoint + file created during task)
    key_criteria_met = (start_correct and end_correct) or \
                       ((start_correct or end_correct) and (created_during_task or modified_during_task))
    
    passed = score >= 70 and key_criteria_met
    
    details['final_score'] = score
    details['key_criteria_met'] = key_criteria_met
    
    # Build final feedback
    status = "✅ PASSED" if passed else "❌ FAILED"
    feedback = f"{status} (Score: {score}/100) | " + " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }