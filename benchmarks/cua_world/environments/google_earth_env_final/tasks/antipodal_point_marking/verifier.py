#!/usr/bin/env python3
"""
Verifier for Antipodal Point Marking task.

VERIFICATION STRATEGY:
1. KML File Analysis (60 points):
   - Placemark named "Quito Antipode" exists (20 pts)
   - Correct hemisphere (Northern/Eastern) (15 pts)
   - Latitude accuracy within tolerance (15 pts)
   - Longitude accuracy within tolerance (10 pts)

2. Anti-Gaming Checks (15 points):
   - File modified during task timeframe (10 pts)
   - Placemark count increased (5 pts)

3. VLM Trajectory Verification (25 points):
   - Navigation progression visible (10 pts)
   - Southeast Asian geography visible (10 pts)
   - Placemark creation evidence (5 pts)

Pass threshold: 70 points with placemark existence AND correct hemisphere
"""

import json
import tempfile
import os
import math
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected values
EXPECTED_LAT = 0.1807
EXPECTED_LON = 101.5322
TOLERANCE_DEG = 0.5
EXPECTED_NAME = "Quito Antipode"
MAX_DISTANCE_KM = 100


def haversine_distance(lat1, lon1, lat2, lon2):
    """Calculate great circle distance in kilometers."""
    R = 6371  # Earth's radius in km
    
    lat1_rad = math.radians(lat1)
    lat2_rad = math.radians(lat2)
    delta_lat = math.radians(lat2 - lat1)
    delta_lon = math.radians(lon2 - lon1)
    
    a = math.sin(delta_lat/2)**2 + math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(delta_lon/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    
    return R * c


def parse_kml_for_placemark(kml_content, target_name):
    """Parse KML content to find a placemark by name and extract coordinates."""
    try:
        # Find placemark with target name (case-insensitive)
        pattern = r'<Placemark[^>]*>.*?<name>\s*' + re.escape(target_name) + r'\s*</name>.*?<coordinates>\s*([^<]+)\s*</coordinates>.*?</Placemark>'
        match = re.search(pattern, kml_content, re.DOTALL | re.IGNORECASE)
        
        if match:
            coords_str = match.group(1).strip()
            parts = coords_str.split(',')
            if len(parts) >= 2:
                lon = float(parts[0].strip())
                lat = float(parts[1].strip())
                return {"found": True, "lat": lat, "lon": lon, "raw": coords_str}
        
        # Try alternative pattern without strict name matching
        pattern_alt = r'<Placemark[^>]*>.*?<name>([^<]*[Qq]uito[^<]*[Aa]ntipode[^<]*)</name>.*?<coordinates>\s*([^<]+)\s*</coordinates>.*?</Placemark>'
        match_alt = re.search(pattern_alt, kml_content, re.DOTALL)
        
        if match_alt:
            coords_str = match_alt.group(2).strip()
            parts = coords_str.split(',')
            if len(parts) >= 2:
                lon = float(parts[0].strip())
                lat = float(parts[1].strip())
                return {"found": True, "lat": lat, "lon": lon, "raw": coords_str, "actual_name": match_alt.group(1)}
        
        return {"found": False, "error": "Placemark not found"}
    except Exception as e:
        return {"found": False, "error": str(e)}


# VLM Prompts
TRAJECTORY_VERIFICATION_PROMPT = """You are analyzing a sequence of Google Earth Pro screenshots from an agent performing an antipodal point navigation task.

The task was to:
1. Navigate from Quito, Ecuador to its antipodal point in Sumatra, Indonesia
2. Create a placemark named "Quito Antipode" at coordinates ~0.18°N, 101.53°E

Analyze these screenshots (ordered from earliest to latest) and determine:

1. NAVIGATION_OCCURRED: Do the screenshots show the view changing significantly? 
   - Look for transition from one continent/region to another
   - Evidence of search/navigation being used
   
2. SOUTHEAST_ASIA_VISIBLE: Does any screenshot show Southeast Asian geography?
   - Indonesian islands, Sumatra, or nearby regions
   - Eastern hemisphere location indicators
   
3. PLACEMARK_CREATION: Is there evidence of placemark creation?
   - Placemark dialog visible
   - Placemark icon/pin visible on the map
   - "Quito Antipode" text visible anywhere
   
4. GOOGLE_EARTH_ACTIVE: Are the screenshots showing Google Earth interface?
   - Satellite imagery visible
   - Google Earth toolbars/panels

Respond in JSON format:
{
    "navigation_occurred": true/false,
    "southeast_asia_visible": true/false,
    "placemark_creation_evidence": true/false,
    "google_earth_active": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see across the frames"
}
"""


def verify_antipodal_point_marking(traj, env_info, task_info):
    """
    Verify that the agent navigated to the antipodal point and created a placemark.
    
    Uses multiple verification signals:
    1. KML file analysis for placemark data
    2. Timestamp checks for anti-gaming
    3. VLM trajectory verification
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    expected_lat = metadata.get('expected_latitude', EXPECTED_LAT)
    expected_lon = metadata.get('expected_longitude', EXPECTED_LON)
    tolerance = metadata.get('coordinate_tolerance_degrees', TOLERANCE_DEG)
    
    feedback_parts = []
    score = 0
    details = {}
    
    # ================================================================
    # STEP 1: Copy and parse task result JSON
    # ================================================================
    result_data = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
        details['result_data'] = result_data
    except Exception as e:
        logger.warning(f"Could not read task result: {e}")
        details['result_error'] = str(e)
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # STEP 2: Copy and parse KML file
    # ================================================================
    kml_content = ""
    placemark_data = {"found": False}
    
    temp_kml = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
    try:
        copy_from_env("/tmp/myplaces_final.kml", temp_kml.name)
        with open(temp_kml.name, 'r', encoding='utf-8', errors='ignore') as f:
            kml_content = f.read()
        
        placemark_data = parse_kml_for_placemark(kml_content, EXPECTED_NAME)
        details['placemark_data'] = placemark_data
    except Exception as e:
        logger.warning(f"Could not read KML file: {e}")
        # Try alternate path
        try:
            copy_from_env("/home/ga/.googleearth/myplaces.kml", temp_kml.name)
            with open(temp_kml.name, 'r', encoding='utf-8', errors='ignore') as f:
                kml_content = f.read()
            placemark_data = parse_kml_for_placemark(kml_content, EXPECTED_NAME)
            details['placemark_data'] = placemark_data
        except Exception as e2:
            details['kml_error'] = str(e2)
    finally:
        if os.path.exists(temp_kml.name):
            os.unlink(temp_kml.name)
    
    # ================================================================
    # CRITERION 1: Placemark exists (20 points)
    # ================================================================
    placemark_exists = placemark_data.get('found', False)
    
    if not placemark_exists:
        # Also check result_data as backup
        placemark_exists = result_data.get('quito_antipode_exists', False)
    
    if placemark_exists:
        score += 20
        feedback_parts.append("✅ Placemark 'Quito Antipode' found")
    else:
        feedback_parts.append("❌ Placemark 'Quito Antipode' NOT found")
        # Cannot proceed with coordinate checks without placemark
        details['early_exit'] = "No placemark found"
    
    # ================================================================
    # CRITERION 2: Correct hemisphere (15 points)
    # ================================================================
    correct_hemisphere = False
    found_lat = None
    found_lon = None
    
    if placemark_data.get('found'):
        found_lat = placemark_data.get('lat')
        found_lon = placemark_data.get('lon')
    elif result_data.get('placemark_latitude') is not None:
        found_lat = result_data.get('placemark_latitude')
        found_lon = result_data.get('placemark_longitude')
    
    if found_lat is not None and found_lon is not None:
        details['found_coordinates'] = {"lat": found_lat, "lon": found_lon}
        
        # Check hemisphere: should be Northern (lat > -10) and Eastern (lon > 0)
        if found_lat > -10 and found_lon > 0:
            correct_hemisphere = True
            score += 15
            feedback_parts.append(f"✅ Correct hemisphere (N/E): {found_lat:.4f}°, {found_lon:.4f}°")
        else:
            feedback_parts.append(f"❌ Wrong hemisphere: {found_lat:.4f}°, {found_lon:.4f}°")
    else:
        feedback_parts.append("❌ Could not extract coordinates")
    
    # ================================================================
    # CRITERION 3: Latitude accuracy (15 points)
    # ================================================================
    lat_accurate = False
    if found_lat is not None:
        lat_diff = abs(found_lat - expected_lat)
        details['latitude_error'] = lat_diff
        
        if lat_diff <= tolerance:
            lat_accurate = True
            score += 15
            feedback_parts.append(f"✅ Latitude accurate (error: {lat_diff:.4f}°)")
        else:
            feedback_parts.append(f"❌ Latitude inaccurate (error: {lat_diff:.4f}°, tolerance: {tolerance}°)")
    
    # ================================================================
    # CRITERION 4: Longitude accuracy (10 points)
    # ================================================================
    lon_accurate = False
    if found_lon is not None:
        lon_diff = abs(found_lon - expected_lon)
        details['longitude_error'] = lon_diff
        
        if lon_diff <= tolerance:
            lon_accurate = True
            score += 10
            feedback_parts.append(f"✅ Longitude accurate (error: {lon_diff:.4f}°)")
        else:
            feedback_parts.append(f"❌ Longitude inaccurate (error: {lon_diff:.4f}°, tolerance: {tolerance}°)")
    
    # Calculate distance from expected point
    if found_lat is not None and found_lon is not None:
        distance_km = haversine_distance(found_lat, found_lon, expected_lat, expected_lon)
        details['distance_from_expected_km'] = distance_km
        feedback_parts.append(f"📍 Distance from expected: {distance_km:.2f} km")
    
    # ================================================================
    # CRITERION 5: Anti-gaming - File modified during task (10 points)
    # ================================================================
    file_modified = result_data.get('myplaces_modified_during_task', False)
    
    if file_modified:
        score += 10
        feedback_parts.append("✅ KML file modified during task")
    else:
        feedback_parts.append("⚠️ KML file not modified during task timeframe")
    
    # ================================================================
    # CRITERION 6: Placemark count increased (5 points)
    # ================================================================
    placemark_count_increased = result_data.get('placemark_count_increased', False)
    
    if placemark_count_increased:
        score += 5
        feedback_parts.append("✅ New placemark added")
    else:
        feedback_parts.append("⚠️ Placemark count did not increase")
    
    # ================================================================
    # CRITERION 7: VLM Trajectory Verification (25 points)
    # ================================================================
    vlm_score = 0
    
    if query_vlm:
        try:
            # Import trajectory sampling utilities
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Get trajectory frames
            traj_frames = sample_trajectory_frames(traj, n=5)
            final_frame = get_final_screenshot(traj)
            
            all_frames = []
            if traj_frames:
                all_frames.extend(traj_frames)
            if final_frame:
                all_frames.append(final_frame)
            
            if all_frames:
                vlm_result = query_vlm(
                    prompt=TRAJECTORY_VERIFICATION_PROMPT,
                    images=all_frames
                )
                
                details['vlm_result'] = vlm_result
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    
                    if parsed.get('google_earth_active', False):
                        vlm_score += 5
                    if parsed.get('navigation_occurred', False):
                        vlm_score += 8
                    if parsed.get('southeast_asia_visible', False):
                        vlm_score += 7
                    if parsed.get('placemark_creation_evidence', False):
                        vlm_score += 5
                    
                    confidence = parsed.get('confidence', 'low')
                    if confidence == 'low':
                        vlm_score = int(vlm_score * 0.7)
                    elif confidence == 'medium':
                        vlm_score = int(vlm_score * 0.85)
                    
                    observations = parsed.get('observations', '')
                    feedback_parts.append(f"🔍 VLM: {observations[:100]}...")
                else:
                    feedback_parts.append(f"⚠️ VLM verification failed: {vlm_result.get('error', 'unknown')}")
            else:
                feedback_parts.append("⚠️ No trajectory frames available for VLM")
                
        except ImportError:
            # Fallback: try to copy and verify final screenshot
            logger.warning("Could not import VLM utilities, skipping VLM verification")
            feedback_parts.append("⚠️ VLM utilities not available")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            feedback_parts.append(f"⚠️ VLM error: {str(e)[:50]}")
    else:
        feedback_parts.append("⚠️ VLM not available for verification")
    
    score += vlm_score
    details['vlm_score'] = vlm_score
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    details['score_breakdown'] = {
        'placemark_exists': 20 if placemark_exists else 0,
        'correct_hemisphere': 15 if correct_hemisphere else 0,
        'latitude_accurate': 15 if lat_accurate else 0,
        'longitude_accurate': 10 if lon_accurate else 0,
        'file_modified': 10 if file_modified else 0,
        'placemark_count_increased': 5 if placemark_count_increased else 0,
        'vlm_verification': vlm_score
    }
    
    # Pass requires: 70+ points AND placemark exists AND correct hemisphere
    key_criteria_met = placemark_exists and correct_hemisphere
    passed = score >= 70 and key_criteria_met
    
    # Build final feedback
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": feedback,
        "details": details
    }