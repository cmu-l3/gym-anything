#!/usr/bin/env python3
"""
Verifier for Crater Lake Caldera Dimensions task.

VERIFICATION STRATEGY (Multi-Signal):
1. KML file exists at correct path (10 points)
2. File created during task - anti-gaming (10 points)
3. Contains 4 placemarks (15 points)
4. Placemarks have correct names (10 points)
5. All placemarks within Crater Lake bounds (15 points)
6. Cardinal directions correct - N has max lat, etc. (40 points total, 10 each)
7. VLM trajectory verification - shows workflow (bonus/tiebreaker)

Pass threshold: 70 points with at least 3 cardinal placemarks correct
"""

import json
import tempfile
import os
import re
import base64
import logging
import xml.etree.ElementTree as ET
from typing import Dict, Any, List, Optional, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ================================================================
# KML NAMESPACE HANDLING
# ================================================================
KML_NAMESPACES = {
    'kml': 'http://www.opengis.net/kml/2.2',
    'gx': 'http://www.google.com/kml/ext/2.2'
}


def parse_kml_content(kml_content: str) -> List[Dict[str, Any]]:
    """Parse KML content and extract placemarks with coordinates."""
    placemarks = []
    
    try:
        root = ET.fromstring(kml_content)
        
        # Try with namespace first
        for ns_prefix in ['kml:', '']:
            placemark_tag = f'{{{KML_NAMESPACES["kml"]}}}Placemark' if ns_prefix else 'Placemark'
            name_tag = f'{{{KML_NAMESPACES["kml"]}}}name' if ns_prefix else 'name'
            coords_tag = f'{{{KML_NAMESPACES["kml"]}}}coordinates' if ns_prefix else 'coordinates'
            
            for pm in root.iter(placemark_tag):
                name_elem = pm.find(f'.//{name_tag}') if ns_prefix else pm.find('.//name')
                coords_elem = pm.find(f'.//{coords_tag}') if ns_prefix else pm.find('.//coordinates')
                
                # Also try without namespace prefix in find
                if name_elem is None:
                    name_elem = pm.find('.//name')
                if coords_elem is None:
                    coords_elem = pm.find('.//coordinates')
                
                if name_elem is not None and coords_elem is not None:
                    name = name_elem.text.strip() if name_elem.text else ""
                    coords_text = coords_elem.text.strip() if coords_elem.text else ""
                    
                    # Parse coordinates (lon,lat,alt format in KML)
                    parts = coords_text.replace('\n', '').replace('\t', '').split(',')
                    if len(parts) >= 2:
                        try:
                            lon = float(parts[0].strip())
                            lat = float(parts[1].strip())
                            placemarks.append({
                                'name': name,
                                'latitude': lat,
                                'longitude': lon
                            })
                        except ValueError:
                            logger.warning(f"Could not parse coordinates: {coords_text}")
            
            if placemarks:
                break
                
    except ET.ParseError as e:
        logger.error(f"XML parse error: {e}")
    except Exception as e:
        logger.error(f"Error parsing KML: {e}")
    
    return placemarks


def check_folder_in_kml(kml_content: str) -> Tuple[bool, str]:
    """Check if KML contains a folder with 'Crater Lake' in name."""
    try:
        root = ET.fromstring(kml_content)
        
        # Search for Folder elements
        for folder in root.iter():
            if 'Folder' in folder.tag:
                for name_elem in folder.iter():
                    if 'name' in name_elem.tag and name_elem.text:
                        if 'crater' in name_elem.text.lower() and 'lake' in name_elem.text.lower():
                            return True, name_elem.text
        
        return False, ""
    except Exception as e:
        logger.error(f"Error checking folder: {e}")
        return False, ""


def categorize_placemark(name: str) -> Optional[str]:
    """Categorize a placemark by its cardinal direction based on name."""
    name_lower = name.lower()
    
    patterns = {
        'north': ['north rim extreme', 'north rim', 'north extreme', 'n rim', 'north'],
        'south': ['south rim extreme', 'south rim', 'south extreme', 's rim', 'south'],
        'east': ['east rim extreme', 'east rim', 'east extreme', 'e rim', 'east'],
        'west': ['west rim extreme', 'west rim', 'west extreme', 'w rim', 'west']
    }
    
    for direction, keywords in patterns.items():
        for keyword in keywords:
            if keyword in name_lower:
                return direction
    
    return None


# ================================================================
# VLM VERIFICATION
# ================================================================

TRAJECTORY_VERIFICATION_PROMPT = """You are analyzing a sequence of screenshots from an agent performing a task in Google Earth Pro.

TASK: The agent was asked to document Crater Lake caldera dimensions by:
1. Navigating to Crater Lake, Oregon
2. Placing 4 placemarks at the cardinal rim extremes (North, South, East, West)
3. Measuring diameters with the ruler tool
4. Organizing placemarks in a folder
5. Exporting as KML

Analyze these chronological screenshots and determine:

1. NAVIGATED_TO_CRATER_LAKE: Did the agent navigate to Crater Lake? Look for:
   - A distinctive circular lake (deep blue) surrounded by rim
   - Location in mountainous Oregon terrain
   - The search showing "Crater Lake" or similar

2. PLACEMARKS_CREATED: Are there placemarks visible on the map?
   - Look for placemark pins/markers around the crater rim
   - Look for placemark dialog boxes being filled in

3. RULER_TOOL_USED: Was the ruler/measurement tool used?
   - Look for measurement lines or the ruler dialog
   - Look for distance readings

4. WORKFLOW_PROGRESSION: Do the screenshots show meaningful task progression?
   - Not just the same screen repeated
   - Shows different stages of the task

Respond in JSON format:
{
    "navigated_to_crater_lake": true/false,
    "placemarks_visible": true/false,
    "ruler_tool_used": true/false,
    "workflow_progression": true/false,
    "stages_observed": ["list what you see"],
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see across the frames"
}
"""


def verify_via_vlm(traj: Dict[str, Any], query_vlm) -> Dict[str, Any]:
    """Use VLM to verify task completion via trajectory frames."""
    if not query_vlm:
        return {"success": False, "error": "VLM not available"}
    
    try:
        # Import trajectory frame sampling
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        # Get trajectory frames (sample across the episode)
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        
        if final and final not in frames:
            frames.append(final)
        
        if not frames:
            return {"success": False, "error": "No trajectory frames available"}
        
        # Query VLM with multiple frames
        result = query_vlm(
            prompt=TRAJECTORY_VERIFICATION_PROMPT,
            images=frames
        )
        
        if not result.get("success"):
            return {"success": False, "error": result.get("error", "VLM query failed")}
        
        parsed = result.get("parsed", {})
        return {
            "success": True,
            "navigated": parsed.get("navigated_to_crater_lake", False),
            "placemarks_visible": parsed.get("placemarks_visible", False),
            "ruler_used": parsed.get("ruler_tool_used", False),
            "workflow_ok": parsed.get("workflow_progression", False),
            "confidence": parsed.get("confidence", "low"),
            "observations": parsed.get("observations", "")
        }
        
    except ImportError:
        logger.warning("Could not import VLM utilities")
        return {"success": False, "error": "VLM utilities not available"}
    except Exception as e:
        logger.error(f"VLM verification error: {e}")
        return {"success": False, "error": str(e)}


# ================================================================
# MAIN VERIFICATION FUNCTION
# ================================================================

