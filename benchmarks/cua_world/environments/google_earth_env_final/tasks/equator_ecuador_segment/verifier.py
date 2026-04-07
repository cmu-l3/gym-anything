#!/usr/bin/env python3
"""
Verifier for equator_ecuador_segment task.

Task: Create a path along the equator through Ecuador and document
the Mitad del Mundo monument, then export as KML.

Verification Strategy:
1. KML file exists and was created during task (anti-gaming)
2. KML contains required elements (folder, path, placemark)
3. Path follows the equator (latitude ~0°) through Ecuador
4. Path length is reasonable (~280-370 km)
5. Placemark is near Mitad del Mundo monument
6. VLM trajectory verification shows actual workflow

Multi-signal verification to prevent gaming.
"""

import json
import tempfile
import os
import re
import math
import logging
import xml.etree.ElementTree as ET
from typing import Dict, Any, List, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# =============================================================================
# CONSTANTS
# =============================================================================

EQUATOR_LATITUDE = 0.0
LATITUDE_TOLERANCE = 0.05  # degrees
ECUADOR_LON_WEST = -81.0
ECUADOR_LON_EAST = -74.5
EXPECTED_DISTANCE_MIN = 280  # km
EXPECTED_DISTANCE_MAX = 370  # km
MONUMENT_LAT = -0.002
MONUMENT_LON = -78.455
MONUMENT_TOLERANCE_KM = 5


# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate distance between two points in kilometers."""
    R = 6371  # Earth's radius in km
    lat1_rad = math.radians(lat1)
    lat2_rad = math.radians(lat2)
    delta_lat = math.radians(lat2 - lat1)
    delta_lon = math.radians(lon2 - lon1)
    
    a = math.sin(delta_lat/2)**2 + math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(delta_lon/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    return R * c


def parse_kml_coordinates(coord_string: str) -> List[Tuple[float, float, float]]:
    """Parse KML coordinate string into list of (lon, lat, alt) tuples."""
    coordinates = []
    coord_string = coord_string.strip()
    parts = re.split(r'\s+', coord_string)
    for part in parts:
        if ',' in part:
            values = part.split(',')
            if len(values) >= 2:
                try:
                    lon = float(values[0])
                    lat = float(values[1])
                    alt = float(values[2]) if len(values) > 2 else 0
                    coordinates.append((lon, lat, alt))
                except ValueError:
                    continue
    return coordinates


def calculate_path_length(coordinates: List[Tuple[float, float, float]]) -> float:
    """Calculate total path length in kilometers."""
    total = 0.0
    for i in range(1, len(coordinates)):
        lon1, lat1, _ = coordinates[i-1]
        lon2, lat2, _ = coordinates[i]
        total += haversine_distance(lat1, lon1, lat2, lon2)
    return total


def analyze_path_latitude(coordinates: List[Tuple[float, float, float]]) -> Dict:
    """Analyze how well the path follows the equator."""
    if not coordinates:
        return {"valid": False, "avg_lat": None, "max_deviation": None, "within_tolerance": False}
    
    latitudes = [coord[1] for coord in coordinates]
    avg_lat = sum(latitudes) / len(latitudes)
    max_deviation = max(abs(lat - EQUATOR_LATITUDE) for lat in latitudes)
    
    return {
        "valid": True,
        "avg_lat": avg_lat,
        "max_deviation": max_deviation,
        "within_tolerance": abs(avg_lat) <= LATITUDE_TOLERANCE
    }


def analyze_path_longitude_span(coordinates: List[Tuple[float, float, float]]) -> Dict:
    """Check if path spans Ecuador's longitude range."""
    if not coordinates:
        return {"valid": False, "covers_ecuador": False}
    
    longitudes = [coord[0] for coord in coordinates]
    min_lon = min(longitudes)
    max_lon = max(longitudes)
    span = abs(max_lon - min_lon)
    
    # Check if it covers most of Ecuador's width
    covers_ecuador = (min_lon <= -79.0 and max_lon >= -76.0) or span >= 3.0
    
    return {
        "valid": True,
        "min_lon": min_lon,
        "max_lon": max_lon,
        "span": span,
        "covers_ecuador": covers_ecuador
    }


def parse_kml_file(filepath: str) -> Dict:
    """Parse KML file and extract relevant elements."""
    result = {
        "parse_success": False,
        "has_folder": False,
        "folder_name": None,
        "has_path": False,
        "path_name": None,
        "path_coordinates": [],
        "has_placemark": False,
        "placemark_name": None,
        "placemark_coords": None,
        "placemark_description": None
    }
    
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        result["parse_success"] = True
        
        # Handle KML namespace
        ns = {'kml': 'http://www.opengis.net/kml/2.2'}
        
        def find_elements(tag):
            elements = root.findall(f".//{{{ns['kml']}}}{tag}")
            if not elements:
                elements = root.findall(f".//{tag}")
            return elements
        
        # Find folders
        folders = find_elements("Folder")
        if folders:
            result["has_folder"] = True
            for folder in folders:
                name_elem = folder.find(f"{{{ns['kml']}}}name") or folder.find("name")
                if name_elem is not None and name_elem.text:
                    result["folder_name"] = name_elem.text
                    break
        
        # Find paths (LineString)
        placemarks = find_elements("Placemark")
        for pm in placemarks:
            linestring = pm.find(f"{{{ns['kml']}}}LineString") or pm.find("LineString")
            if linestring is not None:
                result["has_path"] = True
                name_elem = pm.find(f"{{{ns['kml']}}}name") or pm.find("name")
                if name_elem is not None:
                    result["path_name"] = name_elem.text
                
                coords_elem = linestring.find(f"{{{ns['kml']}}}coordinates") or linestring.find("coordinates")
                if coords_elem is not None and coords_elem.text:
                    result["path_coordinates"] = parse_kml_coordinates(coords_elem.text)
                break
        
        # Find placemarks with Point (not LineString)
        for pm in placemarks:
            point = pm.find(f"{{{ns['kml']}}}Point") or pm.find("Point")
            if point is not None:
                result["has_placemark"] = True
                name_elem = pm.find(f"{{{ns['kml']}}}name") or pm.find("name")
                if name_elem is not None:
                    result["placemark_name"] = name_elem.text
                
                desc_elem = pm.find(f"{{{ns['kml']}}}description") or pm.find("description")
                if desc_elem is not None:
                    result["placemark_description"] = desc_elem.text
                
                coords_elem = point.find(f"{{{ns['kml']}}}coordinates") or point.find("coordinates")
                if coords_elem is not None and coords_elem.text:
                    coords = parse_kml_coordinates(coords_elem.text)
                    if coords:
                        result["placemark_coords"] = (coords[0][0], coords[0][1])
                break
                
    except ET.ParseError as e:
        logger.warning(f"XML parse error: {e}")
    except Exception as e:
        logger.warning(f"Error parsing KML: {e}")
    
    return result


# =============================================================================
# VLM PROMPTS
# =============================================================================

TRAJECTORY_VERIFICATION_PROMPT = """You are analyzing a sequence of screenshots from an agent performing a geographic documentation task in Google Earth.

TASK: Create a path along the equator (0° latitude) through Ecuador and document the Mitad del Mundo monument.

The images are sampled chronologically from the agent's interaction. For successful completion, the agent should:
1. Navigate to South America / Ecuador region
2. Create a path tool and trace along the equator (east-west line)
3. Navigate to central Ecuador near Quito (for the monument)
4. Create a placemark at the Mitad del Mundo location
5. Organize elements in a folder
6. Export/save as KML file

Analyze the screenshots and determine:
1. NAVIGATED_TO_ECUADOR: Did the agent navigate to Ecuador/South America area?
2. PATH_CREATION_VISIBLE: Is there evidence of path/line creation (ruler tool, path tool)?
3. EQUATOR_REGION_SHOWN: Do screenshots show the equatorial region (tropical area near 0° latitude)?
4. PLACEMARK_CREATED: Is there evidence of placemark creation?
5. EXPORT_DIALOG_SHOWN: Is there evidence of save/export dialog?
6. MEANINGFUL_WORKFLOW: Do the frames show real progression through the task?

Respond in JSON format:
{
    "navigated_to_ecuador": true/false,
    "path_creation_visible": true/false,
    "equator_region_shown": true/false,
    "placemark_created": true/false,
    "export_dialog_shown": true/false,
    "meaningful_workflow": true/false,
    "stages_observed": ["list what you see"],
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see across the frames"
}
"""

FINAL_STATE_PROMPT = """You are verifying the final state of a Google Earth task.

TASK: The agent should have created a path along the equator through Ecuador and a placemark at the Mitad del Mundo monument.

Look at this final screenshot and determine:
1. Is this Google Earth showing a map/satellite view?
2. Is the view showing Ecuador or South American region?
3. Are there visible paths/lines that could represent the equator trace?
4. Is there a visible placemark marker?
5. Are there any dialog boxes (save/export dialogs)?

Respond in JSON format:
{
    "is_google_earth": true/false,
    "shows_ecuador_region": true/false,
    "path_visible": true/false,
    "placemark_visible": true/false,
    "dialog_open": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief description of what you see"
}
"""


# =============================================================================
# MAIN VERIFICATION FUNCTION
# =============================================================================

def verify_equator_ecuador_segment(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that the equator path through Ecuador was created and exported correctly.
    
    Uses multi-signal verification:
    1. Programmatic KML file analysis
    2. VLM trajectory verification
    3. Anti-gaming timestamp checks
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    feedback_parts = []
    score = 0
    details = {}
    
    # =========================================================================
    # STEP 1: Copy and parse result JSON from container
    # =========================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        details['export_result'] = result
    except Exception as e:
        logger.warning(f"Failed to read result JSON: {e}")
        result = {}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # =========================================================================
    # CRITERION 1: KML file exists (10 points)
    # =========================================================================
    output_exists = result.get('output_exists', False)
    
    if output_exists:
        score += 10
        feedback_parts.append("✅ KML file exists (+10)")
        details['kml_exists'] = True
    else:
        feedback_parts.append("❌ KML file not found")
        details['kml_exists'] = False
        # Early exit if no file
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # =========================================================================
    # CRITERION 2: File created during task - anti-gaming (10 points)
    # =========================================================================
    file_created_during_task = result.get('file_created_during_task', False)
    
    if file_created_during_task:
        score += 10
        feedback_parts.append("✅ File created during task (+10)")
        details['created_during_task'] = True
    else:
        feedback_parts.append("⚠️ File may predate task")
        details['created_during_task'] = False
    
    # =========================================================================
    # STEP 2: Copy and parse the KML file
    # =========================================================================
    temp_kml = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
    kml_data = None
    try:
        copy_from_env("/tmp/ecuador_equator.kml", temp_kml.name)
        kml_data = parse_kml_file(temp_kml.name)
        details['kml_parsed'] = kml_data
    except Exception as e:
        logger.warning(f"Failed to copy/parse KML: {e}")
        kml_data = {"parse_success": False}
    finally:
        if os.path.exists(temp_kml.name):
            os.unlink(temp_kml.name)
    
    if not kml_data.get('parse_success', False):
        feedback_parts.append("❌ Failed to parse KML file")
        # Continue with what we have from export script
        kml_data = {
            "has_folder": result.get('kml_has_folder', False),
            "has_path": result.get('kml_has_path', False),
            "has_placemark": result.get('kml_has_placemark', False),
            "path_coordinates": []
        }
    
    # =========================================================================
    # CRITERION 3: Folder structure correct (10 points)
    # =========================================================================
    if kml_data.get('has_folder', False):
        score += 10
        folder_name = kml_data.get('folder_name', 'unknown')
        feedback_parts.append(f"✅ Folder present: {folder_name} (+10)")
        details['has_folder'] = True
    else:
        feedback_parts.append("❌ No folder structure found")
        details['has_folder'] = False
    
    # =========================================================================
    # CRITERION 4: Path present (15 points)
    # =========================================================================
    path_coords = kml_data.get('path_coordinates', [])
    
    if kml_data.get('has_path', False) and len(path_coords) >= 2:
        score += 15
        feedback_parts.append(f"✅ Path present with {len(path_coords)} points (+15)")
        details['has_path'] = True
        details['path_point_count'] = len(path_coords)
    else:
        feedback_parts.append("❌ No valid path found")
        details['has_path'] = False
    
    # =========================================================================
    # CRITERION 5: Path latitude accuracy (20 points)
    # =========================================================================
    if path_coords:
        lat_analysis = analyze_path_latitude(path_coords)
        details['latitude_analysis'] = lat_analysis
        
        if lat_analysis.get('within_tolerance', False):
            score += 20
            avg_lat = lat_analysis.get('avg_lat', 0)
            feedback_parts.append(f"✅ Path follows equator (avg lat: {avg_lat:.4f}°) (+20)")
            details['latitude_correct'] = True
        else:
            avg_lat = lat_analysis.get('avg_lat', 'N/A')
            feedback_parts.append(f"❌ Path latitude off target (avg: {avg_lat})")
            details['latitude_correct'] = False
    else:
        details['latitude_correct'] = False
    
    # =========================================================================
    # CRITERION 6: Path spans Ecuador (15 points)
    # =========================================================================
    if path_coords:
        lon_analysis = analyze_path_longitude_span(path_coords)
        details['longitude_analysis'] = lon_analysis
        
        if lon_analysis.get('covers_ecuador', False):
            score += 15
            span = lon_analysis.get('span', 0)
            feedback_parts.append(f"✅ Path spans Ecuador ({span:.2f}° longitude) (+15)")
            details['spans_ecuador'] = True
        else:
            feedback_parts.append("❌ Path does not adequately span Ecuador")
            details['spans_ecuador'] = False
    else:
        details['spans_ecuador'] = False
    
    # =========================================================================
    # CRITERION 7: Path length reasonable (10 points)
    # =========================================================================
    if path_coords:
        path_length = calculate_path_length(path_coords)
        details['path_length_km'] = path_length
        
        if EXPECTED_DISTANCE_MIN <= path_length <= EXPECTED_DISTANCE_MAX:
            score += 10
            feedback_parts.append(f"✅ Path length: {path_length:.1f} km (+10)")
            details['length_correct'] = True
        elif 200 <= path_length <= 450:
            score += 5
            feedback_parts.append(f"⚠️ Path length: {path_length:.1f} km (partial +5)")
            details['length_correct'] = False
        else:
            feedback_parts.append(f"❌ Path length {path_length:.1f} km outside expected range")
            details['length_correct'] = False
    else:
        details['length_correct'] = False
    
    # =========================================================================
    # CRITERION 8: Mitad del Mundo placemark (10 points total)
    # =========================================================================
    if kml_data.get('has_placemark', False):
        score += 5
        placemark_name = kml_data.get('placemark_name', 'unknown')
        feedback_parts.append(f"✅ Placemark present: {placemark_name} (+5)")
        details['has_placemark'] = True
        
        # Check location
        placemark_coords = kml_data.get('placemark_coords')
        if placemark_coords:
            lon, lat = placemark_coords
            distance = haversine_distance(lat, lon, MONUMENT_LAT, MONUMENT_LON)
            details['placemark_distance_km'] = distance
            
            if distance <= MONUMENT_TOLERANCE_KM:
                score += 5
                feedback_parts.append(f"✅ Placemark location correct ({distance:.2f} km from monument) (+5)")
                details['placemark_location_correct'] = True
            else:
                feedback_parts.append(f"⚠️ Placemark {distance:.2f} km from expected location")
                details['placemark_location_correct'] = False
    else:
        feedback_parts.append("❌ No placemark found")
        details['has_placemark'] = False
    
    # =========================================================================
    # CRITERION 9: VLM Trajectory Verification (remaining points, up to 100)
    # =========================================================================
    vlm_score = 0
    
    if query_vlm:
        try:
            # Import trajectory sampling functions
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Get trajectory frames
            trajectory_frames = sample_trajectory_frames(traj, n=5)
            final_screenshot = get_final_screenshot(traj)
            
            if trajectory_frames:
                # Query VLM on trajectory
                traj_result = query_vlm(
                    prompt=TRAJECTORY_VERIFICATION_PROMPT,
                    images=trajectory_frames
                )
                
                if traj_result.get('success'):
                    parsed = traj_result.get('parsed', {})
                    details['vlm_trajectory'] = parsed
                    
                    # Score based on workflow evidence
                    if parsed.get('navigated_to_ecuador', False):
                        vlm_score += 2
                    if parsed.get('path_creation_visible', False):
                        vlm_score += 2
                    if parsed.get('equator_region_shown', False):
                        vlm_score += 2
                    if parsed.get('placemark_created', False):
                        vlm_score += 2
                    if parsed.get('meaningful_workflow', False):
                        vlm_score += 2
                    
                    # Bonus for high confidence
                    if parsed.get('confidence') == 'high':
                        vlm_score = min(vlm_score + 2, 10)
                    
                    feedback_parts.append(f"✅ VLM trajectory verification (+{vlm_score})")
            
            # Also check final screenshot
            if final_screenshot:
                final_result = query_vlm(
                    prompt=FINAL_STATE_PROMPT,
                    image=final_screenshot
                )
                
                if final_result.get('success'):
                    details['vlm_final'] = final_result.get('parsed', {})
                    
        except ImportError:
            logger.warning("Could not import VLM utilities")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
    
    score += vlm_score
    
    # =========================================================================
    # FINAL SCORING
    # =========================================================================
    
    # Cap at 100
    score = min(score, 100)
    
    # Determine pass/fail
    # Must have: file exists, created during task, path with correct latitude
    key_criteria_met = (
        details.get('kml_exists', False) and
        details.get('has_path', False) and
        details.get('latitude_correct', False)
    )
    
    passed = score >= 70 and key_criteria_met
    
    # Build final feedback
    feedback = " | ".join(feedback_parts)
    feedback += f"\n\nTotal Score: {score}/100"
    if passed:
        feedback += "\n✅ TASK PASSED"
    else:
        feedback += "\n❌ TASK FAILED"
        if not key_criteria_met:
            feedback += " (key criteria not met: need valid path along equator)"
        elif score < 70:
            feedback += " (score below 70 threshold)"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }