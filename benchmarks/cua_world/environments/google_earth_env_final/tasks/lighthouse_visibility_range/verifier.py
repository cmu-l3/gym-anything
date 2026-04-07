#!/usr/bin/env python3
"""
Verifier for Lighthouse Visibility Range Documentation task.

MULTI-SIGNAL VERIFICATION:
1. KML file exists at correct path (10 points)
2. File created during task - anti-gaming (10 points)
3. Lighthouse placemark correctly named (10 points)
4. Lighthouse coordinates accurate (20 points)
5. Lighthouse description present (10 points)
6. Visibility limit placemark named (10 points)
7. Distance measurement accurate ~37km (20 points)
8. Direction correct - east over ocean (5 points)
9. Visibility description present (5 points)

VLM Trajectory Verification (bonus validation):
- Confirms workflow progression through screenshots
- Verifies ruler tool usage, placemark creation, save dialog

Pass threshold: 70 points with lighthouse coordinates accurate
"""

import json
import tempfile
import os
import math
import base64
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ================================================================
# CONSTANTS FROM TASK METADATA
# ================================================================
DEFAULT_LIGHTHOUSE_LAT = 35.2516
DEFAULT_LIGHTHOUSE_LON = -75.5289
DEFAULT_DISTANCE_KM = 37.04
DEFAULT_COORDINATE_TOLERANCE = 0.01  # degrees
DEFAULT_DISTANCE_TOLERANCE = 2.0  # km


# ================================================================
# HELPER FUNCTIONS
# ================================================================