def verify_crater_caldera_dimensions(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the Crater Lake caldera dimensions task.
    
    Uses multiple independent signals:
    1. KML file content analysis
    2. Timestamp verification (anti-gaming)
    3. Coordinate bounds checking
    4. Cardinal position verification
    5. VLM trajectory verification
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "❌ Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    
    # Crater Lake bounds from metadata
    BOUNDS = {
        'lat_min': metadata.get('crater_bounds_lat_min', 42.88),
        'lat_max': metadata.get('crater_bounds_lat_max', 43.01),
        'lon_min': metadata.get('crater_bounds_lon_min', -122.20),
        'lon_max': metadata.get('crater_bounds_lon_max', -122.03)
    }
    
    feedback_parts = []
    details = {}
    score = 0
    
    # ================================================================
    # COPY RESULT FILE FROM CONTAINER
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result file: {e}")
        return {"passed": False, "score": 0, "feedback": f"❌ Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    details['export_result'] = result
    
    # ================================================================
    # CRITERION 1: KML FILE EXISTS (10 points)
    # ================================================================
    output_exists = result.get('output_exists', False)
    
    if output_exists:
        score += 10
        feedback_parts.append("✅ KML file exists")
        details['kml_exists'] = True
    else:
        feedback_parts.append("❌ KML file not found at expected path")
        details['kml_exists'] = False
        # Can't verify further without the file
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: FILE CREATED DURING TASK (10 points) - Anti-gaming
    # ================================================================
    file_created = result.get('file_created_during_task', False)
    
    if file_created:
        score += 10
        feedback_parts.append("✅ File created during task")
        details['file_timing_valid'] = True
    else:
        feedback_parts.append("⚠️ File may have existed before task")
        details['file_timing_valid'] = False
    
    # ================================================================
    # PARSE KML CONTENT
    # ================================================================
    kml_base64 = result.get('kml_content_base64', '')
    placemarks = []
    
    if kml_base64:
        try:
            kml_content = base64.b64decode(kml_base64).decode('utf-8')
            placemarks = parse_kml_content(kml_content)
            has_folder, folder_name = check_folder_in_kml(kml_content)
            details['folder_found'] = has_folder
            details['folder_name'] = folder_name
        except Exception as e:
            logger.error(f"Failed to decode KML: {e}")
            # Try to copy KML directly
            temp_kml = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
            try:
                copy_from_env("/home/ga/Documents/crater_lake_dimensions.kml", temp_kml.name)
                with open(temp_kml.name, 'r') as f:
                    kml_content = f.read()
                placemarks = parse_kml_content(kml_content)
                has_folder, folder_name = check_folder_in_kml(kml_content)
                details['folder_found'] = has_folder
            except Exception as e2:
                logger.error(f"Failed to read KML directly: {e2}")
            finally:
                if os.path.exists(temp_kml.name):
                    os.unlink(temp_kml.name)
    
    details['placemarks_parsed'] = placemarks
    details['placemark_count'] = len(placemarks)
    
    # ================================================================
    # CRITERION 3: CONTAINS 4 PLACEMARKS (15 points)
    # ================================================================
    if len(placemarks) == 4:
        score += 15
        feedback_parts.append("✅ Contains 4 placemarks")
    elif len(placemarks) > 0:
        partial = min(10, len(placemarks) * 3)
        score += partial
        feedback_parts.append(f"⚠️ Contains {len(placemarks)} placemarks (expected 4)")
    else:
        feedback_parts.append("❌ No placemarks found in KML")
    
    # ================================================================
    # CRITERION 4: CORRECT PLACEMARK NAMES (10 points)
    # ================================================================
    categorized = {'north': None, 'south': None, 'east': None, 'west': None}
    names_matched = 0
    
    for pm in placemarks:
        direction = categorize_placemark(pm['name'])
        if direction and categorized[direction] is None:
            categorized[direction] = pm
            names_matched += 1
    
    if names_matched == 4:
        score += 10
        feedback_parts.append("✅ All placemark names correct")
        details['names_correct'] = True
    elif names_matched > 0:
        score += (names_matched * 2)
        feedback_parts.append(f"⚠️ {names_matched}/4 placemark names match expected pattern")
        details['names_correct'] = False
    else:
        feedback_parts.append("❌ No placemark names match expected pattern")
        details['names_correct'] = False
    
    details['categorized_placemarks'] = {k: v['name'] if v else None for k, v in categorized.items()}
    
    # ================================================================
    # CRITERION 5: ALL PLACEMARKS IN CRATER LAKE BOUNDS (15 points)
    # ================================================================
    in_bounds_count = 0
    for pm in placemarks:
        lat, lon = pm['latitude'], pm['longitude']
        if (BOUNDS['lat_min'] <= lat <= BOUNDS['lat_max'] and
            BOUNDS['lon_min'] <= lon <= BOUNDS['lon_max']):
            in_bounds_count += 1
    
    if in_bounds_count == len(placemarks) and len(placemarks) >= 4:
        score += 15
        feedback_parts.append("✅ All placemarks within Crater Lake bounds")
        details['all_in_bounds'] = True
    elif in_bounds_count > 0:
        partial = min(10, in_bounds_count * 3)
        score += partial
        feedback_parts.append(f"⚠️ {in_bounds_count}/{len(placemarks)} placemarks in bounds")
        details['all_in_bounds'] = False
    else:
        feedback_parts.append("❌ No placemarks within Crater Lake bounds")
        details['all_in_bounds'] = False
    
    details['in_bounds_count'] = in_bounds_count
    
    # ================================================================
    # CRITERION 6: CARDINAL DIRECTIONS CORRECT (40 points, 10 each)
    # ================================================================
    cardinal_correct = {'north': False, 'south': False, 'east': False, 'west': False}
    
    if len(placemarks) >= 4:
        lats = [pm['latitude'] for pm in placemarks]
        lons = [pm['longitude'] for pm in placemarks]
        
        max_lat = max(lats)
        min_lat = min(lats)
        max_lon = max(lons)  # Least negative (easternmost)
        min_lon = min(lons)  # Most negative (westernmost)
        
        # Check North: should have maximum latitude
        if categorized['north'] and abs(categorized['north']['latitude'] - max_lat) < 0.001:
            score += 10
            cardinal_correct['north'] = True
            feedback_parts.append("✅ North placemark has max latitude")
        else:
            feedback_parts.append("❌ North placemark NOT at max latitude")
        
        # Check South: should have minimum latitude
        if categorized['south'] and abs(categorized['south']['latitude'] - min_lat) < 0.001:
            score += 10
            cardinal_correct['south'] = True
            feedback_parts.append("✅ South placemark has min latitude")
        else:
            feedback_parts.append("❌ South placemark NOT at min latitude")
        
        # Check East: should have maximum longitude (least negative)
        if categorized['east'] and abs(categorized['east']['longitude'] - max_lon) < 0.001:
            score += 10
            cardinal_correct['east'] = True
            feedback_parts.append("✅ East placemark has max longitude")
        else:
            feedback_parts.append("❌ East placemark NOT at max longitude")
        
        # Check West: should have minimum longitude (most negative)
        if categorized['west'] and abs(categorized['west']['longitude'] - min_lon) < 0.001:
            score += 10
            cardinal_correct['west'] = True
            feedback_parts.append("✅ West placemark has min longitude")
        else:
            feedback_parts.append("❌ West placemark NOT at min longitude")
    else:
        feedback_parts.append("❌ Not enough placemarks to verify cardinal positions")
    
    details['cardinal_correct'] = cardinal_correct
    correct_cardinals = sum(cardinal_correct.values())
    details['correct_cardinal_count'] = correct_cardinals
    
    # ================================================================
    # BONUS: FOLDER STRUCTURE (5 points)
    # ================================================================
    if details.get('folder_found', False):
        score += 5
        feedback_parts.append("✅ Folder structure present")
    
    # ================================================================
    # VLM TRAJECTORY VERIFICATION (informational, not scored)
    # ================================================================
    vlm_result = verify_via_vlm(traj, query_vlm)
    details['vlm_verification'] = vlm_result
    
    if vlm_result.get('success'):
        vlm_info = []
        if vlm_result.get('navigated'):
            vlm_info.append("navigated to Crater Lake")
        if vlm_result.get('placemarks_visible'):
            vlm_info.append("placemarks visible")
        if vlm_result.get('ruler_used'):
            vlm_info.append("ruler tool used")
        if vlm_result.get('workflow_ok'):
            vlm_info.append("good workflow progression")
        
        if vlm_info:
            feedback_parts.append(f"📸 VLM observed: {', '.join(vlm_info)}")
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    # Pass requires: 70+ points AND at least 3 cardinal placemarks correct
    passed = (score >= 70) and (correct_cardinals >= 3)
    
    # Cap score at 100
    score = min(100, score)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }


if __name__ == '__main__':
    # Test with mock data
    print("Crater Lake Caldera Dimensions Verifier")
    print("Run via framework for actual verification")