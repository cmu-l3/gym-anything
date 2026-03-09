#!/usr/bin/env python3
"""
Verifier for supply_route_network task.

Task: Create a multi-segment logistics route network in Google Earth Pro
with styled paths and export as KML.

Verification Strategy (Multi-Signal):
1. KML file exists at expected path (10 pts)
2. File was created during task - anti-gaming (10 pts)
3. KML contains properly named folder (10 pts)
4. KML contains 3 paths with LineString geometry (15 pts each = 45 pts)
5. Paths have correct names (10 pts)
6. Red color styling detected (10 pts)
7. Blue color styling detected (5 pts)
8. Coordinates in Chicago area (10 pts) - VLM verification for trajectory

Pass threshold: 65 points minimum, with at least 2 paths created
"""

import json
import tempfile
import os
import logging
import re
from xml.etree import ElementTree as ET
from typing import Dict, Any, List, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Chicago metropolitan area bounds for coordinate validation
CHICAGO_BOUNDS = {
    "lat_min": 41.0,
    "lat_max": 42.5,
    "lon_min": -88.5,
    "lon_max": -87.0
}


def parse_kml_coordinates(coord_string: str) -> List[Tuple[float, float]]:
    """Parse KML coordinate string into list of (lat, lon) tuples."""
    coords = []
    if not coord_string:
        return coords
    
    for point in coord_string.strip().split():
        parts = point.split(',')
        if len(parts) >= 2:
            try:
                lon = float(parts[0])
                lat = float(parts[1])
                coords.append((lat, lon))
            except ValueError:
                continue
    return coords


def is_in_chicago_area(lat: float, lon: float) -> bool:
    """Check if coordinates are within Chicago metropolitan area."""
    return (CHICAGO_BOUNDS["lat_min"] <= lat <= CHICAGO_BOUNDS["lat_max"] and
            CHICAGO_BOUNDS["lon_min"] <= lon <= CHICAGO_BOUNDS["lon_max"])


def extract_color_from_kml(kml_content: str) -> Dict[str, bool]:
    """Extract color information from KML content."""
    result = {"has_red": False, "has_blue": False}
    
    # KML colors are in aabbggrr format (alpha, blue, green, red)
    # Red = ff0000ff (or variations with high red, low blue/green)
    # Blue = ffff0000 (or variations with high blue, low red/green)
    
    content_lower = kml_content.lower()
    
    # Look for color elements
    color_matches = re.findall(r'<color>([a-f0-9]{8})</color>', content_lower)
    
    for color in color_matches:
        if len(color) == 8:
            # Parse aabbggrr format
            alpha = color[0:2]
            blue = color[2:4]
            green = color[4:6]
            red = color[6:8]
            
            # Check for red (high red value, low blue/green)
            try:
                red_val = int(red, 16)
                blue_val = int(blue, 16)
                green_val = int(green, 16)
                
                if red_val > 200 and blue_val < 100 and green_val < 100:
                    result["has_red"] = True
                if blue_val > 200 and red_val < 100 and green_val < 100:
                    result["has_blue"] = True
            except ValueError:
                continue
    
    return result