def haversine_distance(lat1, lon1, lat2, lon2):
    """Calculate distance between two points in kilometers using Haversine formula."""
    R = 6371  # Earth's radius in km
    
    lat1_rad = math.radians(lat1)
    lat2_rad = math.radians(lat2)
    delta_lat = math.radians(lat2 - lat1)
    delta_lon = math.radians(lon2 - lon1)
    
    a = math.sin(delta_lat/2)**2 + \
        math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(delta_lon/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    
    return R * c


def parse_kml_from_content(kml_content):
    """Parse KML content and extract placemarks."""
    placemarks = []
    
    try:
        root = ET.fromstring(kml_content)
    except ET.ParseError as e:
        logger.error(f"Failed to parse KML: {e}")
        return placemarks
    
    # Handle KML namespace
    namespaces = {
        'kml': 'http://www.opengis.net/kml/2.2',
        '': 'http://www.opengis.net/kml/2.2'
    }
    
    # Try with namespace first
    for ns_prefix, ns_uri in [('kml:', namespaces['kml']), ('', '')]:
        if ns_prefix:
            pm_elements = root.findall(f'.//{{{ns_uri}}}Placemark')
        else:
            pm_elements = root.findall('.//Placemark')
        
        for pm in pm_elements:
            placemark = extract_placemark_data(pm, ns_uri)
            if placemark:
                placemarks.append(placemark)
        
        if placemarks:
            break
    
    return placemarks


def extract_placemark_data(pm_element, ns_uri=''):
    """Extract name, description, and coordinates from a placemark element."""
    ns = {'kml': ns_uri} if ns_uri else {}
    
    def find_elem(parent, tag):
        if ns_uri:
            elem = parent.find(f'{{{ns_uri}}}{tag}')
            if elem is None:
                elem = parent.find(tag)
        else:
            elem = parent.find(tag)
        return elem
    
    name_elem = find_elem(pm_element, 'name')
    desc_elem = find_elem(pm_element, 'description')
    
    # Find Point > coordinates
    point = find_elem(pm_element, 'Point')
    if point is None:
        # Try deeper search
        for child in pm_element.iter():
            if 'Point' in child.tag:
                point = child
                break
    
    if point is None:
        return None
    
    coords_elem = find_elem(point, 'coordinates')
    if coords_elem is None:
        for child in point.iter():
            if 'coordinates' in child.tag:
                coords_elem = child
                break
    
    if coords_elem is None or coords_elem.text is None:
        return None
    
    coords_text = coords_elem.text.strip()
    parts = coords_text.split(',')
    if len(parts) < 2:
        return None
    
    try:
        lon = float(parts[0].strip())
        lat = float(parts[1].strip())
    except ValueError:
        return None
    
    return {
        'name': name_elem.text.strip() if name_elem is not None and name_elem.text else "",
        'description': desc_elem.text.strip() if desc_elem is not None and desc_elem.text else "",
        'lon': lon,
        'lat': lat,
        'alt': float(parts[2].strip()) if len(parts) > 2 else 0
    }


# ================================================================
# VLM VERIFICATION
# ================================================================

VLM_TRAJECTORY_PROMPT = """You are analyzing a sequence of screenshots from an agent documenting lighthouse visibility range in Google Earth Pro.

The task required the agent to:
1. Navigate to Cape Hatteras Lighthouse on the North Carolina coast
2. Create a placemark at the lighthouse location
3. Use the Ruler tool to measure 20 nautical miles east over the ocean
4. Create a second placemark at the measurement endpoint
5. Save placemarks to a KML file

Analyze these screenshots (ordered chronologically) and assess:

1. NAVIGATION: Did the agent navigate to a coastal area that could be Cape Hatteras/Outer Banks?
   - Look for barrier island geography, Atlantic Ocean

2. PLACEMARK_CREATION: Was the Add Placemark dialog visible at any point?
   - Yellow pushpin icon, placemark properties dialog

3. RULER_TOOL: Was the Ruler/Measure tool used?
   - Ruler dialog, measurement line over water

4. SAVE_DIALOG: Was a Save/Export dialog used?
   - File save dialog, KML file selection

5. WORKFLOW_PROGRESSION: Do the screenshots show meaningful state changes through the task?

Respond in JSON format:
{
    "navigation_to_coast": true/false,
    "placemark_dialog_visible": true/false,
    "ruler_tool_used": true/false,
    "save_dialog_visible": true/false,
    "workflow_progression": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you observed"
}
"""


def verify_via_vlm(traj, query_vlm):
    """Verify task completion using VLM on trajectory frames."""
    if not query_vlm:
        return {"success": False, "error": "VLM not available"}
    
    # Import trajectory utilities
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    except ImportError:
        logger.warning("Could not import VLM utilities")
        return {"success": False, "error": "VLM utilities not available"}
    
    # Sample frames from trajectory (not just final)
    frames = sample_trajectory_frames(traj, n=5)
    final = get_final_screenshot(traj)
    
    if not frames and not final:
        return {"success": False, "error": "No screenshots available"}
    
    # Combine frames for analysis
    all_frames = frames if frames else []
    if final and final not in all_frames:
        all_frames.append(final)
    
    if not all_frames:
        return {"success": False, "error": "No frames to analyze"}
    
    try:
        result = query_vlm(
            prompt=VLM_TRAJECTORY_PROMPT,
            images=all_frames
        )
        
        if result.get("success"):
            parsed = result.get("parsed", {})
            
            # Score VLM criteria
            vlm_score = 0
            if parsed.get("navigation_to_coast"):
                vlm_score += 20
            if parsed.get("placemark_dialog_visible"):
                vlm_score += 20
            if parsed.get("ruler_tool_used"):
                vlm_score += 25
            if parsed.get("save_dialog_visible"):
                vlm_score += 20
            if parsed.get("workflow_progression"):
                vlm_score += 15
            
            return {
                "success": True,
                "score": vlm_score,
                "parsed": parsed,
                "frames_analyzed": len(all_frames)
            }
        else:
            return {"success": False, "error": result.get("error", "VLM query failed")}
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        return {"success": False, "error": str(e)}


# ================================================================
# MAIN VERIFICATION FUNCTION
# ================================================================

def verify_lighthouse_visibility_range(traj, env_info, task_info):
    """
    Verify that the lighthouse visibility range was documented correctly.
    
    Uses multiple independent signals:
    1. KML file analysis (primary)
    2. Timestamp anti-gaming checks
    3. VLM trajectory verification (secondary)
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available for verification"
        }
    
    # Get metadata
    metadata = task_info.get('metadata', {})
    expected_kml_path = metadata.get('expected_kml_path', '/home/ga/Documents/cape_hatteras_visibility.kml')
    lighthouse_lat = metadata.get('lighthouse_lat', DEFAULT_LIGHTHOUSE_LAT)
    lighthouse_lon = metadata.get('lighthouse_lon', DEFAULT_LIGHTHOUSE_LON)
    expected_distance = metadata.get('expected_distance_km', DEFAULT_DISTANCE_KM)
    coord_tolerance = metadata.get('coordinate_tolerance_deg', DEFAULT_COORDINATE_TOLERANCE)
    dist_tolerance = metadata.get('distance_tolerance_km', DEFAULT_DISTANCE_TOLERANCE)
    
    feedback_parts = []
    score = 0
    details = {}
    
    # ================================================================
    # Copy result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Failed to read task result: {e}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    details['result'] = result
    
    # ================================================================
    # CRITERION 1: KML file exists (10 points)
    # ================================================================
    output_info = result.get('output_file', {})
    kml_exists = output_info.get('exists', False)
    
    if kml_exists:
        score += 10
        feedback_parts.append("✅ KML file exists")
    else:
        feedback_parts.append("❌ KML file not found")
        # Try to get KML from myplaces as fallback
        myplaces = result.get('myplaces', {})
        if myplaces.get('exists') and myplaces.get('content_base64'):
            feedback_parts.append("⚠️ Checking myplaces.kml as fallback")
    
    # ================================================================
    # CRITERION 2: File created during task - anti-gaming (10 points)
    # ================================================================
    created_during_task = output_info.get('created_during_task', False)
    
    if created_during_task:
        score += 10
        feedback_parts.append("✅ File created during task")
    elif kml_exists:
        feedback_parts.append("⚠️ File existed before task (possible pre-creation)")
    
    # ================================================================
    # Parse KML content
    # ================================================================
    kml_content = None
    placemarks = []
    
    if output_info.get('content_base64'):
        try:
            kml_content = base64.b64decode(output_info['content_base64']).decode('utf-8')
            placemarks = parse_kml_from_content(kml_content)
            details['placemarks_found'] = len(placemarks)
        except Exception as e:
            logger.error(f"Failed to parse KML: {e}")
    
    # Fallback to myplaces
    if not placemarks:
        myplaces = result.get('myplaces', {})
        if myplaces.get('content_base64'):
            try:
                myplaces_content = base64.b64decode(myplaces['content_base64']).decode('utf-8')
                placemarks = parse_kml_from_content(myplaces_content)
                if placemarks:
                    feedback_parts.append("⚠️ Using placemarks from myplaces.kml")
            except Exception as e:
                logger.error(f"Failed to parse myplaces: {e}")
    
    if len(placemarks) < 2:
        feedback_parts.append(f"❌ Need 2 placemarks, found {len(placemarks)}")
        # Can still get partial score from VLM
    
    # ================================================================
    # Find lighthouse and visibility placemarks
    # ================================================================
    lighthouse_pm = None
    visibility_pm = None
    
    lighthouse_keywords = ['hatteras', 'lighthouse', 'light', 'cape']
    visibility_keywords = ['visibility', 'limit', '20nm', '20 nm', 'range']
    
    for pm in placemarks:
        pm_name_lower = pm['name'].lower()
        
        # Check for lighthouse placemark
        if any(kw in pm_name_lower for kw in lighthouse_keywords):
            lighthouse_pm = pm
        # Check for visibility placemark
        elif any(kw in pm_name_lower for kw in visibility_keywords):
            visibility_pm = pm
    
    # If no match by name, try by coordinates
    if not lighthouse_pm and not visibility_pm and len(placemarks) >= 2:
        for pm in placemarks:
            dist_to_lighthouse = haversine_distance(
                pm['lat'], pm['lon'], lighthouse_lat, lighthouse_lon
            )
            if dist_to_lighthouse < 2.0:  # Within 2km of expected lighthouse
                lighthouse_pm = pm
            elif dist_to_lighthouse > 30:  # Far from lighthouse
                visibility_pm = pm
    
    # ================================================================
    # CRITERION 3: Lighthouse placemark named correctly (10 points)
    # ================================================================
    if lighthouse_pm:
        if 'cape hatteras' in lighthouse_pm['name'].lower() or \
           'hatteras light' in lighthouse_pm['name'].lower():
            score += 10
            feedback_parts.append(f"✅ Lighthouse named: {lighthouse_pm['name']}")
        else:
            score += 5
            feedback_parts.append(f"⚠️ Lighthouse name partial: {lighthouse_pm['name']}")
    else:
        feedback_parts.append("❌ Lighthouse placemark not found")
    
    # ================================================================
    # CRITERION 4: Lighthouse coordinates accurate (20 points)
    # ================================================================
    lighthouse_coords_accurate = False
    
    if lighthouse_pm:
        lat_diff = abs(lighthouse_pm['lat'] - lighthouse_lat)
        lon_diff = abs(lighthouse_pm['lon'] - lighthouse_lon)
        
        details['lighthouse_coords'] = {
            'found': [lighthouse_pm['lat'], lighthouse_pm['lon']],
            'expected': [lighthouse_lat, lighthouse_lon],
            'diff': [lat_diff, lon_diff]
        }
        
        if lat_diff <= coord_tolerance and lon_diff <= coord_tolerance:
            score += 20
            lighthouse_coords_accurate = True
            feedback_parts.append(f"✅ Lighthouse coords accurate ({lighthouse_pm['lat']:.4f}, {lighthouse_pm['lon']:.4f})")
        elif lat_diff <= coord_tolerance * 2 and lon_diff <= coord_tolerance * 2:
            score += 12
            lighthouse_coords_accurate = True
            feedback_parts.append(f"⚠️ Lighthouse coords close ({lighthouse_pm['lat']:.4f}, {lighthouse_pm['lon']:.4f})")
        else:
            feedback_parts.append(f"❌ Lighthouse coords off ({lighthouse_pm['lat']:.4f}, {lighthouse_pm['lon']:.4f})")
    
    # ================================================================
    # CRITERION 5: Lighthouse description present (10 points)
    # ================================================================
    if lighthouse_pm and lighthouse_pm.get('description'):
        desc_lower = lighthouse_pm['description'].lower()
        has_height = 'height' in desc_lower or '64' in desc_lower or 'meter' in desc_lower
        has_range = 'range' in desc_lower or '20' in desc_lower or 'nm' in desc_lower
        
        if has_height and has_range:
            score += 10
            feedback_parts.append("✅ Lighthouse description complete")
        elif has_height or has_range:
            score += 5
            feedback_parts.append("⚠️ Lighthouse description partial")
        else:
            score += 2
            feedback_parts.append("⚠️ Lighthouse has description but missing key info")
    else:
        feedback_parts.append("❌ Lighthouse description missing")
    
    # ================================================================
    # CRITERION 6: Visibility limit placemark named (10 points)
    # ================================================================
    if visibility_pm:
        if 'visibility' in visibility_pm['name'].lower() or \
           '20nm' in visibility_pm['name'].lower() or \
           'limit' in visibility_pm['name'].lower():
            score += 10
            feedback_parts.append(f"✅ Visibility placemark: {visibility_pm['name']}")
        else:
            score += 5
            feedback_parts.append(f"⚠️ Second placemark found: {visibility_pm['name']}")
    else:
        feedback_parts.append("❌ Visibility limit placemark not found")
    
    # ================================================================
    # CRITERION 7: Distance measurement accurate (20 points)
    # ================================================================
    if lighthouse_pm and visibility_pm:
        actual_distance = haversine_distance(
            lighthouse_pm['lat'], lighthouse_pm['lon'],
            visibility_pm['lat'], visibility_pm['lon']
        )
        
        details['distance'] = {
            'actual_km': actual_distance,
            'expected_km': expected_distance,
            'diff_km': abs(actual_distance - expected_distance)
        }
        
        if abs(actual_distance - expected_distance) <= dist_tolerance:
            score += 20
            feedback_parts.append(f"✅ Distance accurate: {actual_distance:.2f} km (expected ~{expected_distance} km)")
        elif abs(actual_distance - expected_distance) <= dist_tolerance * 2:
            score += 12
            feedback_parts.append(f"⚠️ Distance close: {actual_distance:.2f} km (expected ~{expected_distance} km)")
        elif actual_distance > 20 and actual_distance < 60:
            score += 6
            feedback_parts.append(f"⚠️ Distance in range: {actual_distance:.2f} km")
        else:
            feedback_parts.append(f"❌ Distance incorrect: {actual_distance:.2f} km")
    
    # ================================================================
    # CRITERION 8: Direction correct - east over ocean (5 points)
    # ================================================================
    if lighthouse_pm and visibility_pm:
        # East means more negative longitude (western hemisphere)
        is_east = visibility_pm['lon'] < lighthouse_pm['lon']
        
        if is_east:
            score += 5
            feedback_parts.append("✅ Direction correct (east over ocean)")
        else:
            feedback_parts.append("❌ Direction incorrect (should be east)")
        
        details['direction'] = {
            'lighthouse_lon': lighthouse_pm['lon'],
            'visibility_lon': visibility_pm['lon'],
            'is_east': is_east
        }
    
    # ================================================================
    # CRITERION 9: Visibility description present (5 points)
    # ================================================================
    if visibility_pm and visibility_pm.get('description'):
        desc_lower = visibility_pm['description'].lower()
        if 'visibility' in desc_lower or 'range' in desc_lower or 'maximum' in desc_lower:
            score += 5
            feedback_parts.append("✅ Visibility description present")
        else:
            score += 2
            feedback_parts.append("⚠️ Visibility has description")
    else:
        feedback_parts.append("❌ Visibility description missing")
    
    # ================================================================
    # VLM TRAJECTORY VERIFICATION (bonus validation)
    # ================================================================
    vlm_result = verify_via_vlm(traj, query_vlm)
    details['vlm_verification'] = vlm_result
    
    if vlm_result.get('success'):
        vlm_score = vlm_result.get('score', 0)
        confidence = vlm_result.get('parsed', {}).get('confidence', 'low')
        
        # VLM provides confidence boost, not primary score
        if vlm_score >= 60 and confidence in ['medium', 'high']:
            feedback_parts.append(f"✅ VLM confirms workflow (confidence: {confidence})")
        elif vlm_score >= 40:
            feedback_parts.append(f"⚠️ VLM partial confirmation")
    else:
        feedback_parts.append(f"⚠️ VLM verification skipped: {vlm_result.get('error', 'unavailable')}")
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    # Key criteria: lighthouse coordinates must be accurate AND file must exist
    key_criteria_met = lighthouse_coords_accurate and (kml_exists or len(placemarks) >= 2)
    passed = score >= 70 and key_criteria_met
    
    details['score_breakdown'] = {
        'kml_exists': 10 if kml_exists else 0,
        'created_during_task': 10 if created_during_task else 0,
        'lighthouse_name': 10 if lighthouse_pm else 0,
        'lighthouse_coords': 20 if lighthouse_coords_accurate else 0,
        'lighthouse_desc': 10 if (lighthouse_pm and lighthouse_pm.get('description')) else 0,
        'visibility_name': 10 if visibility_pm else 0,
        'distance': 'calculated above',
        'direction': 5 if (lighthouse_pm and visibility_pm) else 0,
        'visibility_desc': 5 if (visibility_pm and visibility_pm.get('description')) else 0
    }
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "details": details
    }