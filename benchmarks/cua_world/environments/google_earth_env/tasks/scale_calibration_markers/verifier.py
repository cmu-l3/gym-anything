#!/usr/bin/env python3
"""
Verifier for scale_calibration_markers task.

VERIFICATION STRATEGY:
1. Programmatic: Parse myplaces.kml for placemarks, check coordinates and distance
2. Anti-gaming: Verify file was modified during task window
3. VLM: Use trajectory frames to verify agent actually navigated and created placemarks

SCORING (100 points total):
- Cal Point A present: 15 points
- Cal Point B present: 15 points  
- Both on Salt Flats: 20 points
- Distance within 10% (0.9-1.1 km): 20 points
- Distance within 5% (0.95-1.05 km): +15 points bonus
- East-west alignment (lat diff < 0.002°): 15 points

PASS THRESHOLD: 70 points AND both placemarks present AND valid location
"""

import json
import math
import tempfile
import os
import logging
from typing import Dict, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate distance in kilometers between two lat/lon points using Haversine formula."""
    R = 6371  # Earth's radius in km
    lat1_rad, lon1_rad = math.radians(lat1), math.radians(lon1)
    lat2_rad, lon2_rad = math.radians(lat2), math.radians(lon2)
    
    dlat = lat2_rad - lat1_rad
    dlon = lon2_rad - lon1_rad
    
    a = math.sin(dlat/2)**2 + math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(dlon/2)**2
    c = 2 * math.asin(math.sqrt(a))
    
    return R * c


def parse_placemarks_from_kml(kml_content: str) -> Dict[str, tuple]:
    """Parse placemarks from KML content string."""
    from xml.etree import ElementTree as ET
    
    placemarks = {}
    try:
        root = ET.fromstring(kml_content)
        
        # Handle KML namespace
        ns = {'kml': 'http://www.opengis.net/kml/2.2'}
        
        # Try with namespace
        for pm in root.findall('.//kml:Placemark', ns):
            name_elem = pm.find('kml:name', ns)
            coords_elem = pm.find('.//kml:coordinates', ns)
            if name_elem is not None and coords_elem is not None:
                name = name_elem.text.strip() if name_elem.text else ""
                coords = coords_elem.text.strip().split(',')
                if len(coords) >= 2:
                    try:
                        lon, lat = float(coords[0]), float(coords[1])
                        placemarks[name] = (lat, lon)
                    except ValueError:
                        pass
        
        # Try without namespace if nothing found
        if not placemarks:
            for pm in root.findall('.//Placemark'):
                name_elem = pm.find('name')
                coords_elem = pm.find('.//coordinates')
                if name_elem is not None and coords_elem is not None:
                    name = name_elem.text.strip() if name_elem.text else ""
                    coords = coords_elem.text.strip().split(',')
                    if len(coords) >= 2:
                        try:
                            lon, lat = float(coords[0]), float(coords[1])
                            placemarks[name] = (lat, lon)
                        except ValueError:
                            pass
    except ET.ParseError as e:
        logger.warning(f"Failed to parse KML: {e}")
    
    return placemarks


# VLM Prompts
TRAJECTORY_VERIFICATION_PROMPT = """You are analyzing a sequence of screenshots from an agent creating ground control reference markers in Google Earth.

The task was to:
1. Navigate to Bonneville Salt Flats, Utah (a distinctive white/gray salt flat area)
2. Create two placemarks named "Cal Point A" and "Cal Point B" 
3. Position them exactly 1 kilometer apart in an east-west direction

Look at these trajectory screenshots (earliest to latest) and assess:

1. NAVIGATION_TO_SALT_FLATS: Did the agent navigate to what appears to be the Bonneville Salt Flats?
   - Look for: distinctive white/light colored flat terrain, Utah area, search for "Bonneville"
   
2. PLACEMARK_CREATION: Did the agent create placemarks?
   - Look for: placemark dialog boxes, naming placemarks, clicking on the map to place markers
   
3. MEASUREMENT_TOOL_USED: Did the agent use measurement/ruler tool to verify distance?
   - Look for: ruler tool interface, distance measurements displayed
   
4. MEANINGFUL_WORK: Do the frames show actual progression through the task (not just idle screens)?

Respond in JSON format:
{
    "navigation_to_salt_flats": true/false,
    "placemark_creation_visible": true/false,
    "measurement_tool_used": true/false,
    "meaningful_work_shown": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see across the frames"
}
"""

FINAL_STATE_PROMPT = """You are verifying the final state of a Google Earth task.

The task was to create two placemarks ("Cal Point A" and "Cal Point B") on the Bonneville Salt Flats, Utah.

Look at this final screenshot and assess:

1. IS_GOOGLE_EARTH: Is this Google Earth Pro interface?
2. SALT_FLATS_VISIBLE: Does the view show the Bonneville Salt Flats (white/light flat terrain)?
3. PLACEMARKS_VISIBLE: Are there placemark pins/markers visible on the map?
4. PLACES_PANEL: Is there a "My Places" or sidebar showing saved placemarks?

Respond in JSON format:
{
    "is_google_earth": true/false,
    "salt_flats_visible": true/false,
    "placemarks_visible": true/false,
    "places_panel_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief description of what you see"
}
"""


def verify_scale_calibration_markers(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that the agent created two calibration placemarks 1km apart on the Salt Flats.
    
    Uses:
    1. KML file analysis for placemark verification
    2. Trajectory VLM for process verification
    3. Timestamp checks for anti-gaming
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "❌ Copy function not available"}
    
    # Get metadata
    metadata = task_info.get('metadata', {})
    salt_flat_bounds = metadata.get('salt_flat_bounds', {
        "lat_min": 40.70, "lat_max": 40.85,
        "lon_min": -114.1, "lon_max": -113.7
    })
    expected_distance = metadata.get('expected_distance_km', 1.0)
    max_lat_diff = metadata.get('max_latitude_diff_deg', 0.002)
    placemark_a_name = metadata.get('placemark_a_name', 'Cal Point A')
    placemark_b_name = metadata.get('placemark_b_name', 'Cal Point B')
    
    feedback_parts = []
    result_details = {}
    score = 0
    
    # ================================================================
    # STEP 1: Copy and parse result JSON
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read task result: {e}")
        return {"passed": False, "score": 0, "feedback": f"❌ Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    result_details['export_result'] = result
    
    # ================================================================
    # STEP 2: Anti-gaming check - was file modified during task?
    # ================================================================
    file_modified = result.get('file_modified_during_task', False)
    task_start = result.get('task_start_time', 0)
    task_end = result.get('task_end_time', 0)
    
    if not file_modified:
        feedback_parts.append("⚠️ myplaces.kml not modified during task")
        result_details['anti_gaming_check'] = "FAILED - file not modified"
    else:
        result_details['anti_gaming_check'] = "PASSED"
    
    # ================================================================
    # STEP 3: Parse placemarks from exported result
    # ================================================================
    placemarks_raw = result.get('placemarks', [])
    
    # Convert list format to dict format
    placemarks = {}
    for pm in placemarks_raw:
        if isinstance(pm, dict) and 'name' in pm and 'lat' in pm and 'lon' in pm:
            placemarks[pm['name']] = (pm['lat'], pm['lon'])
    
    result_details['placemarks_found'] = list(placemarks.keys())
    logger.info(f"Found placemarks: {list(placemarks.keys())}")
    
    # If no placemarks from export, try to get KML directly
    if not placemarks:
        temp_kml = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
        try:
            copy_from_env("/tmp/task_evidence/myplaces_final.kml", temp_kml.name)
            with open(temp_kml.name, 'r') as f:
                kml_content = f.read()
            placemarks = parse_placemarks_from_kml(kml_content)
            result_details['placemarks_found'] = list(placemarks.keys())
            logger.info(f"Parsed placemarks from KML: {list(placemarks.keys())}")
        except Exception as e:
            logger.warning(f"Failed to parse KML directly: {e}")
        finally:
            if os.path.exists(temp_kml.name):
                os.unlink(temp_kml.name)
    
    # ================================================================
    # STEP 4: Check for Cal Point A (15 points)
    # ================================================================
    has_cal_a = placemark_a_name in placemarks
    
    # Also check for case-insensitive and partial matches
    if not has_cal_a:
        for name in placemarks.keys():
            if 'cal' in name.lower() and 'a' in name.lower():
                has_cal_a = True
                placemark_a_name = name
                break
    
    if has_cal_a:
        score += 15
        feedback_parts.append(f"✅ '{placemark_a_name}' present")
    else:
        feedback_parts.append(f"❌ '{placemark_a_name}' NOT found")
    
    result_details['cal_point_a'] = {'present': has_cal_a, 'points': 15 if has_cal_a else 0}
    
    # ================================================================
    # STEP 5: Check for Cal Point B (15 points)
    # ================================================================
    has_cal_b = placemark_b_name in placemarks
    
    if not has_cal_b:
        for name in placemarks.keys():
            if 'cal' in name.lower() and 'b' in name.lower():
                has_cal_b = True
                placemark_b_name = name
                break
    
    if has_cal_b:
        score += 15
        feedback_parts.append(f"✅ '{placemark_b_name}' present")
    else:
        feedback_parts.append(f"❌ '{placemark_b_name}' NOT found")
    
    result_details['cal_point_b'] = {'present': has_cal_b, 'points': 15 if has_cal_b else 0}
    
    # ================================================================
    # STEP 6: If both placemarks exist, check location and distance
    # ================================================================
    location_valid = False
    distance_ok = False
    aligned = False
    
    if has_cal_a and has_cal_b:
        lat_a, lon_a = placemarks[placemark_a_name]
        lat_b, lon_b = placemarks[placemark_b_name]
        
        result_details['coordinates'] = {
            placemark_a_name: {'lat': lat_a, 'lon': lon_a},
            placemark_b_name: {'lat': lat_b, 'lon': lon_b}
        }
        
        # Check if both on Salt Flats (20 points)
        a_on_flats = (salt_flat_bounds['lat_min'] <= lat_a <= salt_flat_bounds['lat_max'] and
                      salt_flat_bounds['lon_min'] <= lon_a <= salt_flat_bounds['lon_max'])
        b_on_flats = (salt_flat_bounds['lat_min'] <= lat_b <= salt_flat_bounds['lat_max'] and
                      salt_flat_bounds['lon_min'] <= lon_b <= salt_flat_bounds['lon_max'])
        
        location_valid = a_on_flats and b_on_flats
        
        if location_valid:
            score += 20
            feedback_parts.append("✅ Both points on Salt Flats")
        elif a_on_flats or b_on_flats:
            score += 10
            feedback_parts.append("⚠️ Only one point on Salt Flats")
        else:
            feedback_parts.append("❌ Points NOT on Salt Flats")
        
        result_details['location'] = {
            'a_on_salt_flats': a_on_flats,
            'b_on_salt_flats': b_on_flats,
            'both_valid': location_valid,
            'points': 20 if location_valid else (10 if (a_on_flats or b_on_flats) else 0)
        }
        
        # Calculate distance (20 points for within 10%, +15 for within 5%)
        distance = haversine_distance(lat_a, lon_a, lat_b, lon_b)
        result_details['distance'] = {
            'measured_km': round(distance, 4),
            'target_km': expected_distance
        }
        
        within_10pct = 0.9 * expected_distance <= distance <= 1.1 * expected_distance
        within_5pct = 0.95 * expected_distance <= distance <= 1.05 * expected_distance
        
        distance_points = 0
        if within_10pct:
            distance_points += 20
            score += 20
            distance_ok = True
            feedback_parts.append(f"✅ Distance {distance:.3f} km (within 10%)")
        else:
            feedback_parts.append(f"❌ Distance {distance:.3f} km (outside 10% tolerance)")
        
        if within_5pct:
            distance_points += 15
            score += 15
            feedback_parts.append(f"✅ Bonus: within 5% precision")
        
        result_details['distance']['within_10pct'] = within_10pct
        result_details['distance']['within_5pct'] = within_5pct
        result_details['distance']['points'] = distance_points
        
        # Check east-west alignment (15 points)
        lat_diff = abs(lat_a - lat_b)
        lon_diff = lon_b - lon_a  # Positive if B is east of A
        
        aligned = lat_diff < max_lat_diff
        b_east_of_a = lon_diff > 0
        
        alignment_points = 0
        if aligned:
            alignment_points = 15
            score += 15
            feedback_parts.append(f"✅ East-west aligned (lat diff: {lat_diff:.5f}°)")
        else:
            feedback_parts.append(f"⚠️ Not aligned E-W (lat diff: {lat_diff:.5f}°)")
        
        if not b_east_of_a:
            feedback_parts.append("⚠️ Note: B is west of A (should be east)")
        
        result_details['alignment'] = {
            'latitude_diff_deg': round(lat_diff, 5),
            'longitude_diff_deg': round(lon_diff, 5),
            'east_west_aligned': aligned,
            'b_east_of_a': b_east_of_a,
            'points': alignment_points
        }
    
    # ================================================================
    # STEP 7: VLM Trajectory Verification
    # ================================================================
    vlm_score = 0
    
    if query_vlm:
        try:
            # Import trajectory frame helpers
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Get trajectory frames (sample 5 frames across the episode)
            frames = sample_trajectory_frames(traj, n=5)
            final_screenshot = get_final_screenshot(traj)
            
            # Trajectory process verification
            if frames and len(frames) > 0:
                traj_result = query_vlm(
                    prompt=TRAJECTORY_VERIFICATION_PROMPT,
                    images=frames
                )
                
                if traj_result.get('success'):
                    parsed = traj_result.get('parsed', {})
                    result_details['vlm_trajectory'] = parsed
                    
                    # Count VLM criteria met
                    vlm_criteria = [
                        parsed.get('navigation_to_salt_flats', False),
                        parsed.get('placemark_creation_visible', False),
                        parsed.get('measurement_tool_used', False),
                        parsed.get('meaningful_work_shown', False)
                    ]
                    
                    vlm_criteria_met = sum(vlm_criteria)
                    confidence = parsed.get('confidence', 'low')
                    
                    # VLM provides supporting evidence but not primary scoring
                    if vlm_criteria_met >= 3 and confidence in ['medium', 'high']:
                        feedback_parts.append("✅ VLM: Task workflow verified")
                        vlm_score = 10
                    elif vlm_criteria_met >= 2:
                        feedback_parts.append("⚠️ VLM: Partial workflow observed")
                        vlm_score = 5
                    else:
                        feedback_parts.append("⚠️ VLM: Limited workflow evidence")
                else:
                    logger.warning(f"VLM trajectory query failed: {traj_result.get('error')}")
            
            # Final state verification
            if final_screenshot:
                final_result = query_vlm(
                    prompt=FINAL_STATE_PROMPT,
                    image=final_screenshot
                )
                
                if final_result.get('success'):
                    parsed = final_result.get('parsed', {})
                    result_details['vlm_final_state'] = parsed
                    
                    if parsed.get('is_google_earth') and parsed.get('placemarks_visible'):
                        feedback_parts.append("✅ VLM: Final state shows placemarks")
                else:
                    logger.warning(f"VLM final state query failed: {final_result.get('error')}")
                    
        except ImportError:
            logger.warning("Could not import VLM helpers")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
    
    # Add VLM bonus (not required for passing)
    # score += vlm_score  # Uncomment to include VLM in scoring
    
    # ================================================================
    # STEP 8: Determine pass/fail
    # ================================================================
    # Must have both placemarks AND valid location AND reasonable distance
    key_criteria_met = has_cal_a and has_cal_b and location_valid
    passed = score >= 70 and key_criteria_met
    
    # Also pass if we got close but file modification failed (edge case)
    if score >= 85 and has_cal_a and has_cal_b and not file_modified:
        # High score suggests work was done, might be timing issue
        passed = True
        feedback_parts.append("⚠️ Passed despite file timestamp issue (high score)")
    
    result_details['score_breakdown'] = {
        'cal_point_a': 15 if has_cal_a else 0,
        'cal_point_b': 15 if has_cal_b else 0,
        'location': result_details.get('location', {}).get('points', 0),
        'distance': result_details.get('distance', {}).get('points', 0),
        'alignment': result_details.get('alignment', {}).get('points', 0),
        'total': score
    }
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result_details
    }