def analyze_kml_structure(kml_content: str) -> Dict[str, Any]:
    """Analyze KML file structure for paths, folders, and styling."""
    analysis = {
        "valid_xml": False,
        "has_folder": False,
        "folder_name": "",
        "placemarks": [],
        "linestring_count": 0,
        "paths_in_chicago": 0,
        "color_info": {"has_red": False, "has_blue": False}
    }
    
    try:
        # Try parsing with namespace
        root = ET.fromstring(kml_content)
        analysis["valid_xml"] = True
    except ET.ParseError as e:
        logger.warning(f"KML parse error: {e}")
        return analysis
    
    # Handle KML namespace
    ns = {'kml': 'http://www.opengis.net/kml/2.2'}
    
    def find_elements(parent, tag):
        """Find elements with or without namespace."""
        elements = parent.findall(f'.//{{{ns["kml"]}}}{tag}')
        if not elements:
            elements = parent.findall(f'.//{tag}')
        return elements
    
    def get_element_text(parent, tag):
        """Get text from element with or without namespace."""
        elem = parent.find(f'{{{ns["kml"]}}}{tag}')
        if elem is None:
            elem = parent.find(tag)
        return elem.text if elem is not None and elem.text else ""
    
    # Find folders
    folders = find_elements(root, 'Folder')
    for folder in folders:
        name = get_element_text(folder, 'name')
        if name:
            analysis["has_folder"] = True
            analysis["folder_name"] = name
            break
    
    # Find placemarks with LineString (paths)
    placemarks = find_elements(root, 'Placemark')
    for pm in placemarks:
        pm_info = {
            "name": get_element_text(pm, 'name'),
            "has_linestring": False,
            "coordinates": [],
            "in_chicago": False
        }
        
        # Check for LineString
        linestrings = find_elements(pm, 'LineString')
        if linestrings:
            pm_info["has_linestring"] = True
            analysis["linestring_count"] += 1
            
            # Get coordinates
            for ls in linestrings:
                coord_elem = ls.find(f'{{{ns["kml"]}}}coordinates')
                if coord_elem is None:
                    coord_elem = ls.find('coordinates')
                
                if coord_elem is not None and coord_elem.text:
                    coords = parse_kml_coordinates(coord_elem.text)
                    pm_info["coordinates"] = coords
                    
                    # Check if in Chicago area
                    if coords:
                        start = coords[0]
                        end = coords[-1] if len(coords) > 1 else coords[0]
                        if is_in_chicago_area(start[0], start[1]) or is_in_chicago_area(end[0], end[1]):
                            pm_info["in_chicago"] = True
                            analysis["paths_in_chicago"] += 1
        
        if pm_info["has_linestring"]:
            analysis["placemarks"].append(pm_info)
    
    # Extract color info
    analysis["color_info"] = extract_color_from_kml(kml_content)
    
    return analysis


