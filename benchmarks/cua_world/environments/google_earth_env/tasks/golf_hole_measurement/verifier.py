#!/usr/bin/env python3
"""
Verifier for Golf Hole Measurement Task.

VERIFICATION STRATEGY (Multi-signal, anti-gaming):
1. KML file analysis - check for new paths with correct coordinates (35 pts)
2. Timestamp verification - ensure work done during task (15 pts)
3. Coordinate validation - path endpoints near Augusta 12th hole (20 pts)
4. Distance accuracy - measurement matches known hole length (10 pts)
5. VLM trajectory verification - agent actually used Google Earth (20 pts)

Pass threshold: 60 points with KML evidence of measurement creation.

Uses copy_from_env (NOT exec_in_env) per framework requirements.
Uses trajectory frames (NOT just final screenshot) for VLM verification.
"""

import json
import tempfile
import os
import math
import logging
import re
import base64
import xml.etree.ElementTree as ET
from typing import Dict, Any, List, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ================================================================
# CONSTANTS - Task-specific parameters
# ================================================================

# Augusta National 12th Hole coordinates
TARGET = {
    "tee_lat": 33.5031,
    "tee_lon": -81.9978,
    "green_lat": 33.5025,
    "green_lon": -81.9968,
    "course_center_lat": 33.503,
    "course_center_lon": -81.998,
    "expected_distance_m": 142,
    "distance_tolerance_m": 18,
    "tee_tolerance_m": 30,
    "green_tolerance_m": 25,
    "course_radius_m": 1000  # Must be within 1km of course center
}

# Keywords that indicate relevant path naming
NAME_KEYWORDS = ["augusta", "12", "twelfth", "golden", "bell", "golf", "hole", "distance"]


# ================================================================
# UTILITY FUNCTIONS
# ================================================================

def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate distance between two coordinates in meters."""
    R = 6371000  # Earth radius in meters
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    
    a = math.sin(dphi/2)**2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    
    return R * c


def parse_kml_paths(kml_content: str) -> List[Dict[str, Any]]:
    """Extract path/line coordinates from KML content."""
    paths = []
    
    try:
        # Remove XML declaration if present (can cause parsing issues)
        if kml_content.startswith('<?xml'):
            kml_content = kml_content[kml_content.find('?>') + 2:]
        
        # Try parsing with namespace handling
        root = ET.fromstring(kml_content)
        
        # Handle KML namespace
        namespaces = {
            'kml': 'http://www.opengis.net/kml/2.2',
            'gx': 'http://www.google.com/kml/ext/2.2'
        }
        
        # Find all Placemarks (with and without namespace)
        placemarks = root.findall('.//kml:Placemark', namespaces)
        if not placemarks:
            placemarks = root.findall('.//{http://www.opengis.net/kml/2.2}Placemark')
        if not placemarks:
            # Try without namespace
            placemarks = root.findall('.//Placemark')
        
        for placemark in placemarks:
            name = ""
            coords = []
            
            # Get name
            name_elem = placemark.find('kml:name', namespaces) or \
                       placemark.find('{http://www.opengis.net/kml/2.2}name') or \
                       placemark.find('name')
            if name_elem is not None and name_elem.text:
                name = name_elem.text.strip()
            
            # Get coordinates from LineString (paths/ruler measurements)
            for coord_elem in placemark.iter():
                if 'coordinates' in coord_elem.tag.lower() and coord_elem.text:
                    coord_text = coord_elem.text.strip()
                    for point in coord_text.split():
                        point = point.strip()
                        if ',' in point:
                            parts = point.split(',')
                            if len(parts) >= 2:
                                try:
                                    lon = float(parts[0])
                                    lat = float(parts[1])
                                    coords.append((lat, lon))
                                except ValueError:
                                    continue
            
            if coords:
                paths.append({
                    "name": name,
                    "coordinates": coords,
                    "num_points": len(coords)
                })
    
    except ET.ParseError as e:
        logger.warning(f"KML XML parsing error: {e}")
        # Try regex fallback for coordinates
        paths = parse_kml_regex_fallback(kml_content)
    except Exception as e:
        logger.warning(f"KML parsing error: {e}")
    
    return paths


def parse_kml_regex_fallback(kml_content: str) -> List[Dict[str, Any]]:
    """Fallback regex-based KML parsing."""
    paths = []
    
    # Find coordinate blocks
    coord_pattern = r'<coordinates>\s*([\s\S]*?)\s*</coordinates>'
    name_pattern = r'<name>\s*(.*?)\s*</name>'
    
    # Find all placemarks
    placemark_pattern = r'<Placemark>([\s\S]*?)</Placemark>'
    
    for match in re.finditer(placemark_pattern, kml_content, re.IGNORECASE):
        placemark_content = match.group(1)
        
        # Extract name
        name = ""
        name_match = re.search(name_pattern, placemark_content, re.IGNORECASE)
        if name_match:
            name = name_match.group(1).strip()
        
        # Extract coordinates
        coords = []
        coord_match = re.search(coord_pattern, placemark_content, re.IGNORECASE)
        if coord_match:
            coord_text = coord_match.group(1)
            for point in coord_text.split():
                point = point.strip()
                if ',' in point:
                    parts = point.split(',')
                    if len(parts) >= 2:
                        try:
                            lon = float(parts[0])
                            lat = float(parts[1])
                            coords.append((lat, lon))
                        except ValueError:
                            continue
        
        if coords:
            paths.append({
                "name": name,
                "coordinates": coords,
                "num_points": len(coords)
            })
    
    return paths


def analyze_path(path: Dict[str, Any]) -> Dict[str, Any]:
    """Analyze a path for Augusta 12th hole measurement characteristics."""
    if len(path["coordinates"]) < 2:
        return None
    
    start = path["coordinates"][0]
    end = path["coordinates"][-1]
    
    # Calculate distances from expected points (both orientations)
    start_to_tee = haversine_distance(start[0], start[1], TARGET["tee_lat"], TARGET["tee_lon"])
    end_to_green = haversine_distance(end[0], end[1], TARGET["green_lat"], TARGET["green_lon"])
    start_to_green = haversine_distance(start[0], start[1], TARGET["green_lat"], TARGET["green_lon"])
    end_to_tee = haversine_distance(end[0], end[1], TARGET["tee_lat"], TARGET["tee_lon"])
    
    # Distance from course center
    start_to_course = haversine_distance(start[0], start[1], 
                                         TARGET["course_center_lat"], TARGET["course_center_lon"])
    end_to_course = haversine_distance(end[0], end[1],
                                       TARGET["course_center_lat"], TARGET["course_center_lon"])
    
    # Path distance
    path_distance = haversine_distance(start[0], start[1], end[0], end[1])
    
    # Check both orientations
    forward_valid = (start_to_tee <= TARGET["tee_tolerance_m"] and 
                     end_to_green <= TARGET["green_tolerance_m"])
    reverse_valid = (start_to_green <= TARGET["green_tolerance_m"] and 
                     end_to_tee <= TARGET["tee_tolerance_m"])
    
    # Check if within Augusta National area
    at_augusta = (start_to_course <= TARGET["course_radius_m"] and 
                  end_to_course <= TARGET["course_radius_m"])
    
    # Check distance accuracy
    distance_accurate = abs(path_distance - TARGET["expected_distance_m"]) <= TARGET["distance_tolerance_m"]
    
    return {
        "name": path["name"],
        "start": start,
        "end": end,
        "path_distance_m": path_distance,
        "start_to_tee_m": start_to_tee,
        "end_to_green_m": end_to_green,
        "start_to_course_m": start_to_course,
        "end_to_course_m": end_to_course,
        "forward_valid": forward_valid,
        "reverse_valid": reverse_valid,
        "endpoints_valid": forward_valid or reverse_valid,
        "at_augusta": at_augusta,
        "distance_accurate": distance_accurate
    }


def check_name_relevance(name: str) -> bool:
    """Check if path name indicates Augusta/12th hole measurement."""
    if not name:
        return False
    name_lower = name.lower()
    return any(kw in name_lower for kw in NAME_KEYWORDS)


# ================================================================
# VLM VERIFICATION
# ================================================================

TRAJECTORY_PROMPT = """You are analyzing a sequence of screenshots from an agent performing a golf course measurement task in Google Earth.

TASK: Navigate to Augusta National Golf Club and measure the distance of the 12th hole (Golden Bell) from tee to green using the Ruler tool.

The images show the agent's progress chronologically. Look for evidence of:
1. Google Earth being used (satellite imagery interface)
2. Navigation to Augusta National Golf Club area (green golf course visible)
3. Zooming in to see individual holes/features
4. Using the Ruler/measurement tool (a line being drawn, ruler dialog)
5. The 12th hole area visible (par-3 with water in front, near Amen Corner)

Assess:
1. IS_GOOGLE_EARTH: Is Google Earth being used throughout?
2. NAVIGATED_TO_AUGUSTA: Did the agent navigate to a golf course area?
3. USED_RULER_TOOL: Is there evidence of measurement tool usage (ruler line, measurement dialog)?
4. GOLF_COURSE_VISIBLE: Can you see golf course features (fairways, greens, bunkers)?
5. MEANINGFUL_WORK: Does the trajectory show actual task progression (not idle)?

Respond in JSON format:
{
    "is_google_earth": true/false,
    "navigated_to_augusta": true/false,
    "used_ruler_tool": true/false,
    "golf_course_visible": true/false,
    "meaningful_work": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see across the frames"
}
"""


def verify_via_vlm(traj: Dict[str, Any], query_vlm) -> Dict[str, Any]:
    """Verify task completion using VLM on trajectory frames."""
    if not query_vlm:
        return {"success": False, "error": "VLM query function not available"}
    
    # Import trajectory utilities
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    except ImportError:
        logger.warning("Could not import gym_anything.vlm utilities")
        return {"success": False, "error": "VLM utilities not available"}
    
    # Get trajectory frames (sample across the episode, not just final)
    frames = sample_trajectory_frames(traj, n=5)  # Sample 5 frames across trajectory
    final_frame = get_final_screenshot(traj)
    
    if final_frame:
        frames.append(final_frame)
    
    if not frames:
        return {"success": False, "error": "No trajectory frames available"}
    
    # Query VLM with multiple images
    try:
        vlm_result = query_vlm(
            prompt=TRAJECTORY_PROMPT,
            images=frames
        )
        
        if not vlm_result.get("success"):
            return {"success": False, "error": vlm_result.get("error", "VLM query failed")}
        
        parsed = vlm_result.get("parsed", {})
        
        # Calculate VLM score based on criteria
        vlm_criteria = [
            parsed.get("is_google_earth", False),
            parsed.get("navigated_to_augusta", False),
            parsed.get("used_ruler_tool", False),
            parsed.get("golf_course_visible", False),
            parsed.get("meaningful_work", False)
        ]
        
        vlm_score = sum(vlm_criteria)
        confidence = parsed.get("confidence", "low")
        
        # Adjust score based on confidence
        confidence_multiplier = {"high": 1.0, "medium": 0.85, "low": 0.7}.get(confidence, 0.7)
        adjusted_score = int((vlm_score / 5) * 20 * confidence_multiplier)  # Max 20 points
        
        return {
            "success": True,
            "score": adjusted_score,
            "criteria_met": vlm_score,
            "total_criteria": 5,
            "confidence": confidence,
            "details": parsed,
            "frames_analyzed": len(frames)
        }
    
    except Exception as e:
        logger.warning(f"VLM verification exception: {e}")
        return {"success": False, "error": str(e)}


# ================================================================
# MAIN VERIFICATION FUNCTION
# ================================================================

def verify_golf_hole_measurement(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the golf hole measurement task.
    
    Multi-criteria scoring:
    - KML file with new path exists (15 pts)
    - Path created during task - timestamp check (15 pts)
    - Path endpoints at Augusta National (20 pts)
    - Path endpoints match 12th hole tee/green (15 pts)
    - Distance measurement accurate (10 pts)
    - Path has relevant name (5 pts)
    - VLM trajectory verification (20 pts)
    
    Total: 100 pts
    Pass threshold: 60 pts with KML evidence
    """
    
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available for verification"
        }
    
    metadata = task_info.get('metadata', {})
    feedback_parts = []
    details = {}
    score = 0
    
    # ================================================================
    # STEP 1: Copy and parse task result JSON
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        details["result_loaded"] = True
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Failed to load task result: {e}",
            "details": {"error": str(e)}
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # Extract key metrics from result
    kml_state = result.get("kml_state", {})
    task_start = result.get("task_start_time", 0)
    ge_state = result.get("google_earth_state", {})
    
    details["task_start_time"] = task_start
    details["kml_exists"] = kml_state.get("exists", False)
    details["kml_modified"] = kml_state.get("modified_during_task", False)
    details["new_paths"] = kml_state.get("new_paths", 0)
    details["ge_running"] = ge_state.get("running", False)
    
    # ================================================================
    # STEP 2: Copy and analyze KML file
    # ================================================================
    kml_content = ""
    paths = []
    
    # Try myplaces.kml first
    temp_kml = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
    try:
        copy_from_env("/tmp/task_state/myplaces_final.kml", temp_kml.name)
        with open(temp_kml.name, 'r', encoding='utf-8', errors='ignore') as f:
            kml_content = f.read()
        details["kml_file_copied"] = True
    except Exception as e:
        logger.warning(f"Could not copy myplaces KML: {e}")
        details["kml_file_copied"] = False
    finally:
        if os.path.exists(temp_kml.name):
            os.unlink(temp_kml.name)
    
    # Also try exported KML
    if not kml_content:
        temp_exported = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
        try:
            copy_from_env("/tmp/task_state/exported.kml", temp_exported.name)
            with open(temp_exported.name, 'r', encoding='utf-8', errors='ignore') as f:
                kml_content = f.read()
            details["exported_kml_used"] = True
        except:
            pass
        finally:
            if os.path.exists(temp_exported.name):
                os.unlink(temp_exported.name)
    
    # Parse KML for paths
    if kml_content:
        paths = parse_kml_paths(kml_content)
        details["paths_found"] = len(paths)
    else:
        details["paths_found"] = 0
    
    # ================================================================
    # CRITERION 1: KML file with new path exists (15 pts)
    # ================================================================
    if kml_state.get("exists", False) and kml_state.get("new_paths", 0) > 0:
        score += 15
        feedback_parts.append("✅ New path created in KML")
    elif kml_state.get("exists", False) and len(paths) > 0:
        score += 10
        feedback_parts.append("⚠️ KML has paths (may be pre-existing)")
    else:
        feedback_parts.append("❌ No new paths in KML")
    
    # ================================================================
    # CRITERION 2: Timestamp verification (15 pts)
    # ================================================================
    if kml_state.get("modified_during_task", False):
        score += 15
        feedback_parts.append("✅ KML modified during task")
        details["timestamp_valid"] = True
    else:
        feedback_parts.append("❌ KML not modified during task")
        details["timestamp_valid"] = False
    
    # ================================================================
    # CRITERIA 3-6: Analyze paths for Augusta 12th hole
    # ================================================================
    best_match = None
    best_match_score = 0
    
    for path in paths:
        analysis = analyze_path(path)
        if not analysis:
            continue
        
        path_score = 0
        
        # At Augusta National area (20 pts potential)
        if analysis["at_augusta"]:
            path_score += 20
        
        # Correct endpoints (15 pts potential)
        if analysis["endpoints_valid"]:
            path_score += 15
        
        # Distance accuracy (10 pts potential)
        if analysis["distance_accurate"]:
            path_score += 10
        
        # Relevant name (5 pts potential)
        if check_name_relevance(analysis["name"]):
            path_score += 5
        
        if path_score > best_match_score:
            best_match_score = path_score
            best_match = analysis
    
    # Add best match score
    score += best_match_score
    
    if best_match:
        details["best_match"] = {
            "name": best_match["name"],
            "distance_m": round(best_match["path_distance_m"], 1),
            "expected_m": TARGET["expected_distance_m"],
            "at_augusta": best_match["at_augusta"],
            "endpoints_valid": best_match["endpoints_valid"],
            "distance_accurate": best_match["distance_accurate"]
        }
        
        if best_match["at_augusta"]:
            feedback_parts.append("✅ Path is at Augusta National")
        else:
            feedback_parts.append("❌ Path not at Augusta National")
        
        if best_match["endpoints_valid"]:
            feedback_parts.append("✅ Endpoints match 12th hole tee/green")
        else:
            feedback_parts.append("⚠️ Endpoints not precisely at 12th hole")
        
        if best_match["distance_accurate"]:
            feedback_parts.append(f"✅ Distance accurate ({best_match['path_distance_m']:.0f}m)")
        else:
            feedback_parts.append(f"⚠️ Distance: {best_match['path_distance_m']:.0f}m (expected ~{TARGET['expected_distance_m']}m)")
        
        if check_name_relevance(best_match["name"]):
            feedback_parts.append(f"✅ Relevant name: '{best_match['name']}'")
    else:
        feedback_parts.append("❌ No valid measurement path found")
    
    # ================================================================
    # CRITERION 7: VLM trajectory verification (20 pts)
    # ================================================================
    vlm_result = verify_via_vlm(traj, query_vlm)
    details["vlm_verification"] = vlm_result
    
    if vlm_result.get("success"):
        vlm_score = vlm_result.get("score", 0)
        score += vlm_score
        
        if vlm_score >= 15:
            feedback_parts.append(f"✅ VLM: Task workflow verified ({vlm_result.get('criteria_met', 0)}/5 criteria)")
        elif vlm_score >= 8:
            feedback_parts.append(f"⚠️ VLM: Partial workflow evidence ({vlm_result.get('criteria_met', 0)}/5 criteria)")
        else:
            feedback_parts.append(f"❌ VLM: Limited workflow evidence ({vlm_result.get('criteria_met', 0)}/5 criteria)")
    else:
        feedback_parts.append(f"⚠️ VLM verification unavailable: {vlm_result.get('error', 'unknown')}")
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    
    # Key criteria for passing: must have KML evidence of work
    has_kml_evidence = (
        kml_state.get("modified_during_task", False) or 
        (best_match is not None and best_match.get("at_augusta", False))
    )
    
    passed = score >= 60 and has_kml_evidence
    
    details["final_score"] = score
    details["max_score"] = 100
    details["passed"] = passed
    details["has_kml_evidence"] = has_kml_evidence
    
    # Summary feedback
    if passed:
        feedback_summary = f"✅ PASSED ({score}/100)"
    else:
        if not has_kml_evidence:
            feedback_summary = f"❌ FAILED ({score}/100) - No KML measurement evidence"
        else:
            feedback_summary = f"❌ FAILED ({score}/100) - Score below threshold"
    
    feedback = feedback_summary + "\n" + " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }