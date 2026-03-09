#!/usr/bin/env python3
"""
Verifier for Poverty Point Archaeological Survey task.

ROBUST MULTI-SIGNAL VERIFICATION:
1. KML file exists (10 points)
2. KML has valid structure (10 points)
3. Mound A placemark present and correctly located (15 points)
4. Central Plaza placemark present and correctly located (15 points)
5. Path element exists with sufficient points (15 points)
6. Path in correct location (10 points)
7. Measurement evidence (15 points)
8. VLM trajectory verification - workflow progression (10 points)

Pass threshold: 60 points AND (KML exists AND at least one correct placemark)
"""

import json
import tempfile
import os
import math
import logging
import xml.etree.ElementTree as ET
from typing import Dict, Any, Optional, List, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ================================================================
# CONSTANTS
# ================================================================

# Target coordinates for Poverty Point features
MOUND_A = {"lat": 32.6369, "lon": -91.4131, "tolerance_m": 500}
CENTRAL_PLAZA = {"lat": 32.6345, "lon": -91.4067, "tolerance_m": 300}
SITE_BOUNDS = {
    "north": 32.645,
    "south": 32.625,
    "east": -91.395,
    "west": -91.420
}
EXPECTED_RING_DIAMETER_M = 1200
DIAMETER_TOLERANCE_PERCENT = 20


# ================================================================
# HELPER FUNCTIONS
# ================================================================

def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate distance between two coordinates in meters."""
    R = 6371000  # Earth's radius in meters
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)
    
    a = math.sin(delta_phi/2)**2 + \
        math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    
    return R * c


def is_within_bounds(lat: float, lon: float, bounds: Dict) -> bool:
    """Check if coordinates are within site bounds."""
    return (bounds["south"] <= lat <= bounds["north"] and
            bounds["west"] <= lon <= bounds["east"])


def parse_coordinates(coord_string: str) -> Optional[Dict]:
    """Parse KML coordinate string (lon,lat,alt) into dict."""
    try:
        parts = coord_string.strip().split(',')
        if len(parts) >= 2:
            return {"lon": float(parts[0]), "lat": float(parts[1])}
    except (ValueError, IndexError):
        pass
    return None


def parse_kml_file(kml_content: str) -> Tuple[Optional[ET.Element], Dict]:
    """Parse KML content and return root element and namespace."""
    try:
        root = ET.fromstring(kml_content)
        
        # Handle KML namespace
        ns = {'kml': 'http://www.opengis.net/kml/2.2'}
        if root.tag.startswith('{'):
            ns_uri = root.tag[1:root.tag.index('}')]
            ns = {'kml': ns_uri}
        
        return root, ns
    except ET.ParseError as e:
        logger.error(f"KML parse error: {e}")
        return None, {}


# ================================================================
# VLM VERIFICATION
# ================================================================

TRAJECTORY_VERIFICATION_PROMPT = """You are analyzing screenshots from an agent performing an archaeological survey task in Google Earth Pro.

TASK: Create an archaeological survey of Poverty Point, a prehistoric earthwork site in Louisiana.
The site features:
- Concentric curved ridges (partial circles like an amphitheater)
- A large mound on the western edge (Mound A / Bird Mound)
- Located in a forested area

For successful completion, the agent should:
1. Navigate to Poverty Point (distinctive concentric ridge patterns visible)
2. Create placemarks (yellow pushpin icons should appear)
3. Draw a path along the ridges
4. Use measurement tool (ruler)
5. Save/export to KML file

Analyze these trajectory screenshots and assess:

1. CORRECT_LOCATION: Is the view showing Poverty Point? Look for concentric curved earthwork ridges forming partial circles in a forested area.

2. PLACEMARKS_CREATED: Are there yellow placemark icons visible on the map?

3. PATH_OR_LINE_DRAWN: Is there evidence of a path (yellow line) or measurement line drawn on the map?

4. SAVE_DIALOG_SHOWN: Is there a save/export dialog visible in any frame?

5. MEANINGFUL_WORKFLOW: Do the frames show progression through multiple steps (not stuck on one screen)?

Respond in JSON format:
{
    "correct_location": true/false,
    "placemarks_visible": true/false,
    "path_or_line_visible": true/false,
    "save_dialog_shown": true/false,
    "meaningful_workflow": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see in the trajectory"
}
"""


def verify_via_vlm(traj: Dict[str, Any], query_vlm) -> Dict[str, Any]:
    """Verify task completion using VLM on trajectory frames."""
    if not query_vlm:
        return {"success": False, "error": "VLM not available", "score": 0}
    
    try:
        # Import trajectory frame sampling utilities
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        # Sample frames across the trajectory (not just final)
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        
        if final and final not in frames:
            frames.append(final)
        
        if not frames:
            return {"success": False, "error": "No frames available", "score": 0}
        
        # Query VLM with trajectory frames
        vlm_result = query_vlm(
            prompt=TRAJECTORY_VERIFICATION_PROMPT,
            images=frames
        )
        
        if not vlm_result.get("success"):
            return {"success": False, "error": vlm_result.get("error", "VLM query failed"), "score": 0}
        
        parsed = vlm_result.get("parsed", {})
        
        # Calculate score from VLM criteria
        criteria_met = sum([
            parsed.get("correct_location", False),
            parsed.get("placemarks_visible", False),
            parsed.get("path_or_line_visible", False),
            parsed.get("save_dialog_shown", False),
            parsed.get("meaningful_workflow", False)
        ])
        
        confidence = parsed.get("confidence", "low")
        confidence_mult = {"high": 1.0, "medium": 0.8, "low": 0.6}.get(confidence, 0.6)
        
        vlm_score = int((criteria_met / 5) * 10 * confidence_mult)
        
        return {
            "success": True,
            "score": vlm_score,
            "details": parsed,
            "frames_analyzed": len(frames)
        }
        
    except ImportError:
        logger.warning("VLM utilities not available, skipping VLM verification")
        return {"success": False, "error": "VLM utilities not available", "score": 0}
    except Exception as e:
        logger.error(f"VLM verification error: {e}")
        return {"success": False, "error": str(e), "score": 0}


# ================================================================
# MAIN VERIFICATION FUNCTION
# ================================================================

def verify_poverty_point_survey(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the Poverty Point Archaeological Survey task.
    
    Uses multiple independent signals:
    1. Programmatic KML analysis
    2. VLM trajectory verification
    3. Timestamp anti-gaming checks
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/Documents/poverty_point_survey.kml')
    
    feedback_parts = []
    score = 0
    max_score = 100
    details = {}
    
    # ================================================================
    # COPY RESULT FILES FROM CONTAINER
    # ================================================================
    
    # Copy task result JSON
    result_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", result_temp.name)
        with open(result_temp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy task result: {e}")
        result = {}
    finally:
        if os.path.exists(result_temp.name):
            os.unlink(result_temp.name)
    
    details['export_result'] = result
    
    # Copy KML content if available
    kml_content = ""
    kml_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
    try:
        copy_from_env(expected_output_path, kml_temp.name)
        with open(kml_temp.name, 'r') as f:
            kml_content = f.read()
    except Exception as e:
        logger.info(f"Could not copy KML file: {e}")
    finally:
        if os.path.exists(kml_temp.name):
            os.unlink(kml_temp.name)
    
    # ================================================================
    # CRITERION 1: KML FILE EXISTS (10 points)
    # ================================================================
    output_exists = result.get('output_exists', False)
    
    if output_exists and kml_content:
        score += 10
        feedback_parts.append("✅ KML file exists")
        details['kml_exists'] = True
    else:
        feedback_parts.append("❌ KML file not found")
        details['kml_exists'] = False
        # Early exit if no KML
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # ANTI-GAMING: Check file was created during task
    # ================================================================
    file_created_during_task = result.get('file_created_during_task', False)
    
    if not file_created_during_task:
        feedback_parts.append("⚠️ File may predate task (possible gaming)")
        score = max(0, score - 10)  # Penalty
        details['timestamp_valid'] = False
    else:
        details['timestamp_valid'] = True
    
    # ================================================================
    # CRITERION 2: KML HAS VALID STRUCTURE (10 points)
    # ================================================================
    root, ns = parse_kml_file(kml_content)
    
    if root is not None:
        score += 10
        feedback_parts.append("✅ Valid KML structure")
        details['kml_valid'] = True
    else:
        feedback_parts.append("❌ Invalid KML XML")
        details['kml_valid'] = False
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # Find all placemarks
    placemarks = root.findall('.//kml:Placemark', ns)
    if not placemarks:
        placemarks = root.findall('.//Placemark')
    
    details['placemark_count'] = len(placemarks)
    
    # ================================================================
    # CRITERION 3: MOUND A PLACEMARK (15 points)
    # ================================================================
    mound_a_found = False
    mound_a_distance = None
    
    for pm in placemarks:
        name_elem = pm.find('kml:name', ns) or pm.find('name')
        if name_elem is not None:
            name_text = name_elem.text.lower() if name_elem.text else ""
            # Check for variations: "mound a", "bird mound", "mound_a", etc.
            if ('mound' in name_text and 'a' in name_text) or 'bird' in name_text:
                coord_elem = pm.find('.//kml:coordinates', ns) or pm.find('.//coordinates')
                if coord_elem is not None:
                    coords = parse_coordinates(coord_elem.text)
                    if coords:
                        dist = haversine_distance(
                            coords["lat"], coords["lon"],
                            MOUND_A["lat"], MOUND_A["lon"]
                        )
                        mound_a_distance = dist
                        if dist <= MOUND_A["tolerance_m"]:
                            mound_a_found = True
                            score += 15
                            feedback_parts.append(f"✅ Mound A placemark ({dist:.0f}m from target)")
                            break
    
    if not mound_a_found:
        if mound_a_distance is not None:
            feedback_parts.append(f"❌ Mound A placemark too far ({mound_a_distance:.0f}m)")
        else:
            feedback_parts.append("❌ Mound A placemark not found")
    
    details['mound_a_found'] = mound_a_found
    details['mound_a_distance'] = mound_a_distance
    
    # ================================================================
    # CRITERION 4: CENTRAL PLAZA PLACEMARK (15 points)
    # ================================================================
    plaza_found = False
    plaza_distance = None
    
    for pm in placemarks:
        name_elem = pm.find('kml:name', ns) or pm.find('name')
        if name_elem is not None:
            name_text = name_elem.text.lower() if name_elem.text else ""
            if 'plaza' in name_text or 'central' in name_text or 'center' in name_text:
                coord_elem = pm.find('.//kml:coordinates', ns) or pm.find('.//coordinates')
                if coord_elem is not None:
                    coords = parse_coordinates(coord_elem.text)
                    if coords:
                        dist = haversine_distance(
                            coords["lat"], coords["lon"],
                            CENTRAL_PLAZA["lat"], CENTRAL_PLAZA["lon"]
                        )
                        plaza_distance = dist
                        if dist <= CENTRAL_PLAZA["tolerance_m"]:
                            plaza_found = True
                            score += 15
                            feedback_parts.append(f"✅ Central Plaza placemark ({dist:.0f}m from target)")
                            break
    
    if not plaza_found:
        if plaza_distance is not None:
            feedback_parts.append(f"❌ Central Plaza placemark too far ({plaza_distance:.0f}m)")
        else:
            feedback_parts.append("❌ Central Plaza placemark not found")
    
    details['plaza_found'] = plaza_found
    details['plaza_distance'] = plaza_distance
    
    # ================================================================
    # CRITERION 5: PATH ELEMENT EXISTS (15 points)
    # ================================================================
    paths = root.findall('.//kml:LineString', ns)
    if not paths:
        paths = root.findall('.//LineString')
    
    path_found = False
    path_point_count = 0
    
    for ls in paths:
        coord_elem = ls.find('kml:coordinates', ns) or ls.find('coordinates')
        if coord_elem is not None and coord_elem.text:
            coord_text = coord_elem.text.strip()
            coord_pairs = coord_text.split()
            point_count = len(coord_pairs)
            if point_count >= 5:  # Require at least 5 points for a meaningful path
                path_found = True
                path_point_count = max(path_point_count, point_count)
                score += 15
                feedback_parts.append(f"✅ Path with {point_count} points")
                break
    
    if not path_found:
        if path_point_count > 0:
            feedback_parts.append(f"❌ Path too short ({path_point_count} points)")
        else:
            feedback_parts.append("❌ No path/LineString found")
    
    details['path_found'] = path_found
    details['path_point_count'] = path_point_count
    
    # ================================================================
    # CRITERION 6: PATH IN CORRECT LOCATION (10 points)
    # ================================================================
    path_in_bounds = False
    
    if path_found:
        for ls in paths:
            coord_elem = ls.find('kml:coordinates', ns) or ls.find('coordinates')
            if coord_elem is not None and coord_elem.text:
                coord_pairs = coord_elem.text.strip().split()
                valid_coords = 0
                for pair in coord_pairs[:15]:  # Check first 15 points
                    coords = parse_coordinates(pair)
                    if coords and is_within_bounds(coords["lat"], coords["lon"], SITE_BOUNDS):
                        valid_coords += 1
                
                if valid_coords >= 3:
                    path_in_bounds = True
                    score += 10
                    feedback_parts.append("✅ Path within site bounds")
                    break
    
    if path_found and not path_in_bounds:
        feedback_parts.append("❌ Path not within Poverty Point bounds")
    
    details['path_in_bounds'] = path_in_bounds
    
    # ================================================================
    # CRITERION 7: MEASUREMENT EVIDENCE (15 points)
    # ================================================================
    measurement_found = False
    measured_distance = None
    
    # Check for 2-point LineString (typical ruler measurement)
    for ls in paths:
        coord_elem = ls.find('kml:coordinates', ns) or ls.find('coordinates')
        if coord_elem is not None and coord_elem.text:
            coord_pairs = coord_elem.text.strip().split()
            if len(coord_pairs) == 2:
                c1 = parse_coordinates(coord_pairs[0])
                c2 = parse_coordinates(coord_pairs[1])
                if c1 and c2:
                    dist = haversine_distance(c1["lat"], c1["lon"], c2["lat"], c2["lon"])
                    measured_distance = dist
                    # Expected ~1200m, accept ±20%
                    min_expected = EXPECTED_RING_DIAMETER_M * (1 - DIAMETER_TOLERANCE_PERCENT/100)
                    max_expected = EXPECTED_RING_DIAMETER_M * (1 + DIAMETER_TOLERANCE_PERCENT/100)
                    if min_expected <= dist <= max_expected:
                        measurement_found = True
                        score += 15
                        feedback_parts.append(f"✅ Measurement ~{dist:.0f}m (expected ~1200m)")
                        break
    
    # Also check descriptions for measurement text
    if not measurement_found:
        for elem in root.iter():
            if elem.text:
                text = str(elem.text).lower()
                # Look for measurement values
                if any(x in text for x in ['1.2', '1200', '0.75', '750', 'km', 'kilometer', 'mile']):
                    measurement_found = True
                    score += 10  # Partial credit
                    feedback_parts.append("✅ Measurement reference found in KML (partial)")
                    break
    
    if not measurement_found:
        if measured_distance is not None:
            feedback_parts.append(f"❌ Measurement {measured_distance:.0f}m outside expected range")
        else:
            # Check for any 2-point line and give partial credit
            for ls in paths:
                coord_elem = ls.find('kml:coordinates', ns) or ls.find('coordinates')
                if coord_elem is not None and coord_elem.text:
                    if len(coord_elem.text.strip().split()) == 2:
                        score += 5
                        feedback_parts.append("⚠️ Measurement line found (distance unverified)")
                        measurement_found = True
                        break
            
            if not measurement_found:
                feedback_parts.append("❌ No measurement evidence found")
    
    details['measurement_found'] = measurement_found
    details['measured_distance'] = measured_distance
    
    # ================================================================
    # CRITERION 8: VLM TRAJECTORY VERIFICATION (10 points)
    # ================================================================
    vlm_result = verify_via_vlm(traj, query_vlm)
    details['vlm_verification'] = vlm_result
    
    if vlm_result.get('success'):
        vlm_score = vlm_result.get('score', 0)
        score += vlm_score
        vlm_details = vlm_result.get('details', {})
        
        if vlm_details.get('correct_location'):
            feedback_parts.append("✅ VLM: Correct location visible")
        if vlm_details.get('placemarks_visible'):
            feedback_parts.append("✅ VLM: Placemarks visible in trajectory")
        if vlm_details.get('meaningful_workflow'):
            feedback_parts.append("✅ VLM: Meaningful workflow progression")
    else:
        feedback_parts.append(f"⚠️ VLM verification skipped: {vlm_result.get('error', 'unknown')}")
    
    # ================================================================
    # DETERMINE PASS/FAIL
    # ================================================================
    # Pass requires:
    # 1. KML file exists
    # 2. At least one correctly-placed placemark (mound A OR plaza)
    # 3. Score >= 60
    
    has_correct_placemark = mound_a_found or plaza_found
    key_criteria_met = details.get('kml_exists', False) and has_correct_placemark
    passed = score >= 60 and key_criteria_met
    
    # Final summary
    feedback_parts.append(f"Score: {score}/{max_score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }