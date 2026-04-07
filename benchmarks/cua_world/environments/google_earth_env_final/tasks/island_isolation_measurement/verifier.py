#!/usr/bin/env python3
"""
Verifier for island_isolation_measurement task.

TASK: Measure the distance from Pitcairn Island to Totegegie Airport
      and save the measurement path with proper name.

VERIFICATION STRATEGY (Multi-signal, anti-gaming):
1. Path exists in myplaces.kml (15 pts)
2. Path was created DURING task - timestamp check (15 pts)
3. Path start coordinates near Pitcairn (20 pts)
4. Path end coordinates near Totegegie (20 pts)
5. Distance measurement accuracy (15 pts)
6. Path properly named (10 pts)
7. VLM trajectory verification (5 pts bonus)

Pass threshold: 70 points AND both start/end coordinates correct
"""

import json
import tempfile
import os
import math
import logging
from typing import Dict, Any, List, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ================================================================
# CONSTANTS - From task metadata
# ================================================================

PITCAIRN_LAT = -25.067
PITCAIRN_LON = -130.100
TOTEGEGIE_LAT = -23.080
TOTEGEGIE_LON = -134.889
COORDINATE_TOLERANCE_KM = 50
EXPECTED_DISTANCE_MIN_KM = 400
EXPECTED_DISTANCE_MAX_KM = 600


# ================================================================
# HELPER FUNCTIONS
# ================================================================

def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate great-circle distance between two points in km."""
    R = 6371  # Earth's radius in km
    
    lat1, lon1, lat2, lon2 = map(math.radians, [lat1, lon1, lat2, lon2])
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    
    a = math.sin(dlat/2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon/2)**2
    c = 2 * math.asin(math.sqrt(a))
    
    return R * c


def check_coordinate_match(actual_lat: float, actual_lon: float, 
                           expected_lat: float, expected_lon: float,
                           tolerance_km: float) -> tuple:
    """Check if coordinates are within tolerance."""
    distance = haversine_distance(actual_lat, actual_lon, expected_lat, expected_lon)
    return distance <= tolerance_km, distance


def find_matching_path(paths: List[Dict], metadata: Dict) -> Optional[Dict]:
    """Find a path that matches Pitcairn-Totegegie route."""
    tolerance = metadata.get('coordinate_tolerance_km', COORDINATE_TOLERANCE_KM)
    
    for path in paths:
        start_lat = path.get('start_lat', 0)
        start_lon = path.get('start_lon', 0)
        end_lat = path.get('end_lat', 0)
        end_lon = path.get('end_lon', 0)
        
        # Check forward direction: Pitcairn -> Totegegie
        start_ok, start_dist = check_coordinate_match(
            start_lat, start_lon, PITCAIRN_LAT, PITCAIRN_LON, tolerance
        )
        end_ok, end_dist = check_coordinate_match(
            end_lat, end_lon, TOTEGEGIE_LAT, TOTEGEGIE_LON, tolerance
        )
        
        if start_ok and end_ok:
            path['direction'] = 'forward'
            path['start_distance_km'] = start_dist
            path['end_distance_km'] = end_dist
            return path
        
        # Check reverse direction: Totegegie -> Pitcairn
        start_ok_rev, start_dist_rev = check_coordinate_match(
            start_lat, start_lon, TOTEGEGIE_LAT, TOTEGEGIE_LON, tolerance
        )
        end_ok_rev, end_dist_rev = check_coordinate_match(
            end_lat, end_lon, PITCAIRN_LAT, PITCAIRN_LON, tolerance
        )
        
        if start_ok_rev and end_ok_rev:
            path['direction'] = 'reverse'
            path['start_distance_km'] = end_dist_rev  # Swap for reporting
            path['end_distance_km'] = start_dist_rev
            return path
    
    return None


# ================================================================
# VLM VERIFICATION
# ================================================================

VLM_TRAJECTORY_PROMPT = """You are analyzing a sequence of screenshots from an agent measuring distance in Google Earth.

The agent's task was to:
1. Navigate to Pitcairn Island (remote South Pacific)
2. Use the ruler/measure tool to create a path to Totegegie Airport
3. Save the measurement path

Look at these trajectory screenshots and assess:
1. NAVIGATION_TO_REMOTE_LOCATION: Do any frames show navigation to a remote Pacific Ocean area or small islands?
2. RULER_TOOL_USED: Is there evidence of the ruler/measure tool being activated (ruler window, measurement line)?
3. PATH_DRAWN_OVER_OCEAN: Is there a line/path drawn over open ocean between islands?
4. SAVE_DIALOG_OR_MY_PLACES: Is there evidence of saving (right-click menu, save dialog, My Places panel)?

