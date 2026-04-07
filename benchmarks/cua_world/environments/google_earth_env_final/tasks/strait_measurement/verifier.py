#!/usr/bin/env python3
"""
Verifier for Strait of Gibraltar measurement task.

VERIFICATION STRATEGY:
1. KML file analysis - check for saved measurement paths (25 points)
2. Coordinate validation - endpoints in correct geographic areas (30 points)
3. Distance validation - measurement is reasonable (20 points)
4. Timestamp verification - file modified during task (10 points)
5. VLM trajectory verification - shows ruler tool usage (15 points)

Pass threshold: 60 points with coordinate validation achieved
"""

import json
import math
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# Geographic bounds for validation
TARIFA_BOUNDS = {
    'lat_min': 35.90, 'lat_max': 36.15,
    'lon_min': -5.80, 'lon_max': -5.45
}
MOROCCO_BOUNDS = {
    'lat_min': 35.75, 'lat_max': 36.00,
    'lon_min': -5.70, 'lon_max': -5.35
}


def haversine_distance(lat1, lon1, lat2, lon2):
    """Calculate distance between two points in kilometers."""
    R = 6371  # Earth's radius in km
    lat1, lon1, lat2, lon2 = map(math.radians, [lat1, lon1, lat2, lon2])
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    a = math.sin(dlat/2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon/2)**2
    c = 2 * math.asin(math.sqrt(a))
    return R * c


def point_in_bounds(lat, lon, bounds):
    """Check if a point is within geographic bounds."""
    return (bounds['lat_min'] <= lat <= bounds['lat_max'] and
            bounds['lon_min'] <= lon <= bounds['lon_max'])


def is_in_strait_region(lat, lon):
    """Check if point is in the general Strait of Gibraltar region."""
    return (35.7 <= lat <= 36.2 and -6.0 <= lon <= -5.2)


def analyze_paths(paths_data, metadata):
    """Analyze extracted paths to find valid strait crossing measurement."""
    if not paths_data:
        return None, []
    
    expected_dist_min = metadata.get('expected_distance_km_min', 13.0)
    expected_dist_max = metadata.get('expected_distance_km_max', 16.5)
    save_name = metadata.get('save_name', 'Gibraltar').lower()
    
    best_path = None
    best_score = 0
    analysis_notes = []
    
    for path in paths_data:
        coords = path.get('coordinates', [])
        name = path.get('name', '')
        
        if len(coords) < 2:
            continue
        
        # Get endpoints
        start = coords[0]
        end = coords[-1]
        start_lat, start_lon = start.get('lat', 0), start.get('lon', 0)
        end_lat, end_lon = end.get('lat', 0), end.get('lon', 0)
        
        path_score = 0
        path_notes = [f"Analyzing path '{name}'"]
        
        # Check if endpoints are in strait region
        start_in_region = is_in_strait_region(start_lat, start_lon)
        end_in_region = is_in_strait_region(end_lat, end_lon)
        
        if not (start_in_region and end_in_region):
            path_notes.append(f"  - Not in strait region")
            continue
        
        # Check endpoint locations
        start_in_tarifa = point_in_bounds(start_lat, start_lon, TARIFA_BOUNDS)
        start_in_morocco = point_in_bounds(start_lat, start_lon, MOROCCO_BOUNDS)
        end_in_tarifa = point_in_bounds(end_lat, end_lon, TARIFA_BOUNDS)
        end_in_morocco = point_in_bounds(end_lat, end_lon, MOROCCO_BOUNDS)
        
        # Valid crossing: one end in Europe, other in Africa
        valid_crossing = (
            (start_in_tarifa and end_in_morocco) or
            (start_in_morocco and end_in_tarifa)
        )
        
        if valid_crossing:
            path_score += 30
            path_notes.append(f"  - Valid crossing: Europe <-> Africa endpoints")
        elif start_in_tarifa or end_in_tarifa:
            path_score += 15
            path_notes.append(f"  - Partial: European endpoint found")
        elif start_in_morocco or end_in_morocco:
            path_score += 15
            path_notes.append(f"  - Partial: African endpoint found")
        else:
            path_notes.append(f"  - Endpoints not in expected areas")
            path_notes.append(f"    Start: ({start_lat:.4f}, {start_lon:.4f})")
            path_notes.append(f"    End: ({end_lat:.4f}, {end_lon:.4f})")
        
        # Calculate and check distance
        distance = haversine_distance(start_lat, start_lon, end_lat, end_lon)
        path_notes.append(f"  - Distance: {distance:.2f} km")
        
        if expected_dist_min <= distance <= expected_dist_max:
            path_score += 20
            path_notes.append(f"  - Distance in expected range ({expected_dist_min}-{expected_dist_max} km)")
        elif 10 <= distance <= 20:
            path_score += 10
            path_notes.append(f"  - Distance roughly plausible")
        else:
            path_notes.append(f"  - Distance outside expected range")
        
        # Check name
        name_lower = name.lower()
        if save_name in name_lower or 'strait' in name_lower or 'crossing' in name_lower:
            path_score += 10
            path_notes.append(f"  - Name matches expected pattern")
        
        path_notes.append(f"  - Path score: {path_score}")
        analysis_notes.extend(path_notes)
        
        if path_score > best_score:
            best_score = path_score
            best_path = {
                'name': name,
                'start': {'lat': start_lat, 'lon': start_lon},
                'end': {'lat': end_lat, 'lon': end_lon},
                'distance_km': distance,
                'score': path_score,
                'valid_crossing': valid_crossing
            }
    
    return best_path, analysis_notes


# VLM prompt for trajectory verification
VLM_TRAJECTORY_PROMPT = """Analyze these screenshots from a Google Earth session where the agent should measure the Strait of Gibraltar using the Ruler tool.

Look for evidence of:

1. NAVIGATION TO STRAIT (20 points):
   - Is the view showing a narrow water channel between two landmasses?
   - Can you see both European (Spain) and African (Morocco) coastlines?
   - Is this the Strait of Gibraltar area (between Spain and Morocco)?

2. RULER TOOL USAGE (40 points):
   - Is the Ruler dialog/window visible in any screenshot?
   - Is there a measurement line drawn across water between two shores?
   - Does the ruler show a distance measurement (approximately 14-15 km or 8-9 miles)?

3. MEASUREMENT SAVED (20 points):
   - Is there evidence of saving the measurement (Save button, naming dialog)?
   - Does "My Places" sidebar show a new path/measurement entry?

4. WORKFLOW PROGRESSION (20 points):
   - Do the screenshots show logical progression (navigate → zoom → measure → save)?
   - Is there evidence of intentional, task-focused actions?

Respond in JSON format:
{
    "navigation_score": <0-20>,
    "ruler_tool_score": <0-40>,
    "save_score": <0-20>,
    "workflow_score": <0-20>,
    "total_score": <0-100>,
    "strait_visible": true/false,
    "ruler_dialog_visible": true/false,
    "measurement_line_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": ["list of key observations"]
}
"""


