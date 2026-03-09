#!/usr/bin/env python3
"""
Verifier for tripoint_border_marker task.

TASK: Navigate to the Austria-Hungary-Slovakia tripoint on the Danube River
and create a precisely positioned placemark named 'AUT-HUN-SVK Tripoint'.

VERIFICATION STRATEGY (Multi-Signal):
1. Programmatic: Parse myplaces.kml for placemark with correct name and coordinates
2. Anti-gaming: Check file was modified during task (timestamps)
3. VLM Trajectory: Verify agent navigated to Danube/Bratislava region
4. VLM Final: Verify placemark creation workflow visible

Ground Truth:
- Tripoint coordinates: 48.016°N, 17.158°E (±0.01°)
- Placemark name: "AUT-HUN-SVK Tripoint"
"""

import json
import tempfile
import os
import re
import math
import base64
import xml.etree.ElementTree as ET
import logging
from typing import Dict, Any, List, Optional, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ============================================================
# CONSTANTS
# ============================================================

TRIPOINT = {
    'lat': 48.016,
    'lon': 17.158,
    'tolerance': 0.01,  # ~1.1 km
    'name': 'AUT-HUN-SVK Tripoint'
}

REGION_BOUNDS = {
    'lat_min': 47.5,
    'lat_max': 48.5,
    'lon_min': 16.5,
    'lon_max': 18.0
}


# ============================================================
# KML PARSING
# ============================================================

def parse_kml_placemarks(kml_content: str) -> List[Dict[str, Any]]:
    """Parse KML content and extract placemark information."""
    placemarks = []
    
    if not kml_content:
        return placemarks
    
    try:
        root = ET.fromstring(kml_content)
        
        # Find all Placemarks (handle various namespace configurations)
        for elem in root.iter():
            if 'Placemark' in elem.tag:
                placemark = {'name': None, 'lat': None, 'lon': None, 'description': None}
                
                for child in elem.iter():
                    tag_name = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                    
                    if tag_name == 'name' and child.text:
                        placemark['name'] = child.text.strip()
                    elif tag_name == 'description' and child.text:
                        placemark['description'] = child.text.strip()
                    elif tag_name == 'coordinates' and child.text:
                        # Format: lon,lat,alt or lon,lat
                        coords_text = child.text.strip()
                        # Handle multi-point coordinates (take first point)
                        first_coord = coords_text.split()[0] if ' ' in coords_text else coords_text
                        parts = first_coord.split(',')
                        if len(parts) >= 2:
                            try:
                                placemark['lon'] = float(parts[0])
                                placemark['lat'] = float(parts[1])
                            except ValueError:
                                pass
                
                if placemark['name'] or (placemark['lat'] is not None):
                    placemarks.append(placemark)
                    
    except ET.ParseError as e:
        logger.warning(f"KML parse error: {e}")
    except Exception as e:
        logger.warning(f"Error parsing KML: {e}")
    
    return placemarks


def check_name_match(placemark_name: str, target_name: str) -> Tuple[bool, str]:
    """Check if placemark name matches target (with flexibility)."""
    if not placemark_name:
        return False, "no_name"
    
    pm_lower = placemark_name.lower().strip()
    target_lower = target_name.lower().strip()
    
    # Exact match
    if pm_lower == target_lower:
        return True, "exact"
    
    # Contains all key components
    key_terms = ['tripoint', 'aut', 'hun', 'svk']
    alt_terms = ['austria', 'hungary', 'slovakia']
    
    has_tripoint = 'tripoint' in pm_lower or 'tri-point' in pm_lower or 'triple' in pm_lower
    has_countries = (
        (any(t in pm_lower for t in ['aut', 'austria'])) and
        (any(t in pm_lower for t in ['hun', 'hungary'])) and
        (any(t in pm_lower for t in ['svk', 'slovakia']))
    )
    
    if has_tripoint and has_countries:
        return True, "partial"
    
    # Just has tripoint and some country reference
    if has_tripoint and any(t in pm_lower for t in key_terms + alt_terms):
        return True, "loose"
    
    return False, "no_match"


def calculate_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate distance in degrees (Euclidean approximation)."""
    return math.sqrt((lat2 - lat1)**2 + (lon2 - lon1)**2)


def is_in_region(lat: float, lon: float) -> bool:
    """Check if coordinates are in the broader Danube/Bratislava region."""
    return (REGION_BOUNDS['lat_min'] <= lat <= REGION_BOUNDS['lat_max'] and
            REGION_BOUNDS['lon_min'] <= lon <= REGION_BOUNDS['lon_max'])


# ============================================================
# VLM PROMPTS
# ============================================================

TRAJECTORY_PROMPT = """You are analyzing a sequence of screenshots from an agent performing a geographic navigation task in Google Earth.

TASK: Navigate to the Austria-Hungary-Slovakia tripoint (where three countries meet) on the Danube River and create a placemark.

The images are sampled chronologically from the agent's interaction.

Look for evidence of these workflow stages:
1. Google Earth is open with satellite imagery visible
2. Navigation toward Central Europe / Danube River region
3. Borders layer enabled (country boundaries visible as lines)
4. Zoom into the Bratislava / Danube area
5. Placemark creation dialog visible
6. Placemark positioned at a border junction

Assess:
1. GOOGLE_EARTH_VISIBLE: Is Google Earth's interface visible (toolbar, search, layers)?
2. DANUBE_REGION_SHOWN: At any point, is the Danube River area near Bratislava visible?
3. BORDERS_VISIBLE: Are country border lines visible in any frame?
4. PLACEMARK_DIALOG: Is a placemark creation dialog shown?
5. MEANINGFUL_WORKFLOW: Does the sequence show real navigation and placemark creation?

Respond in JSON format:
{
    "google_earth_visible": true/false,
    "danube_region_shown": true/false,
    "borders_visible": true/false,
    "placemark_dialog": true/false,
    "meaningful_workflow": true/false,
    "workflow_stages_observed": ["list what you see"],
    "confidence": "low"/"medium"/"high",
    "observations": "describe the progression"
}
"""

FINAL_SCREENSHOT_PROMPT = """You are verifying that an agent completed a placemark creation task in Google Earth.

TASK: Create a placemark named 'AUT-HUN-SVK Tripoint' at the Austria-Hungary-Slovakia border junction.

Look at this final screenshot and determine:

1. IS_GOOGLE_EARTH: Is this Google Earth Pro interface?
2. SHOWS_CENTRAL_EUROPE: Does the view show Central European region (Austria/Hungary/Slovakia area)?
3. PLACEMARK_VISIBLE: Is there a placemark icon visible on the map?
4. MY_PLACES_SHOWS_PLACEMARK: Does the left sidebar "My Places" section show a placemark entry?
5. BORDERS_OR_RIVER_VISIBLE: Are country borders or the Danube River visible?
6. NEAR_TRIPOINT_AREA: Does the view appear to be near where multiple borders meet?

Note: The tripoint is on the Danube River southeast of Bratislava. It's a point where three country borders converge.

