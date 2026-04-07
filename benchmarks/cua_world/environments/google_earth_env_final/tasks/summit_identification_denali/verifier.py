#!/usr/bin/env python3
"""
Verifier for Summit Identification Denali task.

MULTI-SIGNAL VERIFICATION:
1. Placemark exists in myplaces.kml (10 points)
2. KML was modified during task - anti-gaming (15 points)
3. Placemark name contains "Denali Summit" (15 points)
4. Placemark coordinates within 500m of true summit (25 points)
5. Elevation documented in description (20 points)
6. VLM: Trajectory shows navigation to Denali area (15 points)

Pass threshold: 70 points with summit_accuracy criterion met

Ground Truth:
- Summit coordinates: 63.0692°N, 151.0070°W
- Elevation: 20,310 ft (6,190 m)
- Coordinate tolerance: 0.5 km
- Elevation tolerance: 500 ft
"""

import json
import tempfile
import os
import math
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Ground truth values
TRUE_LAT = 63.0692
TRUE_LON = -151.0070
TRUE_ELEV_FT = 20310
TRUE_ELEV_M = 6190
MAX_DISTANCE_KM = 0.5
ELEV_TOLERANCE_FT = 500


def haversine_distance(lat1, lon1, lat2, lon2):
    """Calculate distance between two points in kilometers."""
    R = 6371  # Earth's radius in km
    lat1, lon1, lat2, lon2 = map(math.radians, [lat1, lon1, lat2, lon2])
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    a = math.sin(dlat/2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon/2)**2
    c = 2 * math.asin(math.sqrt(a))
    return R * c


def contains_elevation(text, expected_ft, expected_m, tolerance_ft=500):
    """Check if text contains elevation value within tolerance."""
    if not text:
        return False
    
    # Look for numbers in the text (handle commas in numbers)
    text_clean = text.replace(',', '')
    numbers = re.findall(r'[\d]+\.?\d*', text_clean)
    
    for num_str in numbers:
        try:
            num = float(num_str)
            # Check if it's close to expected elevation in feet
            if abs(num - expected_ft) <= tolerance_ft:
                return True
            # Check if it's close to expected elevation in meters
            if abs(num - expected_m) <= (tolerance_ft * 0.3048):
                return True
        except ValueError:
            continue
    
    return False


# VLM Prompt for trajectory verification
TRAJECTORY_VERIFICATION_PROMPT = """You are verifying if a computer agent successfully navigated to Denali National Park in Google Earth and worked on identifying the summit.

These screenshots are sampled from the agent's workflow (earliest to latest).

For successful task completion, the agent should have:
1. Started with Google Earth open
2. Navigated to Alaska/Denali National Park area
3. Zoomed in to view mountain terrain
4. Potentially opened a placemark creation dialog

Look at the sequence and assess:
1. IS_GOOGLE_EARTH: Are these screenshots from Google Earth (satellite imagery interface)?
2. SHOWS_ALASKA_DENALI: Does any frame show Alaska, Denali National Park, or mountain terrain?
3. NAVIGATION_OCCURRED: Is there evidence of navigation/zooming (different views across frames)?
4. PLACEMARK_ACTIVITY: Is there any evidence of placemark creation dialog or My Places panel?

Respond in JSON format:
{
    "is_google_earth": true/false,
    "shows_alaska_denali": true/false,
    "navigation_occurred": true/false,
    "placemark_activity": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "what you see across the frames"
}
"""