def verify_via_vlm(traj: Dict[str, Any], env_info: Dict[str, Any]) -> Dict[str, Any]:
    """Use VLM to verify trajectory shows path creation workflow."""
    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        return {"success": False, "error": "VLM not available"}
    
    # Get trajectory frames
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        
        if final:
            frames = frames + [final]
        
        if not frames:
            return {"success": False, "error": "No trajectory frames available"}
    except ImportError:
        # Fallback if gym_anything.vlm not available
        frames = traj.get('frames', [])
        if not frames:
            return {"success": False, "error": "No frames in trajectory"}
        # Sample frames
        if len(frames) > 6:
            indices = [0, len(frames)//4, len(frames)//2, 3*len(frames)//4, -1]
            frames = [frames[i] for i in indices if i < len(frames)]
    
    prompt = """You are analyzing screenshots from an agent creating logistics routes in Google Earth Pro.

The task was to create 3 path segments representing a supply chain network in Chicago:
- Two red paths (primary routes)
- One blue path (secondary route)
- All organized in a folder named "Chicago Distribution Network"

Analyze these trajectory screenshots and determine:

1. GOOGLE_EARTH_VISIBLE: Is Google Earth Pro visible in the screenshots?
2. CHICAGO_AREA_SHOWN: Does the map show the Chicago metropolitan area?
3. PATH_CREATION_VISIBLE: Can you see evidence of path/line creation (drawing lines, path dialog, etc.)?
4. MULTIPLE_PATHS_VISIBLE: Are multiple path lines visible on the map?
5. COLOR_STYLING_VISIBLE: Can you see colored lines (red or blue paths)?
6. PLACES_PANEL_VISIBLE: Is the Places/My Places panel visible showing folder structure?
7. KML_EXPORT_VISIBLE: Is there any evidence of saving/exporting (Save Place As dialog, etc.)?

Respond in JSON format:
{
    "google_earth_visible": true/false,
    "chicago_area_shown": true/false,
    "path_creation_visible": true/false,
    "multiple_paths_visible": true/false,
    "color_styling_visible": true/false,
    "places_panel_visible": true/false,
    "kml_export_visible": true/false,
    "workflow_progression": "description of what you observe across the frames",
    "confidence": "low"/"medium"/"high"
}
"""
    
    try:
        result = query_vlm(prompt=prompt, images=frames)
        if result.get("success"):
            return {"success": True, "parsed": result.get("parsed", {})}
        return {"success": False, "error": result.get("error", "VLM query failed")}
    except Exception as e:
        return {"success": False, "error": str(e)}


def verify_supply_route_network(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify supply route network task completion.
    
    Multi-signal verification:
    1. Programmatic: KML file structure analysis
    2. Anti-gaming: File timestamp verification
    3. VLM: Trajectory verification for workflow
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/Documents/chicago_distribution_network.kml')
    
    feedback_parts = []
    score = 0
    max_score = 100
    details = {}
    
    # ================================================================
    # STEP 1: Copy result JSON from container
    # ================================================================
    result_data = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
        details["result_data"] = result_data
    except Exception as e:
        logger.warning(f"Could not read result JSON: {e}")
        feedback_parts.append(f"Could not read task results: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # CRITERION 1: KML file exists (10 points)
    # ================================================================
    output_exists = result_data.get('output_exists', False)
    
    if output_exists:
        score += 10
        feedback_parts.append("✅ KML file exists (10 pts)")
    else:
        feedback_parts.append("❌ KML file NOT found at expected path")
        # Try to continue with any KML file that might exist
        if result_data.get('new_kml_files_created', 0) > 0:
            feedback_parts.append("⚠️ Other KML files were created but not at expected location")
    
    # ================================================================
    # CRITERION 2: File created during task - anti-gaming (10 points)
    # ================================================================
    file_created_during_task = result_data.get('file_created_during_task', False)
    
    if file_created_during_task:
        score += 10
        feedback_parts.append("✅ File created during task (10 pts)")
    elif output_exists:
        feedback_parts.append("⚠️ File exists but may not have been created during task")
        score += 3  # Partial credit
    else:
        feedback_parts.append("❌ No file created during task")
    
    # ================================================================
    # STEP 2: Copy and analyze KML file
    # ================================================================
    kml_content = ""
    kml_analysis = {}
    
    if output_exists:
        temp_kml = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
        try:
            # Try the expected path first
            copy_from_env(expected_output_path, temp_kml.name)
            with open(temp_kml.name, 'r', encoding='utf-8', errors='ignore') as f:
                kml_content = f.read()
        except Exception as e:
            logger.warning(f"Could not read KML from expected path: {e}")
            # Try the tmp copy
            try:
                copy_from_env("/tmp/task_output.kml", temp_kml.name)
                with open(temp_kml.name, 'r', encoding='utf-8', errors='ignore') as f:
                    kml_content = f.read()
            except Exception as e2:
                logger.warning(f"Could not read KML from tmp: {e2}")
        finally:
            if os.path.exists(temp_kml.name):
                os.unlink(temp_kml.name)
    
    if kml_content:
        kml_analysis = analyze_kml_structure(kml_content)
        details["kml_analysis"] = kml_analysis
        
        # ================================================================
        # CRITERION 3: Folder structure (10 points)
        # ================================================================
        if kml_analysis.get("has_folder", False):
            folder_name = kml_analysis.get("folder_name", "").lower()
            if "chicago" in folder_name and "distribution" in folder_name:
                score += 10
                feedback_parts.append("✅ Folder 'Chicago Distribution Network' found (10 pts)")
            elif folder_name:
                score += 5
                feedback_parts.append(f"⚠️ Folder found but name differs: '{kml_analysis.get('folder_name')}' (5 pts)")
            else:
                score += 3
                feedback_parts.append("⚠️ Folder structure present but no name (3 pts)")
        else:
            feedback_parts.append("❌ No folder structure in KML")
        
        # ================================================================
        # CRITERION 4: Paths with LineString geometry (15 pts each, 45 total)
        # ================================================================
        linestring_count = kml_analysis.get("linestring_count", 0)
        placemarks = kml_analysis.get("placemarks", [])
        
        if linestring_count >= 1:
            score += 15
            feedback_parts.append("✅ Path 1 with LineString found (15 pts)")
        if linestring_count >= 2:
            score += 15
            feedback_parts.append("✅ Path 2 with LineString found (15 pts)")
        if linestring_count >= 3:
            score += 15
            feedback_parts.append("✅ Path 3 with LineString found (15 pts)")
        
        if linestring_count < 3:
            feedback_parts.append(f"⚠️ Only {linestring_count}/3 paths found")
        
        # ================================================================
        # CRITERION 5: Path names (10 points)
        # ================================================================
        correct_names = 0
        expected_keywords = [
            ["primary", "hub", "regional"],
            ["primary", "regional", "south"],
            ["secondary", "east"]
        ]
        
        for pm in placemarks:
            pm_name = pm.get("name", "").lower()
            for keywords in expected_keywords:
                if any(kw in pm_name for kw in keywords):
                    correct_names += 1
                    break
        
        if correct_names >= 2:
            score += 10
            feedback_parts.append(f"✅ Path names correct ({correct_names}/3) (10 pts)")
        elif correct_names >= 1:
            score += 5
            feedback_parts.append(f"⚠️ Some path names correct ({correct_names}/3) (5 pts)")
        else:
            feedback_parts.append("❌ Path names do not match expected pattern")
        
        # ================================================================
        # CRITERION 6: Red color styling (10 points)
        # ================================================================
        color_info = kml_analysis.get("color_info", {})
        if color_info.get("has_red", False):
            score += 10
            feedback_parts.append("✅ Red colored paths found (10 pts)")
        else:
            # Check the basic analysis from export script
            if result_data.get("kml_analysis", {}).get("has_red_style", False):
                score += 10
                feedback_parts.append("✅ Red styling detected (10 pts)")
            else:
                feedback_parts.append("⚠️ Red path styling not detected")
        
        # ================================================================
        # CRITERION 7: Blue color styling (5 points)
        # ================================================================
        if color_info.get("has_blue", False):
            score += 5
            feedback_parts.append("✅ Blue colored path found (5 pts)")
        else:
            if result_data.get("kml_analysis", {}).get("has_blue_style", False):
                score += 5
                feedback_parts.append("✅ Blue styling detected (5 pts)")
            else:
                feedback_parts.append("⚠️ Blue path styling not detected")
        
        # ================================================================
        # CRITERION 8: Coordinates in Chicago area (implicit in good paths)
        # ================================================================
        paths_in_chicago = kml_analysis.get("paths_in_chicago", 0)
        if paths_in_chicago >= 2:
            feedback_parts.append(f"✅ {paths_in_chicago} paths have Chicago-area coordinates")
        elif paths_in_chicago >= 1:
            feedback_parts.append(f"⚠️ Only {paths_in_chicago} path(s) in Chicago area")
    
    else:
        feedback_parts.append("❌ Could not analyze KML content")
    
    # ================================================================
    # VLM TRAJECTORY VERIFICATION (bonus validation)
    # ================================================================
    vlm_result = verify_via_vlm(traj, env_info)
    details["vlm_result"] = vlm_result
    
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        vlm_criteria_met = sum([
            parsed.get("google_earth_visible", False),
            parsed.get("path_creation_visible", False),
            parsed.get("multiple_paths_visible", False),
        ])
        
        if vlm_criteria_met >= 2:
            feedback_parts.append(f"✅ VLM confirms workflow progression ({vlm_criteria_met}/3 criteria)")
        elif vlm_criteria_met >= 1:
            feedback_parts.append(f"⚠️ VLM partially confirms workflow ({vlm_criteria_met}/3 criteria)")
        
        if parsed.get("workflow_progression"):
            details["vlm_observations"] = parsed.get("workflow_progression")
    else:
        feedback_parts.append(f"⚠️ VLM verification unavailable: {vlm_result.get('error', 'unknown')}")
    
    # ================================================================
    # Check Google Earth was running
    # ================================================================
    if result_data.get("google_earth_running", False):
        feedback_parts.append("✅ Google Earth was running")
    else:
        feedback_parts.append("⚠️ Google Earth may not have been running")
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    linestring_count = kml_analysis.get("linestring_count", 0) if kml_analysis else 0
    
    # Key criteria: at least 2 paths created AND file exists
    key_criteria_met = linestring_count >= 2 and output_exists
    
    # Pass threshold: 65 points with key criteria
    passed = score >= 65 and key_criteria_met
    
    # Cap score at max
    score = min(score, max_score)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }