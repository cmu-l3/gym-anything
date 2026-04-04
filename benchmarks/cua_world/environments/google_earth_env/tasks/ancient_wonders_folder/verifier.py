#!/usr/bin/env python3
"""
Verifier for ancient_wonders_folder task.

VERIFICATION STRATEGY:
1. KML File Analysis (Primary) - Parse myplaces.kml to verify folder and placemarks
2. Timestamp Anti-Gaming - Verify file was modified during task
3. VLM Trajectory Verification - Verify agent workflow through trajectory frames
4. Coordinate Verification - Check placemarks are at correct locations

SCORING (100 points total):
- Folder created: 15 points
- Pyramid placemark exists at location: 15 points
- Pyramid correctly named: 5 points
- Lighthouse placemark exists at location: 15 points
- Lighthouse correctly named: 5 points
- Temple placemark exists at location: 15 points
- Temple correctly named: 5 points
- All placemarks in folder: 15 points
- File modified during task: 10 points

Pass threshold: 70 points with folder created and at least 2 placemarks
"""

import json
import tempfile
import os
import math
import re
import logging
import xml.etree.ElementTree as ET
from typing import Dict, Any, List, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ================================================================
# CONFIGURATION
# ================================================================

TARGETS = {
    "pyramid": {
        "lat": 29.9792,
        "lon": 31.1342,
        "keywords": ["pyramid", "giza", "great pyramid"],
        "name": "Great Pyramid of Giza"
    },
    "lighthouse": {
        "lat": 31.2139,
        "lon": 29.8853,
        "keywords": ["lighthouse", "alexandria", "pharos"],
        "name": "Lighthouse of Alexandria"
    },
    "temple": {
        "lat": 37.9497,
        "lon": 27.3639,
        "keywords": ["temple", "artemis", "ephesus"],
        "name": "Temple of Artemis"
    }
}

TOLERANCE_KM = 2.0
FOLDER_KEYWORDS = ["ancient", "wonders"]


# ================================================================
# UTILITY FUNCTIONS
# ================================================================

def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate distance between two points in kilometers."""
    R = 6371  # Earth's radius in km
    lat1, lon1, lat2, lon2 = map(math.radians, [lat1, lon1, lat2, lon2])
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    a = math.sin(dlat/2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon/2)**2
    c = 2 * math.asin(math.sqrt(a))
    return R * c


def parse_kml_content(kml_content: str) -> Tuple[Optional[ET.Element], List[ET.Element], Dict]:
    """Parse KML content and extract folder/placemark structure."""
    try:
        root = ET.fromstring(kml_content)
        
        # Handle KML namespace
        ns = {'kml': 'http://www.opengis.net/kml/2.2'}
        
        # Try with namespace first, then without
        folders = root.findall('.//{http://www.opengis.net/kml/2.2}Folder')
        if not folders:
            folders = root.findall('.//Folder')
        
        return root, folders, ns
    except ET.ParseError as e:
        logger.error(f"XML Parse error: {e}")
        return None, [], {}
    except Exception as e:
        logger.error(f"Error parsing KML: {e}")
        return None, [], {}


def find_folder_by_keywords(folders: List[ET.Element], keywords: List[str]) -> Optional[ET.Element]:
    """Find a folder with name containing any of the keywords."""
    ns = {'kml': 'http://www.opengis.net/kml/2.2'}
    
    for folder in folders:
        # Try with namespace
        name_elem = folder.find('{http://www.opengis.net/kml/2.2}name')
        if name_elem is None:
            name_elem = folder.find('name')
        
        if name_elem is not None and name_elem.text:
            name_lower = name_elem.text.lower()
            if all(kw.lower() in name_lower for kw in keywords):
                return folder
    return None


def extract_placemarks(element: ET.Element) -> List[Dict]:
    """Extract all placemarks from an element (folder or document)."""
    placemarks = []
    ns = {'kml': 'http://www.opengis.net/kml/2.2'}
    
    # Find placemarks with and without namespace
    pm_elems = element.findall('.//{http://www.opengis.net/kml/2.2}Placemark')
    if not pm_elems:
        pm_elems = element.findall('.//Placemark')
    
    for pm in pm_elems:
        # Get name
        name_elem = pm.find('{http://www.opengis.net/kml/2.2}name')
        if name_elem is None:
            name_elem = pm.find('name')
        name = name_elem.text if name_elem is not None and name_elem.text else ""
        
        # Get coordinates
        coord_elem = pm.find('.//{http://www.opengis.net/kml/2.2}coordinates')
        if coord_elem is None:
            coord_elem = pm.find('.//coordinates')
        
        coords = None
        if coord_elem is not None and coord_elem.text:
            # KML coordinates are lon,lat,alt
            parts = coord_elem.text.strip().split(',')
            if len(parts) >= 2:
                try:
                    lon = float(parts[0].strip())
                    lat = float(parts[1].strip())
                    coords = (lat, lon)
                except ValueError:
                    pass
        
        placemarks.append({"name": name, "coords": coords, "element": pm})
    
    return placemarks


def check_placemark_match(placemark: Dict, target: Dict) -> Tuple[bool, bool, float]:
    """Check if a placemark matches a target location.
    Returns: (name_match, coord_match, distance_km)
    """
    name_match = False
    coord_match = False
    distance = float('inf')
    
    # Check name
    if placemark["name"]:
        name_lower = placemark["name"].lower()
        name_match = any(kw.lower() in name_lower for kw in target["keywords"])
    
    # Check coordinates
    if placemark["coords"]:
        lat, lon = placemark["coords"]
        distance = haversine_distance(lat, lon, target["lat"], target["lon"])
        coord_match = distance <= TOLERANCE_KM
    
    return name_match, coord_match, distance


# ================================================================
# VLM VERIFICATION
# ================================================================

TRAJECTORY_PROMPT = """You are analyzing a sequence of screenshots from an agent creating placemarks in Google Earth Pro.

The task was to:
1. Create a folder called "Ancient Wonders" in My Places
2. Add 3 placemarks for ancient wonders (Pyramid of Giza, Lighthouse of Alexandria, Temple of Artemis)

Look at these trajectory screenshots (from earliest to latest) and determine:

1. GOOGLE_EARTH_USED: Is this Google Earth Pro (satellite imagery interface)?
2. FOLDER_CREATED: Did the agent create or open a folder (look for folder dialogs, My Places panel)?
3. NAVIGATION_OCCURRED: Did the agent navigate to different locations (view changes significantly)?
4. PLACEMARKS_CREATED: Are there placemark dialogs or placemark icons visible?
5. MULTIPLE_LOCATIONS: Did the agent visit at least 2-3 distinct geographic areas?
6. WORKFLOW_PROGRESSION: Do the frames show meaningful progression through the task?

Look for evidence of:
- Add Folder dialog
- My Places panel with folders
- Navigation to Egypt (Pyramids, Alexandria) and Turkey
- Add Placemark dialogs
- Yellow pushpin icons

Respond in JSON format:
{
    "google_earth_used": true/false,
    "folder_created": true/false,
    "navigation_occurred": true/false,
    "placemarks_created": true/false,
    "multiple_locations": true/false,
    "workflow_progression": true/false,
    "locations_observed": ["list any recognizable locations"],
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see across frames"
}
"""


def verify_via_vlm(traj: Dict[str, Any], query_vlm) -> Dict[str, Any]:
    """Verify task completion using trajectory frames."""
    if not query_vlm:
        return {"success": False, "error": "VLM not available"}
    
    # Get trajectory frames - sample across the episode
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        
        if final and final not in frames:
            frames.append(final)
        
        if not frames:
            return {"success": False, "error": "No trajectory frames available"}
        
        logger.info(f"Using {len(frames)} trajectory frames for VLM verification")
        
    except ImportError:
        # Fallback: try to get frames from traj directly
        frames = traj.get("frames", [])
        if not frames:
            return {"success": False, "error": "Cannot access trajectory frames"}
        # Sample 5 frames evenly
        if len(frames) > 5:
            indices = [int(i * (len(frames) - 1) / 4) for i in range(5)]
            frames = [frames[i] for i in indices]
    
    try:
        result = query_vlm(prompt=TRAJECTORY_PROMPT, images=frames)
        
        if not result.get("success"):
            return {"success": False, "error": result.get("error", "VLM query failed")}
        
        parsed = result.get("parsed", {})
        return {"success": True, "parsed": parsed}
        
    except Exception as e:
        logger.error(f"VLM verification error: {e}")
        return {"success": False, "error": str(e)}


# ================================================================
# MAIN VERIFICATION FUNCTION
# ================================================================

def verify_ancient_wonders_folder(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that Ancient Wonders folder was created with correct placemarks.
    
    Uses multiple independent signals:
    1. KML file parsing for folder and placemarks
    2. Coordinate verification
    3. Timestamp anti-gaming checks
    4. VLM trajectory verification
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    feedback_parts = []
    details = {}
    score = 0
    
    # ================================================================
    # STEP 1: Get task result JSON from container
    # ================================================================
    result_data = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
        details["result_data"] = result_data
    except Exception as e:
        logger.warning(f"Could not read task result: {e}")
        details["result_error"] = str(e)
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # STEP 2: Check anti-gaming timestamp
    # ================================================================
    file_modified = result_data.get("file_modified", False)
    initial_mtime = result_data.get("initial_mtime", 0)
    current_mtime = result_data.get("myplaces_mtime", 0)
    
    if file_modified or (current_mtime > initial_mtime):
        score += 10
        feedback_parts.append("[+10] myplaces.kml was modified during task")
        details["file_modified"] = True
    else:
        feedback_parts.append("[+0] myplaces.kml was NOT modified (possible gaming)")
        details["file_modified"] = False
    
    # ================================================================
    # STEP 3: Get and parse myplaces.kml from container
    # ================================================================
    kml_content = None
    temp_kml = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
    try:
        copy_from_env("/tmp/myplaces_final.kml", temp_kml.name)
        with open(temp_kml.name, 'r', encoding='utf-8', errors='ignore') as f:
            kml_content = f.read()
        details["kml_size"] = len(kml_content)
    except Exception as e:
        logger.warning(f"Could not read KML file: {e}")
        # Try alternate path
        try:
            copy_from_env("/home/ga/.googleearth/myplaces.kml", temp_kml.name)
            with open(temp_kml.name, 'r', encoding='utf-8', errors='ignore') as f:
                kml_content = f.read()
            details["kml_size"] = len(kml_content)
        except Exception as e2:
            logger.error(f"Could not read KML from alternate path: {e2}")
            details["kml_error"] = str(e2)
    finally:
        if os.path.exists(temp_kml.name):
            os.unlink(temp_kml.name)
    
    if not kml_content:
        feedback_parts.append("[ERROR] Could not read myplaces.kml")
        # Continue with VLM verification only
    else:
        # Parse KML
        root, folders, ns = parse_kml_content(kml_content)
        
        if root is None:
            feedback_parts.append("[ERROR] Failed to parse KML file")
        else:
            details["total_folders"] = len(folders)
            
            # ================================================================
            # STEP 4: Find Ancient Wonders folder
            # ================================================================
            aw_folder = find_folder_by_keywords(folders, FOLDER_KEYWORDS)
            
            if aw_folder is not None:
                score += 15
                feedback_parts.append("[+15] Found 'Ancient Wonders' folder")
                details["folder_found"] = True
                
                # Get folder name
                name_elem = aw_folder.find('{http://www.opengis.net/kml/2.2}name')
                if name_elem is None:
                    name_elem = aw_folder.find('name')
                folder_name = name_elem.text if name_elem is not None else "unknown"
                details["folder_name"] = folder_name
                
                # ================================================================
                # STEP 5: Extract and verify placemarks from folder
                # ================================================================
                placemarks = extract_placemarks(aw_folder)
                details["placemarks_in_folder"] = len(placemarks)
                feedback_parts.append(f"Found {len(placemarks)} placemarks in folder")
                
                # Track which targets were matched
                matched_targets = {}
                for key in TARGETS:
                    matched_targets[key] = {
                        "exists": False,
                        "named": False,
                        "distance_km": float('inf'),
                        "placemark_name": ""
                    }
                
                # Check each placemark against targets
                for pm in placemarks:
                    for target_key, target in TARGETS.items():
                        if matched_targets[target_key]["exists"]:
                            continue  # Already matched this target
                        
                        name_match, coord_match, distance = check_placemark_match(pm, target)
                        
                        if coord_match:
                            matched_targets[target_key]["exists"] = True
                            matched_targets[target_key]["distance_km"] = distance
                            matched_targets[target_key]["placemark_name"] = pm["name"]
                            if name_match:
                                matched_targets[target_key]["named"] = True
                
                details["matched_targets"] = matched_targets
                
                # ================================================================
                # STEP 6: Score individual placemarks
                # ================================================================
                placemarks_found = 0
                
                for target_key, result in matched_targets.items():
                    target_display = TARGETS[target_key]["name"]
                    
                    if result["exists"]:
                        placemarks_found += 1
                        score += 15
                        feedback_parts.append(
                            f"[+15] {target_display} placemark at correct location "
                            f"({result['distance_km']:.1f}km away)"
                        )
                        
                        if result["named"]:
                            score += 5
                            feedback_parts.append(f"[+5] {target_display} correctly named: '{result['placemark_name']}'")
                        else:
                            feedback_parts.append(
                                f"[+0] {target_display} not properly named (found: '{result['placemark_name']}')"
                            )
                    else:
                        feedback_parts.append(f"[+0] {target_display} placemark not found at expected location")
                
                details["placemarks_found"] = placemarks_found
                
                # ================================================================
                # STEP 7: Bonus for all placemarks in folder
                # ================================================================
                if placemarks_found >= 3:
                    score += 15
                    feedback_parts.append("[+15] All three placemarks correctly placed in folder")
                elif placemarks_found >= 2:
                    score += 10
                    feedback_parts.append(f"[+10] {placemarks_found}/3 placemarks in folder (partial credit)")
                elif placemarks_found >= 1:
                    score += 5
                    feedback_parts.append(f"[+5] {placemarks_found}/3 placemarks in folder (minimal credit)")
                    
            else:
                feedback_parts.append("[+0] 'Ancient Wonders' folder NOT found")
                details["folder_found"] = False
                
                # Check if placemarks exist anywhere (partial credit opportunity)
                all_placemarks = extract_placemarks(root)
                details["total_placemarks"] = len(all_placemarks)
                
                if all_placemarks:
                    feedback_parts.append(f"Note: Found {len(all_placemarks)} placemarks outside expected folder")
    
    # ================================================================
    # STEP 8: VLM trajectory verification
    # ================================================================
    vlm_score = 0
    if query_vlm:
        vlm_result = verify_via_vlm(traj, query_vlm)
        details["vlm_result"] = vlm_result
        
        if vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            
            # Award points for VLM-verified actions
            vlm_checks = [
                ("google_earth_used", 2, "Google Earth interface confirmed"),
                ("folder_created", 3, "Folder creation activity detected"),
                ("navigation_occurred", 2, "Navigation activity confirmed"),
                ("placemarks_created", 3, "Placemark creation detected"),
                ("multiple_locations", 3, "Multiple locations visited"),
                ("workflow_progression", 2, "Meaningful workflow progression"),
            ]
            
            for key, points, desc in vlm_checks:
                if parsed.get(key, False):
                    vlm_score += points
                    feedback_parts.append(f"[VLM +{points}] {desc}")
            
            confidence = parsed.get("confidence", "low")
            if confidence == "high" and vlm_score >= 10:
                vlm_score += 5
                feedback_parts.append("[VLM +5] High confidence verification")
            
            details["vlm_observations"] = parsed.get("observations", "")
            details["vlm_locations"] = parsed.get("locations_observed", [])
        else:
            feedback_parts.append(f"[VLM] Verification failed: {vlm_result.get('error', 'unknown')}")
    else:
        feedback_parts.append("[VLM] Not available for verification")
    
    # Cap VLM bonus at 15 points (to not dominate score)
    vlm_score = min(vlm_score, 15)
    details["vlm_score"] = vlm_score
    
    # Note: VLM score is used as a confidence boost but doesn't add to main score
    # to prevent inflating scores when KML verification fails
    
    # ================================================================
    # FINAL ASSESSMENT
    # ================================================================
    details["final_score"] = score
    
    # Determine pass criteria
    folder_found = details.get("folder_found", False)
    placemarks_found = details.get("placemarks_found", 0)
    
    # Pass requires: score >= 70 AND (folder created AND at least 2 placemarks)
    key_criteria_met = folder_found and placemarks_found >= 2
    passed = score >= 70 and key_criteria_met
    
    # Allow pass with lower score if VLM strongly confirms success
    if not passed and score >= 50 and vlm_score >= 12 and folder_found:
        passed = True
        feedback_parts.append("[PASS via VLM] Strong trajectory evidence compensates for partial KML verification")
    
    details["key_criteria_met"] = key_criteria_met
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "details": details
    }