def verify_summit_identification(traj, env_info, task_info):
    """
    Verify that the agent identified and marked the Denali summit correctly.
    
    Uses multiple independent signals to prevent gaming.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_placemark_name', 'Denali Summit')
    
    feedback_parts = []
    score = 0
    max_score = 100
    details = {}
    criteria = {}
    
    # ================================================================
    # Copy result file from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        details['export_result'] = result
    except Exception as e:
        logger.error(f"Failed to read task result: {e}")
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
    # CRITERION 1: Placemark exists in KML (10 points)
    # ================================================================
    placemark_found = result.get('placemark_found', False)
    
    if placemark_found:
        score += 10
        criteria['placemark_exists'] = True
        feedback_parts.append("✅ Placemark found in My Places")
    else:
        criteria['placemark_exists'] = False
        feedback_parts.append("❌ No Denali/Summit placemark found")
        # If no placemark, can't verify other criteria - but continue for partial credit
    
    # ================================================================
    # CRITERION 2: KML modified during task - anti-gaming (15 points)
    # ================================================================
    kml_modified = result.get('kml_modified_during_task', False)
    task_start = result.get('task_start', 0)
    task_end = result.get('task_end', 0)
    
    if kml_modified:
        score += 15
        criteria['kml_modified'] = True
        feedback_parts.append("✅ KML file modified during task")
    else:
        criteria['kml_modified'] = False
        feedback_parts.append("⚠️ KML file not modified during task window")
    
    details['task_duration_sec'] = task_end - task_start
    
    # ================================================================
    # CRITERION 3: Placemark name correct (15 points)
    # ================================================================
    placemark_name = result.get('placemark_name', '')
    details['placemark_name'] = placemark_name
    
    if placemark_name:
        name_lower = placemark_name.lower()
        if 'denali' in name_lower and 'summit' in name_lower:
            score += 15
            criteria['name_correct'] = True
            feedback_parts.append(f"✅ Correct name: '{placemark_name}'")
        elif 'denali' in name_lower or 'summit' in name_lower:
            score += 8
            criteria['name_correct'] = 'partial'
            feedback_parts.append(f"⚠️ Partial name match: '{placemark_name}'")
        else:
            criteria['name_correct'] = False
            feedback_parts.append(f"❌ Name doesn't contain 'Denali Summit': '{placemark_name}'")
    else:
        criteria['name_correct'] = False
    
    # ================================================================
    # CRITERION 4: Summit accuracy - within 500m (25 points)
    # ================================================================
    placemark_lat = result.get('placemark_lat', 0)
    placemark_lon = result.get('placemark_lon', 0)
    
    details['placemark_coordinates'] = {'lat': placemark_lat, 'lon': placemark_lon}
    details['expected_coordinates'] = {'lat': TRUE_LAT, 'lon': TRUE_LON}
    
    if placemark_lat != 0 and placemark_lon != 0:
        distance_km = haversine_distance(placemark_lat, placemark_lon, TRUE_LAT, TRUE_LON)
        details['distance_from_summit_km'] = round(distance_km, 3)
        
        if distance_km <= MAX_DISTANCE_KM:
            score += 25
            criteria['summit_accuracy'] = True
            feedback_parts.append(f"✅ Summit location accurate ({distance_km:.3f} km from true summit)")
        elif distance_km <= MAX_DISTANCE_KM * 2:
            score += 12
            criteria['summit_accuracy'] = 'partial'
            feedback_parts.append(f"⚠️ Close to summit ({distance_km:.3f} km, tolerance: {MAX_DISTANCE_KM} km)")
        else:
            criteria['summit_accuracy'] = False
            feedback_parts.append(f"❌ Too far from summit ({distance_km:.3f} km, tolerance: {MAX_DISTANCE_KM} km)")
    else:
        criteria['summit_accuracy'] = False
        feedback_parts.append("❌ Could not extract placemark coordinates")
    
    # ================================================================
    # CRITERION 5: Elevation documented (20 points)
    # ================================================================
    placemark_desc = result.get('placemark_description', '')
    details['placemark_description'] = placemark_desc[:200] if placemark_desc else None
    
    if placemark_desc:
        if contains_elevation(placemark_desc, TRUE_ELEV_FT, TRUE_ELEV_M, ELEV_TOLERANCE_FT):
            score += 20
            criteria['elevation_documented'] = True
            feedback_parts.append("✅ Elevation documented correctly")
        else:
            criteria['elevation_documented'] = False
            feedback_parts.append("❌ Elevation not found or incorrect in description")
    else:
        criteria['elevation_documented'] = False
        feedback_parts.append("❌ No description with elevation")
    
    # ================================================================
    # CRITERION 6: VLM trajectory verification (15 points)
    # ================================================================
    vlm_score = 0
    
    if query_vlm:
        try:
            # Import trajectory sampling utility
            from gym_anything.vlm import sample_trajectory_frames
            
            # Sample frames across the trajectory
            frames = sample_trajectory_frames(traj, n=5)
            
            if frames and len(frames) > 0:
                vlm_result = query_vlm(
                    prompt=TRAJECTORY_VERIFICATION_PROMPT,
                    images=frames
                )
                
                details['vlm_result'] = vlm_result
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    
                    vlm_checks = [
                        parsed.get('is_google_earth', False),
                        parsed.get('shows_alaska_denali', False),
                        parsed.get('navigation_occurred', False),
                        parsed.get('placemark_activity', False)
                    ]
                    
                    vlm_checks_passed = sum(vlm_checks)
                    confidence = parsed.get('confidence', 'low')
                    
                    # Scale score based on checks passed and confidence
                    confidence_mult = {'high': 1.0, 'medium': 0.85, 'low': 0.7}.get(confidence, 0.7)
                    vlm_score = int((vlm_checks_passed / 4) * 15 * confidence_mult)
                    
                    if vlm_score >= 10:
                        criteria['vlm_trajectory'] = True
                        feedback_parts.append(f"✅ Trajectory shows Denali navigation (VLM: {vlm_checks_passed}/4 checks)")
                    elif vlm_score >= 5:
                        criteria['vlm_trajectory'] = 'partial'
                        feedback_parts.append(f"⚠️ Partial trajectory evidence (VLM: {vlm_checks_passed}/4 checks)")
                    else:
                        criteria['vlm_trajectory'] = False
                        feedback_parts.append(f"❌ Trajectory doesn't show expected workflow (VLM: {vlm_checks_passed}/4 checks)")
                else:
                    criteria['vlm_trajectory'] = 'error'
                    feedback_parts.append(f"⚠️ VLM verification failed: {vlm_result.get('error', 'unknown')}")
            else:
                criteria['vlm_trajectory'] = 'no_frames'
                feedback_parts.append("⚠️ No trajectory frames available for VLM")
        except ImportError:
            # Fallback if VLM module not available - give partial credit
            vlm_score = 8
            criteria['vlm_trajectory'] = 'unavailable'
            feedback_parts.append("⚠️ VLM verification unavailable")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            criteria['vlm_trajectory'] = 'error'
            feedback_parts.append(f"⚠️ VLM error: {str(e)[:50]}")
    else:
        # Give some credit if placemark is correct but VLM not available
        if criteria.get('summit_accuracy') == True:
            vlm_score = 10
            criteria['vlm_trajectory'] = 'inferred'
            feedback_parts.append("⚠️ VLM unavailable, inferred from placemark accuracy")
        else:
            criteria['vlm_trajectory'] = 'unavailable'
            feedback_parts.append("⚠️ VLM query function not available")
    
    score += vlm_score
    
    # ================================================================
    # Final scoring and pass/fail determination
    # ================================================================
    details['criteria'] = criteria
    details['score_breakdown'] = {
        'placemark_exists': 10 if criteria.get('placemark_exists') else 0,
        'kml_modified': 15 if criteria.get('kml_modified') else 0,
        'name_correct': 15 if criteria.get('name_correct') == True else (8 if criteria.get('name_correct') == 'partial' else 0),
        'summit_accuracy': 25 if criteria.get('summit_accuracy') == True else (12 if criteria.get('summit_accuracy') == 'partial' else 0),
        'elevation_documented': 20 if criteria.get('elevation_documented') else 0,
        'vlm_trajectory': vlm_score
    }
    
    # Pass requires: 70+ points AND summit accuracy achieved
    summit_accurate = criteria.get('summit_accuracy') in [True, 'partial']
    passed = score >= 70 and summit_accurate
    
    # Build final feedback
    feedback = " | ".join(feedback_parts)
    if passed:
        feedback = f"✓ PASSED ({score}/{max_score}) | " + feedback
    else:
        if not summit_accurate:
            feedback = f"✗ FAILED ({score}/{max_score}) - Summit location not accurate | " + feedback
        else:
            feedback = f"✗ FAILED ({score}/{max_score}) - Score below threshold | " + feedback
    
    return {
        "passed": passed,
        "score": score,
        "max_score": max_score,
        "feedback": feedback,
        "details": details
    }