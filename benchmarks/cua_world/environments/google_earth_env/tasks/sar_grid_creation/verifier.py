#!/usr/bin/env python3
"""
Verifier for SAR Grid Creation task.

MULTI-SIGNAL VERIFICATION:
1. KML file exists at expected path (10 points)
2. File created/modified DURING task - anti-gaming (10 points)
3. Folder structure with correct name (10 points)
4. Search boundary polygon exists (15 points)
5. Boundary size approximately 4 km² (10 points)
6. Divider paths exist (10 points)
7. Sector placemarks exist (15 points)
8. LKP placemark exists (10 points)
9. LKP coordinates near target location (10 points)

VLM TRAJECTORY VERIFICATION is used to confirm the agent actually
worked in Google Earth (not just created a fake KML file).

Pass threshold: 70 points with file created during task
"""

import json
import tempfile
import os
import math
import logging
import xml.etree.ElementTree as ET
from typing import Dict, Any, List, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# =============================================================================
# CONSTANTS
# =============================================================================

TARGET_LAT = 37.7436
TARGET_LON = -119.5919
COORDINATE_TOLERANCE_KM = 0.5
EXPECTED_AREA_MIN_KM2 = 3.5
EXPECTED_AREA_MAX_KM2 = 4.5


# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate distance between two points in km using Haversine formula."""
    R = 6371  # Earth's radius in km
    lat1_rad = math.radians(lat1)
    lat2_rad = math.radians(lat2)
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    
    a = math.sin(dlat/2)**2 + math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(dlon/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    return R * c


def parse_kml_coordinates(coord_string: str) -> List[Tuple[float, float, float]]:
    """Parse KML coordinate string into list of (lon, lat, alt) tuples."""
    coords = []
    if not coord_string:
        return coords
    for point in coord_string.strip().split():
        parts = point.split(',')
        if len(parts) >= 2:
            try:
                lon = float(parts[0])
                lat = float(parts[1])
                alt = float(parts[2]) if len(parts) > 2 else 0
                coords.append((lon, lat, alt))
            except ValueError:
                continue
    return coords


def calculate_polygon_area_km2(coords: List[Tuple[float, float, float]]) -> float:
    """Calculate approximate area of polygon in km² using shoelace formula."""
    if len(coords) < 3:
        return 0
    
    # Calculate center
    center_lat = sum(c[1] for c in coords) / len(coords)
    center_lon = sum(c[0] for c in coords) / len(coords)
    
    # Convert coordinates to local km
    local_coords = []
    for lon, lat, _ in coords:
        x = haversine_distance(center_lat, center_lon, center_lat, lon)
        if lon < center_lon:
            x = -x
        y = haversine_distance(center_lat, center_lon, lat, center_lon)
        if lat < center_lat:
            y = -y
        local_coords.append((x, y))
    
    # Shoelace formula
    n = len(local_coords)
    area = 0
    for i in range(n):
        j = (i + 1) % n
        area += local_coords[i][0] * local_coords[j][1]
        area -= local_coords[j][0] * local_coords[i][1]
    return abs(area) / 2


def parse_kml_file(kml_content: str) -> Dict[str, Any]:
    """Parse KML file and extract relevant elements."""
    result = {
        "valid": False,
        "folders": [],
        "placemarks": [],
        "polygons": [],
        "paths": [],
        "error": None
    }
    
    try:
        root = ET.fromstring(kml_content)
    except ET.ParseError as e:
        result["error"] = f"XML parse error: {e}"
        return result
    
    # Handle KML namespace
    ns = {'kml': 'http://www.opengis.net/kml/2.2'}
    
    def find_all(element, tag):
        """Find all elements with or without namespace."""
        found = element.findall(f'.//kml:{tag}', ns)
        if not found:
            found = element.findall(f'.//{tag}')
        return found
    
    def get_text(element, tag):
        """Get text content of child element."""
        el = element.find(f'kml:{tag}', ns)
        if el is None:
            el = element.find(tag)
        return el.text.strip() if el is not None and el.text else ""
    
    result["valid"] = True
    
    # Extract folders
    for folder in find_all(root, 'Folder'):
        name = get_text(folder, 'name')
        result["folders"].append({"name": name, "element": folder})
    
    # Extract placemarks
    for pm in find_all(root, 'Placemark'):
        name = get_text(pm, 'name')
        pm_data = {"name": name, "type": None, "coordinates": None}
        
        # Check for Point
        point = pm.find('.//kml:Point', ns)
        if point is None:
            point = pm.find('.//Point')
        if point is not None:
            pm_data["type"] = "point"
            coords_el = point.find('.//kml:coordinates', ns)
            if coords_el is None:
                coords_el = point.find('.//coordinates')
            if coords_el is not None and coords_el.text:
                coords = parse_kml_coordinates(coords_el.text)
                if coords:
                    pm_data["coordinates"] = coords[0]  # (lon, lat, alt)
        
        # Check for Polygon
        polygon = pm.find('.//kml:Polygon', ns)
        if polygon is None:
            polygon = pm.find('.//Polygon')
        if polygon is not None:
            pm_data["type"] = "polygon"
            coords_el = polygon.find('.//kml:coordinates', ns)
            if coords_el is None:
                coords_el = polygon.find('.//coordinates')
            if coords_el is not None and coords_el.text:
                pm_data["coordinates"] = parse_kml_coordinates(coords_el.text)
                result["polygons"].append({
                    "name": name,
                    "coordinates": pm_data["coordinates"]
                })
        
        # Check for LineString (path)
        linestring = pm.find('.//kml:LineString', ns)
        if linestring is None:
            linestring = pm.find('.//LineString')
        if linestring is not None:
            pm_data["type"] = "path"
            coords_el = linestring.find('.//kml:coordinates', ns)
            if coords_el is None:
                coords_el = linestring.find('.//coordinates')
            if coords_el is not None and coords_el.text:
                pm_data["coordinates"] = parse_kml_coordinates(coords_el.text)
                result["paths"].append({
                    "name": name,
                    "coordinates": pm_data["coordinates"]
                })
        
        result["placemarks"].append(pm_data)
    
    return result


# =============================================================================
# VLM VERIFICATION
# =============================================================================

TRAJECTORY_PROMPT = """You are analyzing a sequence of screenshots from an agent creating a Search and Rescue grid in Google Earth Pro.

The task was to:
1. Navigate to Yosemite Valley (37.7436°N, 119.5919°W)
2. Create a folder named 'SAR_MarcusChen_Search'
3. Create a 2km × 2km polygon boundary
4. Create divider paths to split into 4 quadrants
5. Create sector placemarks and an LKP (Last Known Position) placemark
6. Export the grid as a KML file

Analyze these chronological screenshots and determine:

1. GOOGLE_EARTH_VISIBLE: Is Google Earth Pro interface clearly visible?
2. YOSEMITE_AREA: Does any frame show Yosemite Valley area (valley, cliffs, forest terrain)?
3. FOLDER_CREATION: Any evidence of folder creation (right-click menu, 'Add Folder' dialog)?
4. POLYGON_DRAWING: Any evidence of polygon/boundary drawing (polygon tool active, shape being drawn)?
5. PATH_CREATION: Any evidence of path/line creation?
6. PLACEMARK_CREATION: Any evidence of placemark creation (placemark dialog, pins on map)?
7. SAVE_DIALOG: Any evidence of Save/Export dialog for KML?
8. MEANINGFUL_WORK: Do the frames show actual progression through the task?

Respond in JSON format:
{
    "google_earth_visible": true/false,
    "yosemite_area_shown": true/false,
    "folder_creation_evidence": true/false,
    "polygon_drawing_evidence": true/false,
    "path_creation_evidence": true/false,
    "placemark_creation_evidence": true/false,
    "save_dialog_evidence": true/false,
    "meaningful_work_progression": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you observe across the frames"
}
"""


def verify_via_vlm(traj: Dict[str, Any], query_vlm) -> Dict[str, Any]:
    """Verify task using VLM analysis of trajectory screenshots."""
    if not query_vlm:
        return {"success": False, "score": 0, "error": "VLM not available"}
    
    # Import trajectory utilities
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    except ImportError:
        # Fallback for local testing
        def sample_trajectory_frames(traj, n=5):
            frames = traj.get('frames', [])
            if not frames:
                return []
            step = max(1, len(frames) // n)
            return frames[::step][:n]
        
        def get_final_screenshot(traj):
            frames = traj.get('frames', [])
            return frames[-1] if frames else None
    
    # Sample trajectory frames
    frames = sample_trajectory_frames(traj, n=5)
    final = get_final_screenshot(traj)
    
    if not frames and not final:
        return {"success": False, "score": 0, "error": "No trajectory frames available"}
    
    # Combine frames for analysis
    all_frames = frames if frames else []
    if final and final not in all_frames:
        all_frames.append(final)
    
    if not all_frames:
        return {"success": False, "score": 0, "error": "No frames to analyze"}
    
    try:
        vlm_result = query_vlm(
            prompt=TRAJECTORY_PROMPT,
            images=all_frames
        )
        
        if not vlm_result.get("success"):
            return {"success": False, "score": 0, "error": vlm_result.get("error", "VLM query failed")}
        
        parsed = vlm_result.get("parsed", {})
        
        # Calculate trajectory verification score
        criteria = [
            parsed.get("google_earth_visible", False),
            parsed.get("yosemite_area_shown", False),
            parsed.get("polygon_drawing_evidence", False),
            parsed.get("placemark_creation_evidence", False),
            parsed.get("meaningful_work_progression", False),
        ]
        
        score = sum(20 for c in criteria if c)  # 20 points each, max 100
        
        # Bonus for save dialog evidence
        if parsed.get("save_dialog_evidence", False):
            score = min(100, score + 10)
        
        confidence = parsed.get("confidence", "low")
        if confidence == "high":
            pass
        elif confidence == "medium":
            score = int(score * 0.9)
        else:
            score = int(score * 0.8)
        
        return {
            "success": True,
            "score": score,
            "details": parsed,
            "observations": parsed.get("observations", "")
        }
        
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        return {"success": False, "score": 0, "error": str(e)}


# =============================================================================
# MAIN VERIFICATION FUNCTION
# =============================================================================

def verify_sar_grid_creation(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify SAR Grid Creation task completion.
    
    Uses multi-signal verification:
    - Programmatic: KML file parsing and validation
    - VLM: Trajectory analysis for workflow verification
    
    Returns dict with 'passed', 'score', and 'feedback'.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ copy_from_env function not available"
        }
    
    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/Documents/SAR_MarcusChen_Grid.kml')
    
    feedback_parts = []
    score = 0
    details = {}
    
    # ================================================================
    # STEP 1: Copy and parse result JSON from container
    # ================================================================
    result_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", result_temp.name)
        with open(result_temp.name, 'r') as f:
            export_result = json.load(f)
        details["export_result"] = export_result
    except Exception as e:
        logger.error(f"Failed to read task result: {e}")
        export_result = {}
    finally:
        if os.path.exists(result_temp.name):
            os.unlink(result_temp.name)
    
    # ================================================================
    # CRITERION 1: KML file exists (10 points)
    # ================================================================
    output_exists = export_result.get("output_exists", False)
    
    if output_exists:
        score += 10
        feedback_parts.append("✅ KML file exists")
    else:
        feedback_parts.append("❌ KML file NOT found")
        # Without the file, we can still check VLM for partial credit
        vlm_result = verify_via_vlm(traj, query_vlm)
        if vlm_result.get("success"):
            vlm_score = vlm_result.get("score", 0) // 5  # Scale down
            score += vlm_score
            feedback_parts.append(f"📷 Trajectory shows some work (+{vlm_score})")
        
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: File created during task - anti-gaming (10 points)
    # ================================================================
    file_created_during_task = export_result.get("file_created_during_task", False)
    
    if file_created_during_task:
        score += 10
        feedback_parts.append("✅ File created during task")
    else:
        feedback_parts.append("⚠️ File may pre-exist (timestamp check failed)")
    
    details["file_created_during_task"] = file_created_during_task
    
    # ================================================================
    # STEP 2: Copy and parse KML file
    # ================================================================
    kml_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
    kml_parsed = None
    try:
        copy_from_env(expected_output_path, kml_temp.name)
        with open(kml_temp.name, 'r', encoding='utf-8', errors='ignore') as f:
            kml_content = f.read()
        kml_parsed = parse_kml_file(kml_content)
        details["kml_parsed"] = {
            "valid": kml_parsed.get("valid"),
            "folder_count": len(kml_parsed.get("folders", [])),
            "placemark_count": len(kml_parsed.get("placemarks", [])),
            "polygon_count": len(kml_parsed.get("polygons", [])),
            "path_count": len(kml_parsed.get("paths", []))
        }
    except Exception as e:
        logger.error(f"Failed to parse KML file: {e}")
        feedback_parts.append(f"⚠️ KML parse error: {e}")
        kml_parsed = {"valid": False, "error": str(e)}
    finally:
        if os.path.exists(kml_temp.name):
            os.unlink(kml_temp.name)
    
    if not kml_parsed or not kml_parsed.get("valid"):
        feedback_parts.append("❌ KML file is invalid")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 3: Folder structure with correct name (10 points)
    # ================================================================
    folders = kml_parsed.get("folders", [])
    sar_folder_found = any("SAR_MarcusChen" in f.get("name", "") for f in folders)
    
    if sar_folder_found:
        score += 10
        feedback_parts.append("✅ SAR folder found")
    elif folders:
        score += 5
        feedback_parts.append("⚠️ Folder exists but wrong name")
    else:
        feedback_parts.append("❌ No folder structure")
    
    details["sar_folder_found"] = sar_folder_found
    
    # ================================================================
    # CRITERION 4: Search boundary polygon exists (15 points)
    # ================================================================
    polygons = kml_parsed.get("polygons", [])
    boundary_polygon = None
    
    for poly in polygons:
        name = poly.get("name", "")
        if "Search_Boundary" in name or "Boundary" in name.lower():
            boundary_polygon = poly
            break
    
    if not boundary_polygon and polygons:
        # Take first polygon as boundary
        boundary_polygon = polygons[0]
    
    if boundary_polygon:
        score += 15
        feedback_parts.append("✅ Boundary polygon found")
        details["boundary_polygon"] = boundary_polygon.get("name", "unnamed")
    else:
        feedback_parts.append("❌ No boundary polygon")
    
    # ================================================================
    # CRITERION 5: Boundary size approximately 4 km² (10 points)
    # ================================================================
    boundary_area = 0
    if boundary_polygon and boundary_polygon.get("coordinates"):
        boundary_area = calculate_polygon_area_km2(boundary_polygon["coordinates"])
        details["boundary_area_km2"] = round(boundary_area, 2)
        
        if EXPECTED_AREA_MIN_KM2 <= boundary_area <= EXPECTED_AREA_MAX_KM2:
            score += 10
            feedback_parts.append(f"✅ Boundary area ~{boundary_area:.1f} km²")
        elif 2.0 <= boundary_area <= 6.0:
            score += 5
            feedback_parts.append(f"⚠️ Boundary area {boundary_area:.1f} km² (expected ~4 km²)")
        else:
            feedback_parts.append(f"❌ Boundary area {boundary_area:.1f} km² (expected ~4 km²)")
    
    # ================================================================
    # CRITERION 6: Divider paths exist (10 points)
    # ================================================================
    paths = kml_parsed.get("paths", [])
    divider_paths = [p for p in paths if "Divider" in p.get("name", "")]
    
    if len(divider_paths) >= 2:
        score += 10
        feedback_parts.append(f"✅ Divider paths found ({len(divider_paths)})")
    elif len(divider_paths) == 1:
        score += 5
        feedback_parts.append("⚠️ Only 1 divider path found")
    elif paths:
        score += 3
        feedback_parts.append(f"⚠️ Paths exist but no 'Divider' names ({len(paths)} paths)")
    else:
        feedback_parts.append("❌ No divider paths")
    
    details["divider_paths_found"] = len(divider_paths)
    
    # ================================================================
    # CRITERION 7: Sector placemarks exist (15 points)
    # ================================================================
    placemarks = kml_parsed.get("placemarks", [])
    sector_placemarks = [p for p in placemarks if "Sector_" in p.get("name", "")]
    
    expected_sectors = 4
    found_sectors = len(sector_placemarks)
    
    if found_sectors >= 4:
        score += 15
        feedback_parts.append("✅ All 4 sector placemarks found")
    elif found_sectors >= 2:
        score += int(15 * found_sectors / 4)
        feedback_parts.append(f"⚠️ {found_sectors}/4 sector placemarks found")
    elif found_sectors >= 1:
        score += 4
        feedback_parts.append(f"⚠️ Only {found_sectors} sector placemark found")
    else:
        # Check for any point placemarks as partial credit
        point_placemarks = [p for p in placemarks if p.get("type") == "point"]
        if len(point_placemarks) >= 4:
            score += 8
            feedback_parts.append(f"⚠️ {len(point_placemarks)} placemarks but no 'Sector_' names")
        else:
            feedback_parts.append("❌ No sector placemarks")
    
    details["sector_placemarks_found"] = found_sectors
    
    # ================================================================
    # CRITERION 8: LKP placemark exists (10 points)
    # ================================================================
    lkp_placemarks = [p for p in placemarks if "LKP" in p.get("name", "")]
    
    if lkp_placemarks:
        score += 10
        feedback_parts.append("✅ LKP placemark found")
        details["lkp_placemark_found"] = True
    else:
        feedback_parts.append("❌ No LKP placemark")
        details["lkp_placemark_found"] = False
    
    # ================================================================
    # CRITERION 9: LKP coordinates near target (10 points) - OPTIONAL BONUS
    # ================================================================
    if lkp_placemarks and lkp_placemarks[0].get("coordinates"):
        lkp_coords = lkp_placemarks[0]["coordinates"]
        if isinstance(lkp_coords, tuple) and len(lkp_coords) >= 2:
            lon, lat = lkp_coords[0], lkp_coords[1]
            distance = haversine_distance(TARGET_LAT, TARGET_LON, lat, lon)
            details["lkp_distance_km"] = round(distance, 2)
            
            if distance <= COORDINATE_TOLERANCE_KM:
                score += 10
                feedback_parts.append(f"✅ LKP within {distance:.2f} km of target")
            elif distance <= COORDINATE_TOLERANCE_KM * 3:
                score += 5
                feedback_parts.append(f"⚠️ LKP {distance:.1f} km from target")
            else:
                feedback_parts.append(f"❌ LKP {distance:.1f} km from target (too far)")
    
    # ================================================================
    # VLM TRAJECTORY VERIFICATION (bonus/confirmation)
    # ================================================================
    vlm_result = verify_via_vlm(traj, query_vlm)
    if vlm_result.get("success"):
        vlm_score = vlm_result.get("score", 0)
        details["vlm_verification"] = vlm_result
        
        if vlm_score >= 60:
            feedback_parts.append(f"📷 Trajectory confirms workflow (VLM: {vlm_score}%)")
        elif vlm_score >= 30:
            feedback_parts.append(f"📷 Partial workflow evidence (VLM: {vlm_score}%)")
        else:
            feedback_parts.append(f"📷 Limited workflow evidence (VLM: {vlm_score}%)")
    else:
        details["vlm_verification"] = {"error": vlm_result.get("error", "unavailable")}
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    # Key criteria: file must be created during task AND have minimum content
    key_criteria_met = (
        file_created_during_task and
        output_exists and
        (boundary_polygon is not None or len(placemarks) >= 3)
    )
    
    passed = score >= 70 and key_criteria_met
    
    # Cap score at 100
    score = min(100, score)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }