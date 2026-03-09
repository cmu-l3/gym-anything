#!/usr/bin/env python3
"""
Verifier for niagara_falls_width task.

MULTI-SIGNAL VERIFICATION:
1. KML file exists and was created during task (15 points)
2. Four placemarks present (15 points)
3. Placemarks correctly named (15 points)
4. Coordinates in valid Niagara Falls bounding box (20 points)
5. Horseshoe Falls distance measurement reasonable (15 points)
6. American Falls distance measurement reasonable (10 points)
7. Folder organization (5 points)
8. Description with measurements (5 points)

VLM TRAJECTORY VERIFICATION (bonus validation):
- Verify agent navigated to Niagara Falls
- Verify agent used ruler tool / created placemarks
- Verify workflow progression

Pass threshold: 60 points with KML file created and at least 3 valid placemarks
"""

import json
import tempfile
import os
import math
import logging
from typing import Dict, Any, Optional, Tuple, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate distance between two coordinates in meters using Haversine formula."""
    R = 6371000  # Earth radius in meters
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)
    
    a = math.sin(delta_phi/2)**2 + \
        math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    
    return R * c


def find_placemark_by_keywords(placemark_names: List[str], placemark_coords: List[Optional[Dict]], 
                                keywords: List[str]) -> Optional[Dict]:
    """Find a placemark matching all keywords and return its coordinates."""
    for i, name in enumerate(placemark_names):
        if name and all(kw.lower() in name.lower() for kw in keywords):
            if i < len(placemark_coords) and placemark_coords[i]:
                return placemark_coords[i]
    return None


def is_in_bounding_box(lat: float, lon: float, bbox: Dict) -> bool:
    """Check if coordinates are within the Niagara Falls bounding box."""
    return (bbox["min_lat"] <= lat <= bbox["max_lat"] and 
            bbox["min_lon"] <= lon <= bbox["max_lon"])


# VLM Prompts
TRAJECTORY_VERIFICATION_PROMPT = """You are analyzing a sequence of screenshots from an agent using Google Earth Pro to measure Niagara Falls width.

The task requires the agent to:
1. Navigate to Niagara Falls (distinctive horseshoe-shaped waterfall on US/Canada border)
2. Create placemarks at waterfall endpoints
3. Measure the width of Horseshoe Falls and American Falls
4. Organize placemarks in a folder and save as KML

Analyze these trajectory frames (ordered chronologically from earliest to latest) and determine:

1. NAVIGATED_TO_NIAGARA: Did the agent navigate to Niagara Falls? Look for:
   - The distinctive horseshoe-shaped falls
   - Bodies of water (Niagara River, falls)
   - The US/Canada border region near Lake Ontario

2. USED_MEASUREMENT_TOOLS: Did the agent appear to use measurement/placemark tools?
   - Ruler tool visible or being used
   - Placemark creation dialogs
   - Places panel showing new items

3. CREATED_PLACEMARKS: Evidence of placemark creation?
   - Yellow pushpin icons on map
   - Placemark edit dialogs
   - Folder creation in Places panel

4. MEANINGFUL_WORKFLOW: Does the sequence show real task progression?
   - Not just the same screen repeated
   - Shows navigation, then measurement activities

Respond in JSON format:
{
    "navigated_to_niagara": true/false,
    "used_measurement_tools": true/false,
    "created_placemarks": true/false,
    "meaningful_workflow": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see in the trajectory"
}
"""

FINAL_STATE_PROMPT = """You are verifying the final state of a Google Earth Pro session where the agent was asked to measure Niagara Falls width.

Look at this screenshot and determine:

1. IS_GOOGLE_EARTH: Is this Google Earth Pro (satellite imagery interface)?

2. SHOWS_NIAGARA_FALLS: Is Niagara Falls visible? Look for:
   - Horseshoe-shaped waterfall (Canadian/Horseshoe Falls)
   - Smaller linear waterfall (American Falls)
   - Niagara River
   - Green/blue water, white waterfall mist

3. PLACEMARKS_VISIBLE: Are there placemark icons (yellow pushpins) visible on the map?

4. PLACES_PANEL_SHOWS_FOLDER: Can you see a folder structure in the Places panel on the left with measurement-related items?

5. WATERFALL_AREA_IN_VIEW: Is the view centered on the waterfall area (not zoomed out to show all of North America)?

Respond in JSON format:
{
    "is_google_earth": true/false,
    "shows_niagara_falls": true/false,
    "placemarks_visible": true/false,
    "places_panel_shows_items": true/false,
    "waterfall_area_in_view": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief description of what you see"
}
"""


def verify_niagara_falls_width(traj: Dict[str, Any], env_info: Dict[str, Any], 
                                task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that the Niagara Falls width measurement task was completed correctly.
    
    Uses multiple independent signals:
    - Programmatic: KML file analysis, coordinate validation, distance calculation
    - VLM: Trajectory analysis and final state verification
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Get metadata with expected values
    metadata = task_info.get('metadata', {})
    expected_horseshoe = metadata.get('horseshoe_width_m', 670)
    horseshoe_tolerance = metadata.get('horseshoe_tolerance_m', 75)
    expected_american = metadata.get('american_width_m', 260)
    american_tolerance = metadata.get('american_tolerance_m', 60)
    bounding_box = metadata.get('bounding_box', {
        "min_lat": 43.07, "max_lat": 43.09,
        "min_lon": -79.08, "max_lon": -79.06
    })
    
    feedback_parts = []
    score = 0
    result_details = {}
    
    # ================================================================
    # STEP 1: Copy and parse task result from container
    # ================================================================
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read task result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
    
    result_details['export_data'] = result
    
    # ================================================================
    # CRITERION 1: KML file exists and was created during task (15 pts)
    # ================================================================
    output_exists = result.get('output_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    kml_valid = result.get('kml_valid', False)
    
    if output_exists and kml_valid and file_created_during_task:
        score += 15
        feedback_parts.append("✅ KML file created during task")
    elif output_exists and kml_valid:
        score += 8
        feedback_parts.append("⚠️ KML file exists but may predate task")
    elif output_exists:
        score += 5
        feedback_parts.append("⚠️ KML file exists but may be invalid")
    else:
        feedback_parts.append("❌ KML file not found")
        # Continue to check other criteria for partial credit
    
    # ================================================================
    # CRITERION 2: Four placemarks present (15 pts)
    # ================================================================
    num_placemarks = result.get('num_placemarks', 0)
    
    if num_placemarks >= 4:
        score += 15
        feedback_parts.append(f"✅ {num_placemarks} placemarks found")
    elif num_placemarks >= 3:
        score += 11
        feedback_parts.append(f"⚠️ {num_placemarks}/4 placemarks found")
    elif num_placemarks >= 2:
        score += 7
        feedback_parts.append(f"⚠️ {num_placemarks}/4 placemarks found")
    elif num_placemarks >= 1:
        score += 4
        feedback_parts.append(f"⚠️ Only {num_placemarks} placemark found")
    else:
        feedback_parts.append("❌ No placemarks found")
    
    result_details['num_placemarks'] = num_placemarks
    
    # ================================================================
    # CRITERION 3: Placemarks correctly named (15 pts)
    # ================================================================
    placemark_names = result.get('placemark_names', [])
    expected_keywords = [
        ["horseshoe", "west"],
        ["horseshoe", "east"],
        ["american", "south"],
        ["american", "north"]
    ]
    
    named_correctly = 0
    for keywords in expected_keywords:
        for name in placemark_names:
            if name and all(kw.lower() in name.lower() for kw in keywords):
                named_correctly += 1
                break
    
    naming_points = int(15 * named_correctly / 4)
    score += naming_points
    
    if named_correctly == 4:
        feedback_parts.append("✅ All placemarks correctly named")
    elif named_correctly > 0:
        feedback_parts.append(f"⚠️ {named_correctly}/4 placemarks correctly named")
    else:
        feedback_parts.append("❌ Placemark names don't match expected pattern")
    
    result_details['named_correctly'] = named_correctly
    
    # ================================================================
    # CRITERION 4: Coordinates in valid bounding box (20 pts)
    # ================================================================
    placemark_coords = result.get('placemark_coords', [])
    valid_coords = 0
    
    for coord in placemark_coords:
        if coord and 'lat' in coord and 'lon' in coord:
            if is_in_bounding_box(coord['lat'], coord['lon'], bounding_box):
                valid_coords += 1
    
    if num_placemarks > 0:
        coord_points = int(20 * valid_coords / max(num_placemarks, 4))
    else:
        coord_points = 0
    score += coord_points
    
    if valid_coords >= 4:
        feedback_parts.append("✅ All coordinates in Niagara Falls area")
    elif valid_coords > 0:
        feedback_parts.append(f"⚠️ {valid_coords}/{num_placemarks} coordinates valid")
    else:
        feedback_parts.append("❌ No coordinates in valid area")
    
    result_details['valid_coordinates'] = valid_coords
    
    # ================================================================
    # CRITERION 5: Horseshoe Falls distance measurement (15 pts)
    # ================================================================
    horseshoe_west = find_placemark_by_keywords(placemark_names, placemark_coords, 
                                                 ["horseshoe", "west"])
    horseshoe_east = find_placemark_by_keywords(placemark_names, placemark_coords, 
                                                 ["horseshoe", "east"])
    
    horseshoe_dist = None
    if horseshoe_west and horseshoe_east:
        horseshoe_dist = haversine_distance(
            horseshoe_west['lat'], horseshoe_west['lon'],
            horseshoe_east['lat'], horseshoe_east['lon']
        )
        result_details['horseshoe_distance_m'] = round(horseshoe_dist, 1)
        
        min_expected = expected_horseshoe - horseshoe_tolerance
        max_expected = expected_horseshoe + horseshoe_tolerance
        
        if min_expected <= horseshoe_dist <= max_expected:
            score += 15
            feedback_parts.append(f"✅ Horseshoe Falls: {horseshoe_dist:.0f}m (expected ~{expected_horseshoe}m)")
        elif 500 <= horseshoe_dist <= 900:
            score += 8
            feedback_parts.append(f"⚠️ Horseshoe Falls: {horseshoe_dist:.0f}m (outside tolerance)")
        else:
            feedback_parts.append(f"❌ Horseshoe Falls: {horseshoe_dist:.0f}m (far from expected)")
    else:
        feedback_parts.append("❌ Missing Horseshoe Falls endpoints")
    
    # ================================================================
    # CRITERION 6: American Falls distance measurement (10 pts)
    # ================================================================
    american_south = find_placemark_by_keywords(placemark_names, placemark_coords, 
                                                 ["american", "south"])
    american_north = find_placemark_by_keywords(placemark_names, placemark_coords, 
                                                 ["american", "north"])
    
    american_dist = None
    if american_south and american_north:
        american_dist = haversine_distance(
            american_south['lat'], american_south['lon'],
            american_north['lat'], american_north['lon']
        )
        result_details['american_distance_m'] = round(american_dist, 1)
        
        min_expected = expected_american - american_tolerance
        max_expected = expected_american + american_tolerance
        
        if min_expected <= american_dist <= max_expected:
            score += 10
            feedback_parts.append(f"✅ American Falls: {american_dist:.0f}m (expected ~{expected_american}m)")
        elif 150 <= american_dist <= 400:
            score += 5
            feedback_parts.append(f"⚠️ American Falls: {american_dist:.0f}m (outside tolerance)")
        else:
            feedback_parts.append(f"❌ American Falls: {american_dist:.0f}m (far from expected)")
    else:
        feedback_parts.append("❌ Missing American Falls endpoints")
    
    # ================================================================
    # CRITERION 7: Folder organization (5 pts)
    # ================================================================
    has_folder = result.get('has_folder', False)
    folder_name = result.get('folder_name', '').lower()
    
    if has_folder and ('niagara' in folder_name or 'measurement' in folder_name):
        score += 5
        feedback_parts.append("✅ Folder organization correct")
    elif has_folder:
        score += 3
        feedback_parts.append("⚠️ Folder exists but name doesn't match")
    else:
        feedback_parts.append("❌ No folder organization")
    
    # ================================================================
    # CRITERION 8: Description with measurements (5 pts)
    # ================================================================
    has_description = result.get('has_description', False)
    folder_desc = result.get('folder_description', '').lower()
    
    # Check if description contains numbers (likely measurements)
    has_measurements_in_desc = has_description and any(c.isdigit() for c in folder_desc)
    
    if has_measurements_in_desc and ('m' in folder_desc or 'meter' in folder_desc or 'width' in folder_desc):
        score += 5
        feedback_parts.append("✅ Description includes measurements")
    elif has_description:
        score += 2
        feedback_parts.append("⚠️ Description exists but missing measurement values")
    else:
        feedback_parts.append("❌ No description with measurements")
    
    # ================================================================
    # VLM VERIFICATION (Trajectory Analysis)
    # ================================================================
    vlm_score_bonus = 0
    
    if query_vlm:
        try:
            # Import VLM utilities
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Get trajectory frames for process verification
            trajectory_frames = sample_trajectory_frames(traj, n=5)
            final_screenshot = get_final_screenshot(traj)
            
            if trajectory_frames and len(trajectory_frames) >= 2:
                # Verify trajectory shows proper workflow
                traj_result = query_vlm(
                    prompt=TRAJECTORY_VERIFICATION_PROMPT,
                    images=trajectory_frames
                )
                
                if traj_result.get('success'):
                    parsed = traj_result.get('parsed', {})
                    result_details['trajectory_vlm'] = parsed
                    
                    traj_criteria = sum([
                        parsed.get('navigated_to_niagara', False),
                        parsed.get('used_measurement_tools', False),
                        parsed.get('created_placemarks', False),
                        parsed.get('meaningful_workflow', False)
                    ])
                    
                    if traj_criteria >= 3:
                        vlm_score_bonus += 5
                        feedback_parts.append("✅ VLM: Trajectory shows proper workflow")
                    elif traj_criteria >= 2:
                        vlm_score_bonus += 3
                        feedback_parts.append("⚠️ VLM: Partial workflow evidence")
                    else:
                        feedback_parts.append("❌ VLM: Workflow not clearly visible")
            
            # Verify final state
            if final_screenshot:
                final_result = query_vlm(
                    prompt=FINAL_STATE_PROMPT,
                    image=final_screenshot
                )
                
                if final_result.get('success'):
                    parsed = final_result.get('parsed', {})
                    result_details['final_state_vlm'] = parsed
                    
                    if (parsed.get('is_google_earth', False) and 
                        parsed.get('shows_niagara_falls', False)):
                        vlm_score_bonus += 3
                        feedback_parts.append("✅ VLM: Final state shows Niagara Falls")
                    elif parsed.get('is_google_earth', False):
                        vlm_score_bonus += 1
                        feedback_parts.append("⚠️ VLM: Google Earth visible but location unclear")
                    
        except ImportError:
            logger.warning("VLM utilities not available, skipping VLM verification")
            feedback_parts.append("ℹ️ VLM verification skipped (utilities not available)")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback_parts.append(f"ℹ️ VLM verification error: {str(e)[:50]}")
    
    # Add VLM bonus (capped at additional points, don't exceed 100)
    score = min(score + vlm_score_bonus, 100)
    result_details['vlm_bonus'] = vlm_score_bonus
    
    # ================================================================
    # FINAL SCORING AND PASS/FAIL DETERMINATION
    # ================================================================
    result_details['score_breakdown'] = {
        'kml_file': 15 if (output_exists and file_created_during_task and kml_valid) else 0,
        'placemarks': min(15, int(15 * num_placemarks / 4)),
        'naming': naming_points,
        'coordinates': coord_points,
        'horseshoe': 15 if (horseshoe_dist and abs(horseshoe_dist - expected_horseshoe) <= horseshoe_tolerance) else 0,
        'american': 10 if (american_dist and abs(american_dist - expected_american) <= american_tolerance) else 0,
        'folder': 5 if has_folder else 0,
        'description': 5 if has_measurements_in_desc else 0,
        'vlm_bonus': vlm_score_bonus
    }
    
    # Key criteria for passing:
    # - File was created during task (not pre-existing)
    # - At least 3 placemarks with valid coordinates
    key_criteria_met = (
        file_created_during_task and 
        output_exists and 
        num_placemarks >= 3 and 
        valid_coords >= 3
    )
    
    passed = score >= 60 and key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result_details
    }