Respond in JSON format:
{
    "navigation_to_remote_location": true/false,
    "ruler_tool_used": true/false,
    "path_drawn_over_ocean": true/false,
    "save_action_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see in the trajectory"
}
"""


def verify_via_vlm(traj: Dict, query_vlm) -> Dict:
    """Verify task completion using trajectory screenshots."""
    if not query_vlm:
        return {"success": False, "error": "VLM not available"}
    
    try:
        # Import trajectory sampling utilities
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        # Get trajectory frames (sample across the episode)
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        
        if not frames and not final:
            return {"success": False, "error": "No screenshots available"}
        
        # Combine frames for analysis
        all_frames = frames if frames else []
        if final and final not in all_frames:
            all_frames.append(final)
        
        if not all_frames:
            return {"success": False, "error": "No valid frames"}
        
        # Query VLM with trajectory
        result = query_vlm(
            prompt=VLM_TRAJECTORY_PROMPT,
            images=all_frames
        )
        
        if not result.get("success"):
            return {"success": False, "error": result.get("error", "VLM query failed")}
        
        parsed = result.get("parsed", {})
        
        # Calculate VLM score
        vlm_criteria = [
            parsed.get("navigation_to_remote_location", False),
            parsed.get("ruler_tool_used", False),
            parsed.get("path_drawn_over_ocean", False),
            parsed.get("save_action_visible", False)
        ]
        
        criteria_met = sum(vlm_criteria)
        confidence = parsed.get("confidence", "low")
        
        return {
            "success": True,
            "criteria_met": criteria_met,
            "total_criteria": 4,
            "confidence": confidence,
            "parsed": parsed
        }
        
    except ImportError:
        logger.warning("VLM utilities not available, skipping trajectory verification")
        return {"success": False, "error": "VLM utilities not imported"}
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        return {"success": False, "error": str(e)}


# ================================================================
# MAIN VERIFICATION FUNCTION
# ================================================================

def verify_island_isolation_measurement(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that the agent measured distance from Pitcairn to Totegegie and saved the path.
    
    Uses MULTIPLE INDEPENDENT SIGNALS to prevent gaming.
    
    Args:
        traj: Trajectory data from the agent
        env_info: Environment info including copy_from_env function
        task_info: Task metadata
    
    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
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
    feedback_parts = []
    details = {}
    score = 0
    
    # ================================================================
    # STEP 1: Copy result file from container
    # ================================================================
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result file: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Failed to read task result: {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
    
    details['result_data'] = result
    
    # ================================================================
    # CRITERION 1: myplaces.kml exists with paths (15 points)
    # ================================================================
    myplaces_exists = result.get('myplaces_exists', False)
    path_count = result.get('path_count', 0)
    paths = result.get('paths', [])
    
    if myplaces_exists and path_count > 0:
        score += 15
        feedback_parts.append(f"✅ myplaces.kml exists with {path_count} path(s)")
    elif myplaces_exists:
        score += 5
        feedback_parts.append("⚠️ myplaces.kml exists but no paths found")
    else:
        feedback_parts.append("❌ myplaces.kml not found")
    
    # ================================================================
    # CRITERION 2: File was modified DURING task (15 points) - Anti-gaming
    # ================================================================
    file_modified = result.get('file_modified_during_task', False)
    hash_changed = result.get('hash_changed', False)
    new_paths_added = result.get('new_paths_added', False)
    
    if file_modified and (hash_changed or new_paths_added):
        score += 15
        feedback_parts.append("✅ Path created during task (timestamp verified)")
    elif file_modified:
        score += 10
        feedback_parts.append("⚠️ File modified but unclear if new path added")
    else:
        feedback_parts.append("❌ No file modification detected during task")
    
    details['file_modified'] = file_modified
    details['new_paths_added'] = new_paths_added
    
    # ================================================================
    # FIND MATCHING PATH
    # ================================================================
    matching_path = find_matching_path(paths, metadata)
    details['matching_path'] = matching_path
    
    start_coords_correct = False
    end_coords_correct = False
    
    if matching_path:
        # ================================================================
        # CRITERION 3: Start coordinates near Pitcairn (20 points)
        # ================================================================
        start_dist = matching_path.get('start_distance_km', 999)
        if start_dist <= COORDINATE_TOLERANCE_KM:
            score += 20
            start_coords_correct = True
            feedback_parts.append(f"✅ Path starts near Pitcairn ({start_dist:.1f} km away)")
        else:
            feedback_parts.append(f"❌ Path start too far from Pitcairn ({start_dist:.1f} km)")
        
        # ================================================================
        # CRITERION 4: End coordinates near Totegegie (20 points)
        # ================================================================
        end_dist = matching_path.get('end_distance_km', 999)
        if end_dist <= COORDINATE_TOLERANCE_KM:
            score += 20
            end_coords_correct = True
            feedback_parts.append(f"✅ Path ends near Totegegie ({end_dist:.1f} km away)")
        else:
            feedback_parts.append(f"❌ Path end too far from Totegegie ({end_dist:.1f} km)")
        
        # ================================================================
        # CRITERION 5: Distance measurement accuracy (15 points)
        # ================================================================
        measured_distance = matching_path.get('distance_km', 0)
        if EXPECTED_DISTANCE_MIN_KM <= measured_distance <= EXPECTED_DISTANCE_MAX_KM:
            score += 15
            feedback_parts.append(f"✅ Distance correct ({measured_distance:.1f} km)")
        elif measured_distance > 0:
            # Partial credit for reasonable distance
            if 300 <= measured_distance <= 700:
                score += 7
                feedback_parts.append(f"⚠️ Distance slightly off ({measured_distance:.1f} km, expected 400-600)")
            else:
                feedback_parts.append(f"❌ Distance incorrect ({measured_distance:.1f} km, expected 400-600)")
        else:
            feedback_parts.append("❌ Could not calculate distance")
        
        details['measured_distance_km'] = measured_distance
        
        # ================================================================
        # CRITERION 6: Path properly named (10 points)
        # ================================================================
        path_name = matching_path.get('name', '').lower()
        has_pitcairn = 'pitcairn' in path_name
        has_totegegie = 'totegegie' in path_name
        
        if has_pitcairn and has_totegegie:
            score += 10
            feedback_parts.append(f"✅ Path properly named: '{matching_path.get('name')}'")
        elif has_pitcairn or has_totegegie:
            score += 5
            feedback_parts.append(f"⚠️ Path partially named: '{matching_path.get('name')}'")
        else:
            feedback_parts.append(f"⚠️ Path name doesn't include location names: '{matching_path.get('name')}'")
        
        details['path_name'] = matching_path.get('name')
        
    else:
        feedback_parts.append("❌ No path found connecting Pitcairn and Totegegie areas")
        
        # Try to give feedback on what paths exist
        if paths:
            path_names = [p.get('name', 'Unnamed') for p in paths[:3]]
            feedback_parts.append(f"   Found paths: {', '.join(path_names)}")
    
    # ================================================================
    # CRITERION 7: VLM trajectory verification (5 points bonus)
    # ================================================================
    if query_vlm:
        vlm_result = verify_via_vlm(traj, query_vlm)
        details['vlm_result'] = vlm_result
        
        if vlm_result.get('success'):
            criteria_met = vlm_result.get('criteria_met', 0)
            if criteria_met >= 3:
                score += 5
                feedback_parts.append(f"✅ VLM confirms workflow ({criteria_met}/4 criteria)")
            elif criteria_met >= 2:
                score += 3
                feedback_parts.append(f"⚠️ VLM partial confirmation ({criteria_met}/4 criteria)")
            else:
                feedback_parts.append(f"⚠️ VLM low confidence ({criteria_met}/4 criteria)")
        else:
            feedback_parts.append(f"⚠️ VLM verification unavailable: {vlm_result.get('error', 'unknown')}")
    
    # ================================================================
    # DETERMINE PASS/FAIL
    # ================================================================
    # Must have 70+ points AND correct coordinates for both endpoints
    key_criteria_met = start_coords_correct and end_coords_correct
    passed = score >= 70 and key_criteria_met
    
    # Cap score at 100
    score = min(score, 100)
    
    # Additional check: Google Earth should be running
    ge_running = result.get('google_earth_running', False)
    if not ge_running:
        feedback_parts.append("⚠️ Google Earth was not running at export")
    
    details['start_coords_correct'] = start_coords_correct
    details['end_coords_correct'] = end_coords_correct
    details['key_criteria_met'] = key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }


# ================================================================
# STANDALONE TESTING
# ================================================================

if __name__ == "__main__":
    # Test with mock data
    print("Verifier module loaded successfully")
    print(f"Expected Pitcairn coordinates: {PITCAIRN_LAT}, {PITCAIRN_LON}")
    print(f"Expected Totegegie coordinates: {TOTEGEGIE_LAT}, {TOTEGEGIE_LON}")
    print(f"Expected distance: {EXPECTED_DISTANCE_MIN_KM}-{EXPECTED_DISTANCE_MAX_KM} km")
    
    # Calculate actual expected distance
    actual_distance = haversine_distance(PITCAIRN_LAT, PITCAIRN_LON, TOTEGEGIE_LAT, TOTEGEGIE_LON)
    print(f"Calculated distance: {actual_distance:.1f} km")