Respond in JSON format:
{
    "is_google_earth": true/false,
    "shows_central_europe": true/false,
    "placemark_visible": true/false,
    "my_places_shows_placemark": true/false,
    "borders_or_river_visible": true/false,
    "near_tripoint_area": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "what you observe in the screenshot"
}
"""


# ============================================================
# MAIN VERIFICATION
# ============================================================

def verify_tripoint_border_marker(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that a placemark was created at the Austria-Hungary-Slovakia tripoint.
    
    Uses multiple verification signals:
    1. Programmatic KML analysis
    2. Anti-gaming timestamp checks
    3. VLM trajectory analysis
    4. VLM final screenshot verification
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    target_lat = metadata.get('target_latitude', TRIPOINT['lat'])
    target_lon = metadata.get('target_longitude', TRIPOINT['lon'])
    tolerance = metadata.get('tolerance_degrees', TRIPOINT['tolerance'])
    target_name = metadata.get('placemark_name', TRIPOINT['name'])
    
    feedback_parts = []
    details = {}
    score = 0
    
    # ============================================================
    # STEP 1: Load task result JSON
    # ============================================================
    result_data = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
        details['result_loaded'] = True
    except Exception as e:
        logger.warning(f"Failed to load task result: {e}")
        details['result_loaded'] = False
        details['result_error'] = str(e)
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ============================================================
    # STEP 2: Anti-gaming checks (15 points)
    # ============================================================
    file_modified = result_data.get('file_modified_during_task', False)
    placemark_added = result_data.get('placemark_added', False)
    task_start = result_data.get('task_start_time', 0)
    task_end = result_data.get('task_end_time', 0)
    
    details['file_modified'] = file_modified
    details['placemark_added'] = placemark_added
    
    if file_modified or placemark_added:
        score += 15
        feedback_parts.append("✅ File modified during task (anti-gaming passed)")
    else:
        feedback_parts.append("⚠️ No file modification detected")
    
    # ============================================================
    # STEP 3: Parse KML and check placemark (40 points total)
    # ============================================================
    kml_content = None
    placemarks = []
    
    # Try to get myplaces.kml
    temp_kml = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
    try:
        copy_from_env("/tmp/myplaces_final.kml", temp_kml.name)
        with open(temp_kml.name, 'r', encoding='utf-8', errors='ignore') as f:
            kml_content = f.read()
    except Exception as e:
        logger.warning(f"Failed to load myplaces.kml: {e}")
        # Try base64 content from result
        if result_data.get('myplaces_content_base64'):
            try:
                kml_content = base64.b64decode(result_data['myplaces_content_base64']).decode('utf-8', errors='ignore')
            except:
                pass
    finally:
        if os.path.exists(temp_kml.name):
            os.unlink(temp_kml.name)
    
    # Also try exported KML
    if not kml_content:
        temp_exported = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
        try:
            copy_from_env("/tmp/exported_placemark.kml", temp_exported.name)
            with open(temp_exported.name, 'r', encoding='utf-8', errors='ignore') as f:
                kml_content = f.read()
        except:
            pass
        finally:
            if os.path.exists(temp_exported.name):
                os.unlink(temp_exported.name)
    
    if kml_content:
        placemarks = parse_kml_placemarks(kml_content)
        details['placemarks_found'] = len(placemarks)
        details['placemark_names'] = [p.get('name', 'unnamed') for p in placemarks]
    else:
        details['placemarks_found'] = 0
        feedback_parts.append("⚠️ Could not read KML file")
    
    # Find target placemark
    target_placemark = None
    name_match_type = None
    
    for pm in placemarks:
        if pm.get('lat') is not None and pm.get('lon') is not None:
            is_match, match_type = check_name_match(pm.get('name', ''), target_name)
            if is_match:
                target_placemark = pm
                name_match_type = match_type
                break
    
    # If no name match, find closest placemark in region
    if target_placemark is None and placemarks:
        region_placemarks = [p for p in placemarks 
                           if p.get('lat') is not None and p.get('lon') is not None
                           and is_in_region(p['lat'], p['lon'])]
        if region_placemarks:
            target_placemark = min(region_placemarks,
                                  key=lambda p: calculate_distance(p['lat'], p['lon'], target_lat, target_lon))
            name_match_type = "location_only"
    
    # Score placemark criteria
    if target_placemark:
        details['target_placemark'] = target_placemark
        score += 15  # Placemark exists
        feedback_parts.append("✅ Placemark found")
        
        # Name check (10 points)
        if name_match_type == "exact":
            score += 10
            feedback_parts.append("✅ Name matches exactly")
        elif name_match_type == "partial":
            score += 7
            feedback_parts.append("✅ Name contains key elements")
        elif name_match_type == "loose":
            score += 4
            feedback_parts.append("⚠️ Name partially matches")
        else:
            feedback_parts.append(f"❌ Name mismatch: '{target_placemark.get('name', 'none')}'")
        
        # Coordinate accuracy (15 points)
        lat_diff = abs(target_placemark['lat'] - target_lat)
        lon_diff = abs(target_placemark['lon'] - target_lon)
        dist = calculate_distance(target_placemark['lat'], target_placemark['lon'], target_lat, target_lon)
        
        details['latitude_diff'] = lat_diff
        details['longitude_diff'] = lon_diff
        details['total_distance_deg'] = dist
        
        if lat_diff <= tolerance and lon_diff <= tolerance:
            score += 15
            feedback_parts.append(f"✅ Coordinates accurate (within {tolerance}°)")
        elif lat_diff <= tolerance * 2 and lon_diff <= tolerance * 2:
            score += 10
            feedback_parts.append(f"⚠️ Coordinates close (within {tolerance*2}°)")
        elif is_in_region(target_placemark['lat'], target_placemark['lon']):
            score += 5
            feedback_parts.append("⚠️ In correct region but not precise")
        else:
            feedback_parts.append("❌ Coordinates not accurate")
    else:
        feedback_parts.append("❌ No valid placemark found")
        details['target_placemark'] = None
    
    # ============================================================
    # STEP 4: VLM Trajectory Verification (25 points)
    # ============================================================
    vlm_trajectory_score = 0
    
    if query_vlm:
        try:
            # Import trajectory frame helpers
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            frames = sample_trajectory_frames(traj, n=5)
            
            if frames and len(frames) > 0:
                vlm_result = query_vlm(prompt=TRAJECTORY_PROMPT, images=frames)
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    details['vlm_trajectory'] = parsed
                    
                    # Score based on workflow stages
                    if parsed.get('google_earth_visible'):
                        vlm_trajectory_score += 5
                    if parsed.get('danube_region_shown'):
                        vlm_trajectory_score += 8
                    if parsed.get('borders_visible'):
                        vlm_trajectory_score += 4
                    if parsed.get('placemark_dialog'):
                        vlm_trajectory_score += 4
                    if parsed.get('meaningful_workflow'):
                        vlm_trajectory_score += 4
                    
                    score += vlm_trajectory_score
                    
                    if vlm_trajectory_score >= 15:
                        feedback_parts.append("✅ VLM: Workflow verified in trajectory")
                    elif vlm_trajectory_score >= 8:
                        feedback_parts.append("⚠️ VLM: Partial workflow observed")
                    else:
                        feedback_parts.append("⚠️ VLM: Limited workflow evidence")
                else:
                    feedback_parts.append("⚠️ VLM trajectory query failed")
            else:
                feedback_parts.append("⚠️ No trajectory frames available")
        except Exception as e:
            logger.warning(f"VLM trajectory verification failed: {e}")
            feedback_parts.append(f"⚠️ VLM trajectory error: {str(e)[:50]}")
    else:
        # Award some points if other criteria are strong
        if target_placemark and file_modified:
            score += 10
            feedback_parts.append("⚠️ VLM unavailable, partial credit for valid placemark")
    
    # ============================================================
    # STEP 5: VLM Final Screenshot (15 points)
    # ============================================================
    vlm_final_score = 0
    
    if query_vlm:
        try:
            from gym_anything.vlm import get_final_screenshot
            
            final_screenshot = get_final_screenshot(traj)
            
            if final_screenshot:
                vlm_result = query_vlm(prompt=FINAL_SCREENSHOT_PROMPT, image=final_screenshot)
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    details['vlm_final'] = parsed
                    
                    if parsed.get('is_google_earth'):
                        vlm_final_score += 3
                    if parsed.get('shows_central_europe'):
                        vlm_final_score += 3
                    if parsed.get('placemark_visible'):
                        vlm_final_score += 3
                    if parsed.get('my_places_shows_placemark'):
                        vlm_final_score += 3
                    if parsed.get('near_tripoint_area'):
                        vlm_final_score += 3
                    
                    score += vlm_final_score
                    
                    if vlm_final_score >= 10:
                        feedback_parts.append("✅ VLM: Final state verified")
                    elif vlm_final_score >= 6:
                        feedback_parts.append("⚠️ VLM: Partial final state match")
                else:
                    feedback_parts.append("⚠️ VLM final screenshot query failed")
            else:
                feedback_parts.append("⚠️ No final screenshot available")
        except Exception as e:
            logger.warning(f"VLM final verification failed: {e}")
    else:
        if target_placemark:
            score += 5
            feedback_parts.append("⚠️ VLM unavailable, partial credit")
    
    # ============================================================
    # STEP 6: Google Earth Running (5 points)
    # ============================================================
    if result_data.get('google_earth_running', False):
        score += 5
        feedback_parts.append("✅ Google Earth was running")
    else:
        feedback_parts.append("⚠️ Google Earth not detected running")
    
    # ============================================================
    # FINAL SCORING
    # ============================================================
    details['component_scores'] = {
        'anti_gaming': 15 if (file_modified or placemark_added) else 0,
        'placemark_found': 15 if target_placemark else 0,
        'name_match': 10 if name_match_type == "exact" else (7 if name_match_type == "partial" else 0),
        'coordinates': 15 if (target_placemark and lat_diff <= tolerance and lon_diff <= tolerance) else 0,
        'vlm_trajectory': vlm_trajectory_score,
        'vlm_final': vlm_final_score,
        'app_running': 5 if result_data.get('google_earth_running') else 0
    }
    
    # Key criteria for passing
    placemark_created = target_placemark is not None
    coords_reasonable = target_placemark and is_in_region(target_placemark['lat'], target_placemark['lon'])
    modified_during_task = file_modified or placemark_added
    
    passed = (score >= 60 and placemark_created and coords_reasonable) or (score >= 70)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "details": details
    }