def verify_strait_measurement(traj, env_info, task_info):
    """
    Verify that the agent measured the Strait of Gibraltar correctly.
    
    Uses multiple verification signals:
    1. KML file analysis for saved measurements
    2. Coordinate validation for correct endpoints
    3. Distance validation
    4. Timestamp checks for anti-gaming
    5. VLM trajectory verification
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    feedback_parts = []
    score = 0
    details = {}
    
    # ================================================================
    # STEP 1: Copy and parse task result JSON
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
    # STEP 2: Timestamp/Anti-gaming checks (10 points)
    # ================================================================
    task_start = result.get('task_start', 0)
    myplaces_modified = result.get('myplaces_modified', False)
    paths_added = result.get('paths_added', 0)
    
    if myplaces_modified and paths_added > 0:
        score += 10
        feedback_parts.append("✅ KML file modified during task with new paths")
        details['timestamp_valid'] = True
    elif myplaces_modified:
        score += 5
        feedback_parts.append("⚠️ KML file modified but no new paths detected")
        details['timestamp_valid'] = True
    else:
        feedback_parts.append("❌ KML file not modified during task")
        details['timestamp_valid'] = False
    
    # ================================================================
    # STEP 3: Analyze paths from KML (25 points for file, 30 for coords)
    # ================================================================
    paths_data = result.get('paths_data', [])
    details['paths_found'] = len(paths_data) if paths_data else 0
    
    if paths_data and len(paths_data) > 0:
        score += 10
        feedback_parts.append(f"✅ Found {len(paths_data)} path(s) in myplaces.kml")
        
        # Analyze paths for valid strait crossing
        best_path, analysis_notes = analyze_paths(paths_data, metadata)
        details['analysis_notes'] = analysis_notes
        
        if best_path:
            details['best_path'] = best_path
            
            # Coordinate validation (30 points)
            if best_path.get('valid_crossing', False):
                score += 30
                feedback_parts.append(f"✅ Valid strait crossing measurement found")
                feedback_parts.append(f"   Distance: {best_path['distance_km']:.2f} km")
            else:
                # Partial credit for being in the region
                path_score = best_path.get('score', 0)
                partial_pts = min(15, path_score // 2)
                score += partial_pts
                feedback_parts.append(f"⚠️ Path found but endpoints not precisely positioned ({partial_pts} pts)")
            
            # Distance validation (20 points)
            expected_min = metadata.get('expected_distance_km_min', 13.0)
            expected_max = metadata.get('expected_distance_km_max', 16.5)
            distance = best_path.get('distance_km', 0)
            
            if expected_min <= distance <= expected_max:
                score += 20
                feedback_parts.append(f"✅ Distance {distance:.2f} km is in expected range")
            elif 10 <= distance <= 20:
                score += 10
                feedback_parts.append(f"⚠️ Distance {distance:.2f} km is roughly plausible")
            else:
                feedback_parts.append(f"❌ Distance {distance:.2f} km outside expected range")
            
            # Name check (5 points)
            name = best_path.get('name', '').lower()
            expected_name = metadata.get('save_name', 'Gibraltar').lower()
            if expected_name in name or 'strait' in name or 'gibraltar' in name:
                score += 5
                feedback_parts.append(f"✅ Path named appropriately: '{best_path.get('name')}'")
        else:
            feedback_parts.append("❌ No valid strait crossing found in saved paths")
    else:
        feedback_parts.append("❌ No measurement paths found in myplaces.kml")
    
    # ================================================================
    # STEP 4: VLM Trajectory Verification (15 points)
    # ================================================================
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm:
        try:
            # Import trajectory frame sampling
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Get trajectory frames (sample across the episode)
            frames = sample_trajectory_frames(traj, n=5)
            final = get_final_screenshot(traj)
            
            if frames or final:
                all_frames = (frames or []) + ([final] if final else [])
                
                vlm_result = query_vlm(
                    prompt=VLM_TRAJECTORY_PROMPT,
                    images=all_frames if len(all_frames) > 1 else None,
                    image=all_frames[0] if len(all_frames) == 1 else None
                )
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    details['vlm_result'] = parsed
                    
                    # Extract VLM scores
                    vlm_total = parsed.get('total_score', 0)
                    confidence = parsed.get('confidence', 'low')
                    
                    # Scale VLM score to 15 points max
                    confidence_mult = {'high': 1.0, 'medium': 0.8, 'low': 0.6}.get(confidence, 0.5)
                    vlm_score = int((vlm_total / 100) * 15 * confidence_mult)
                    
                    score += vlm_score
                    
                    # Add feedback based on VLM findings
                    if parsed.get('strait_visible'):
                        feedback_parts.append("✅ VLM: Strait of Gibraltar visible in trajectory")
                    if parsed.get('ruler_dialog_visible'):
                        feedback_parts.append("✅ VLM: Ruler tool was used")
                    if parsed.get('measurement_line_visible'):
                        feedback_parts.append("✅ VLM: Measurement line visible")
                    
                    feedback_parts.append(f"📊 VLM score: {vlm_score}/15 (confidence: {confidence})")
                else:
                    feedback_parts.append(f"⚠️ VLM verification failed: {vlm_result.get('error', 'unknown')}")
            else:
                feedback_parts.append("⚠️ No trajectory frames available for VLM verification")
                
        except ImportError:
            logger.warning("VLM utilities not available")
            feedback_parts.append("⚠️ VLM verification skipped (utilities not available)")
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            feedback_parts.append(f"⚠️ VLM verification error: {str(e)[:50]}")
    else:
        feedback_parts.append("⚠️ VLM not available for trajectory verification")
    
    details['vlm_score'] = vlm_score
    
    # ================================================================
    # STEP 5: Check Google Earth was running
    # ================================================================
    ge_running = result.get('google_earth_running', False)
    if ge_running:
        feedback_parts.append("✅ Google Earth was running")
    else:
        feedback_parts.append("⚠️ Google Earth not detected at export time")
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    # Key criteria: must have either valid coordinates OR VLM confirmation of ruler use
    best_path = details.get('best_path')
    has_valid_coordinates = best_path and best_path.get('valid_crossing', False)
    has_vlm_confirmation = vlm_score >= 8  # At least medium confidence ruler usage
    
    key_criteria_met = has_valid_coordinates or (has_vlm_confirmation and paths_added > 0)
    
    # Cap score at 100
    final_score = min(score, 100)
    
    # Pass threshold: 60 points with key criteria
    passed = final_score >= 60 and key_criteria_met
    
    details['final_score'] = final_score
    details['key_criteria_met'] = key_criteria_met
    details['has_valid_coordinates'] = has_valid_coordinates
    details['has_vlm_confirmation'] = has_vlm_confirmation
    
    # Summary
    feedback_parts.insert(0, f"{'✅ PASSED' if passed else '❌ FAILED'} - Score: {final_score}/100")
    
    return {
        "passed": passed,
        "score": final_score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }