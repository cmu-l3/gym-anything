#!/usr/bin/env python3
"""
Verifier for Bridge Site Selection task.

VERIFICATION STRATEGY:
1. Placemark exists with correct name (10 points)
2. Placemark is within study area bounds (10 points)
3. Placemark description contains measurement (15 points)
4. Location accuracy - distance from optimal point (25 points)
5. Measurement accuracy - within tolerance of actual width (20 points)
6. File was modified during task - anti-gaming (10 points)
7. VLM trajectory verification - exploration evidence (10 points)

Pass threshold: 60 points with placemark created

CRITICAL: Uses copy_from_env, NOT exec_in_env
"""

import json
import tempfile
import os
import math
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def haversine_distance(lat1, lon1, lat2, lon2):
    """Calculate distance between two points in kilometers."""
    R = 6371  # Earth's radius in km
    lat1, lon1, lat2, lon2 = map(math.radians, [lat1, lon1, lat2, lon2])
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    a = math.sin(dlat/2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon/2)**2
    return 2 * R * math.asin(math.sqrt(a))


def extract_measurement_from_text(text):
    """Extract width measurement from description text."""
    if not text:
        return None
    
    patterns = [
        r'(\d+(?:,\d{3})*(?:\.\d+)?)\s*(?:m|meters?)\b',
        r'width[:\s]+(\d+(?:,\d{3})*(?:\.\d+)?)',
        r'(\d+(?:\.\d+)?)\s*(?:km|kilometers?)',
        r'(\d{3,4})\s*m\b',
        r'~?\s*(\d+(?:,\d{3})*)\s*(?:m|meters?)',
    ]
    
    for pattern in patterns:
        match = re.search(pattern, str(text), re.IGNORECASE)
        if match:
            value = float(match.group(1).replace(',', ''))
            # Convert km to m if needed
            if 'km' in pattern.lower():
                value *= 1000
            return value
    return None


def verify_bridge_site_selection(traj, env_info, task_info):
    """
    Verify that the agent identified and documented the narrowest crossing point.
    
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
    
    # Get task metadata with ground truth
    metadata = task_info.get('metadata', {})
    GROUND_TRUTH = {
        "lat": metadata.get('narrowest_lat', 40.183),
        "lon": metadata.get('narrowest_lon', 26.417),
        "width_meters": metadata.get('expected_width_meters', 1250),
        "width_tolerance_percent": metadata.get('width_tolerance_percent', 25),
        "location_tolerance_km": metadata.get('location_tolerance_km', 5),
        "study_area_north": metadata.get('study_area_north', 40.25),
        "study_area_south": metadata.get('study_area_south', 40.08),
        "expected_name": metadata.get('expected_placemark_name', 'Bridge_Site_Recommendation')
    }
    
    feedback_parts = []
    score = 0
    max_score = 100
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
        logger.error(f"Failed to read result: {e}")
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
    # CRITERION 1: Placemark exists with correct name (10 points)
    # ================================================================
    placemark_found = result.get('placemark_found', False)
    placemark_name = result.get('placemark_name', '')
    
    if placemark_found:
        name_lower = placemark_name.lower().replace(' ', '_').replace('-', '_')
        expected_lower = GROUND_TRUTH['expected_name'].lower().replace(' ', '_').replace('-', '_')
        
        if expected_lower in name_lower or name_lower == expected_lower:
            score += 10
            feedback_parts.append("✅ Placemark created with correct name")
            details['placemark_name_correct'] = True
        else:
            score += 5  # Partial credit for any bridge-related placemark
            feedback_parts.append(f"⚠️ Placemark found but name differs: '{placemark_name}'")
            details['placemark_name_correct'] = False
    else:
        feedback_parts.append("❌ No Bridge_Site_Recommendation placemark found")
        details['placemark_name_correct'] = False
        # Without placemark, task cannot pass
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: Placemark within study area (10 points)
    # ================================================================
    placemark_lat = result.get('placemark_lat')
    placemark_lon = result.get('placemark_lon')
    
    if placemark_lat is not None and placemark_lon is not None:
        details['placemark_coordinates'] = {'lat': placemark_lat, 'lon': placemark_lon}
        
        if GROUND_TRUTH['study_area_south'] <= placemark_lat <= GROUND_TRUTH['study_area_north']:
            score += 10
            feedback_parts.append("✅ Placemark within study area bounds")
            details['in_study_area'] = True
        else:
            feedback_parts.append(f"❌ Placemark outside study area (lat: {placemark_lat})")
            details['in_study_area'] = False
    else:
        feedback_parts.append("❌ Could not extract placemark coordinates")
        details['in_study_area'] = False
    
    # ================================================================
    # CRITERION 3: Description contains measurement (15 points)
    # ================================================================
    placemark_description = result.get('placemark_description', '')
    measurement_value = result.get('measurement_value')
    
    # Try to extract from description if not already parsed
    if measurement_value is None:
        measurement_value = extract_measurement_from_text(placemark_description)
    
    if measurement_value is not None:
        score += 15
        feedback_parts.append(f"✅ Width measurement found: {measurement_value}m")
        details['measurement_in_description'] = True
        details['measurement_value'] = measurement_value
    else:
        feedback_parts.append("❌ No width measurement in placemark description")
        details['measurement_in_description'] = False
    
    # ================================================================
    # CRITERION 4: Location accuracy (25 points)
    # ================================================================
    if placemark_lat is not None and placemark_lon is not None:
        distance_km = haversine_distance(
            placemark_lat, placemark_lon,
            GROUND_TRUTH['lat'], GROUND_TRUTH['lon']
        )
        details['distance_from_optimal_km'] = round(distance_km, 2)
        
        if distance_km <= GROUND_TRUTH['location_tolerance_km']:
            score += 25
            feedback_parts.append(f"✅ Excellent location ({distance_km:.1f}km from optimal)")
            details['location_quality'] = 'excellent'
        elif distance_km <= GROUND_TRUTH['location_tolerance_km'] * 1.5:
            score += 18
            feedback_parts.append(f"✅ Good location ({distance_km:.1f}km from optimal)")
            details['location_quality'] = 'good'
        elif distance_km <= GROUND_TRUTH['location_tolerance_km'] * 2:
            score += 12
            feedback_parts.append(f"⚠️ Acceptable location ({distance_km:.1f}km from optimal)")
            details['location_quality'] = 'acceptable'
        elif distance_km <= 15:
            score += 5
            feedback_parts.append(f"⚠️ Location somewhat far ({distance_km:.1f}km from optimal)")
            details['location_quality'] = 'far'
        else:
            feedback_parts.append(f"❌ Location too far ({distance_km:.1f}km from optimal)")
            details['location_quality'] = 'poor'
    
    # ================================================================
    # CRITERION 5: Measurement accuracy (20 points)
    # ================================================================
    if measurement_value is not None:
        expected_width = GROUND_TRUTH['width_meters']
        tolerance = expected_width * GROUND_TRUTH['width_tolerance_percent'] / 100
        error = abs(measurement_value - expected_width)
        error_percent = (error / expected_width) * 100
        
        details['measurement_error_percent'] = round(error_percent, 1)
        
        if error <= tolerance:
            score += 20
            feedback_parts.append(f"✅ Accurate measurement (error: {error_percent:.1f}%)")
            details['measurement_accurate'] = True
        elif error <= tolerance * 1.5:
            score += 12
            feedback_parts.append(f"⚠️ Measurement somewhat accurate (error: {error_percent:.1f}%)")
            details['measurement_accurate'] = 'partial'
        elif error <= tolerance * 2:
            score += 6
            feedback_parts.append(f"⚠️ Measurement has significant error ({error_percent:.1f}%)")
            details['measurement_accurate'] = 'rough'
        else:
            feedback_parts.append(f"❌ Measurement inaccurate (error: {error_percent:.1f}%)")
            details['measurement_accurate'] = False
    
    # ================================================================
    # CRITERION 6: File was modified during task (10 points) - anti-gaming
    # ================================================================
    file_modified = result.get('file_modified_during_task', False)
    initial_count = result.get('initial_placemark_count', 0)
    final_count = result.get('final_placemark_count', 0)
    
    if file_modified and final_count > initial_count:
        score += 10
        feedback_parts.append("✅ New placemark created during task")
        details['file_modified'] = True
    elif file_modified:
        score += 5
        feedback_parts.append("⚠️ File modified but placemark count unchanged")
        details['file_modified'] = 'partial'
    else:
        feedback_parts.append("⚠️ File modification not detected")
        details['file_modified'] = False
    
    # ================================================================
    # CRITERION 7: VLM trajectory verification (10 points)
    # ================================================================
    vlm_score = 0
    if query_vlm and traj:
        try:
            # Import VLM utilities
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Sample trajectory frames to verify exploration
            frames = sample_trajectory_frames(traj, n=5)
            final_frame = get_final_screenshot(traj)
            
            if frames or final_frame:
                all_frames = (frames or []) + ([final_frame] if final_frame else [])
                
                vlm_prompt = """You are verifying if an agent performed a geographic exploration task in Google Earth.

TASK: Find the narrowest crossing point of the Dardanelles strait by exploring and measuring multiple locations.

Analyze these trajectory screenshots (shown chronologically) and determine:

1. GOOGLE_EARTH_VISIBLE: Is Google Earth Pro the active application showing satellite/map imagery?
2. STRAIT_EXPLORED: Do the images show the Dardanelles strait (narrow waterway between two land masses in Turkey)?
3. RULER_TOOL_USED: Is there evidence of the ruler/measurement tool being used (line drawn across water)?
4. MULTIPLE_LOCATIONS: Do the screenshots show different views/zoom levels, suggesting exploration?
5. PLACEMARK_CREATED: Is there any evidence of placemark creation dialog or a placemark icon?

Respond in JSON format:
{
    "google_earth_visible": true/false,
    "strait_explored": true/false,
    "ruler_tool_used": true/false,
    "multiple_locations": true/false,
    "placemark_created": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see in the trajectory"
}
"""
                vlm_result = query_vlm(prompt=vlm_prompt, images=all_frames)
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    details['vlm_result'] = parsed
                    
                    # Score based on VLM verification
                    vlm_criteria = 0
                    if parsed.get('google_earth_visible'):
                        vlm_criteria += 1
                    if parsed.get('strait_explored'):
                        vlm_criteria += 1
                    if parsed.get('ruler_tool_used'):
                        vlm_criteria += 1
                    if parsed.get('multiple_locations'):
                        vlm_criteria += 1
                    if parsed.get('placemark_created'):
                        vlm_criteria += 1
                    
                    confidence = parsed.get('confidence', 'low')
                    confidence_mult = {'high': 1.0, 'medium': 0.8, 'low': 0.6}.get(confidence, 0.6)
                    
                    vlm_score = int((vlm_criteria / 5) * 10 * confidence_mult)
                    score += vlm_score
                    
                    if vlm_criteria >= 3:
                        feedback_parts.append(f"✅ Trajectory shows exploration ({vlm_criteria}/5 criteria)")
                    elif vlm_criteria >= 1:
                        feedback_parts.append(f"⚠️ Partial exploration evidence ({vlm_criteria}/5 criteria)")
                    else:
                        feedback_parts.append("❌ No exploration evidence in trajectory")
                else:
                    feedback_parts.append("⚠️ VLM verification unavailable")
                    details['vlm_error'] = vlm_result.get('error', 'Unknown')
            else:
                feedback_parts.append("⚠️ No trajectory frames available")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback_parts.append(f"⚠️ VLM verification error: {str(e)[:50]}")
            details['vlm_error'] = str(e)
    else:
        feedback_parts.append("⚠️ VLM verification not available")
    
    details['vlm_score'] = vlm_score
    
    # ================================================================
    # Final scoring and pass/fail determination
    # ================================================================
    details['final_score'] = score
    details['max_score'] = max_score
    
    # Key criteria for passing:
    # - Placemark must exist
    # - Either good location OR good measurement
    key_criteria_met = (
        placemark_found and
        (details.get('location_quality') in ['excellent', 'good', 'acceptable'] or
         details.get('measurement_accurate') in [True, 'partial'])
    )
    
    passed = score >= 60 and key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }