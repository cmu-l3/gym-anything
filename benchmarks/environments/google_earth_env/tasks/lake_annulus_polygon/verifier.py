#!/usr/bin/env python3
"""
Verifier for Taal Lake Annulus Polygon task.

VERIFICATION STRATEGY:
1. KML file exists and was created during task (20 points)
2. Valid KML structure with Polygon element (10 points)
3. Has outer boundary with coordinates (15 points)
4. Has inner boundary (hole) - CRITICAL REQUIREMENT (25 points)
5. Outer boundary within Taal Lake geographic bounds (10 points)
6. Inner boundary near Volcano Island (10 points)
7. VLM trajectory verification - shows polygon creation workflow (10 points)

Pass threshold: 70 points AND inner boundary must be present
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

# Geographic bounds for Taal Lake
TAAL_BOUNDS = {
    "north": 14.15,
    "south": 13.85,
    "east": 121.10,
    "west": 120.85
}

# Volcano Island approximate center
VOLCANO_ISLAND_CENTER = {
    "lat": 14.009,
    "lon": 120.993
}


def parse_kml_coordinates(coord_string: str) -> List[Tuple[float, float, float]]:
    """Parse KML coordinate string into list of (lon, lat, alt) tuples."""
    coords = []
    if not coord_string:
        return coords
    
    for point in coord_string.strip().split():
        point = point.strip()
        if not point:
            continue
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


def coords_within_bounds(coords: List[Tuple[float, float, float]], bounds: Dict) -> bool:
    """Check if most coordinates fall within geographic bounds."""
    if not coords:
        return False
    
    in_bounds = 0
    for lon, lat, _ in coords:
        if (bounds["west"] <= lon <= bounds["east"] and 
            bounds["south"] <= lat <= bounds["north"]):
            in_bounds += 1
    
    # At least 70% should be within bounds
    return in_bounds >= len(coords) * 0.7


def coords_near_location(coords: List[Tuple[float, float, float]], 
                         center_lat: float, center_lon: float, 
                         max_dist_deg: float = 0.08) -> bool:
    """Check if coordinates are near a specific location."""
    if not coords:
        return False
    
    near_count = 0
    for lon, lat, _ in coords:
        dist = math.sqrt((lon - center_lon)**2 + (lat - center_lat)**2)
        if dist < max_dist_deg:
            near_count += 1
    
    # At least 3 points should be near the location
    return near_count >= 3


def calculate_polygon_area_km2(coords: List[Tuple[float, float, float]]) -> float:
    """Calculate polygon area using shoelace formula, result in km²."""
    if len(coords) < 3:
        return 0
    
    # Using spherical approximation at Taal Lake latitude
    lat_center = 14.0
    lon_to_km = 111.32 * math.cos(math.radians(lat_center))
    lat_to_km = 110.574
    
    # Convert to km coordinates
    km_coords = [(c[0] * lon_to_km, c[1] * lat_to_km) for c in coords]
    
    # Shoelace formula
    n = len(km_coords)
    area = 0
    for i in range(n):
        j = (i + 1) % n
        area += km_coords[i][0] * km_coords[j][1]
        area -= km_coords[j][0] * km_coords[i][1]
    
    return abs(area) / 2


def parse_kml_for_polygon(kml_content: str) -> Dict[str, Any]:
    """Parse KML content and extract polygon information."""
    result = {
        "valid_xml": False,
        "has_polygon": False,
        "has_outer_boundary": False,
        "has_inner_boundary": False,
        "outer_coords": [],
        "inner_coords": [],
        "polygon_name": "",
        "error": None
    }
    
    if not kml_content:
        result["error"] = "Empty KML content"
        return result
    
    try:
        # Parse XML
        root = ET.fromstring(kml_content)
        result["valid_xml"] = True
        
        # Handle KML namespace
        ns = {'kml': 'http://www.opengis.net/kml/2.2'}
        if root.tag.startswith('{'):
            ns_match = re.match(r'\{(.+)\}', root.tag)
            if ns_match:
                ns = {'kml': ns_match.group(1)}
        
        # Find Polygon element (try various paths)
        polygon = None
        for elem in root.iter():
            tag = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
            if tag == 'Polygon':
                polygon = elem
                break
        
        if polygon is None:
            result["error"] = "No Polygon element found"
            return result
        
        result["has_polygon"] = True
        
        # Try to find polygon name from parent Placemark
        for elem in root.iter():
            tag = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
            if tag == 'name':
                if elem.text:
                    result["polygon_name"] = elem.text
                    break
        
        # Find outer and inner boundaries
        for elem in polygon.iter():
            tag = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
            
            if tag == 'outerBoundaryIs':
                for sub in elem.iter():
                    sub_tag = sub.tag.split('}')[-1] if '}' in sub.tag else sub.tag
                    if sub_tag == 'coordinates' and sub.text:
                        result["outer_coords"] = parse_kml_coordinates(sub.text)
                        if result["outer_coords"]:
                            result["has_outer_boundary"] = True
            
            elif tag == 'innerBoundaryIs':
                for sub in elem.iter():
                    sub_tag = sub.tag.split('}')[-1] if '}' in sub.tag else sub.tag
                    if sub_tag == 'coordinates' and sub.text:
                        result["inner_coords"] = parse_kml_coordinates(sub.text)
                        if result["inner_coords"]:
                            result["has_inner_boundary"] = True
        
    except ET.ParseError as e:
        result["error"] = f"XML parse error: {e}"
    except Exception as e:
        result["error"] = f"Unexpected error: {e}"
    
    return result


# VLM Prompts
TRAJECTORY_VERIFICATION_PROMPT = """You are analyzing screenshots from an agent creating a polygon in Google Earth Pro.

The task was to create an "annulus" (donut-shaped) polygon at Taal Lake, Philippines, which has Volcano Island in its center. The polygon should have:
1. An outer boundary around the lake shore
2. An inner boundary (hole) around Volcano Island

Analyze these trajectory screenshots and determine:

1. GOOGLE_EARTH_VISIBLE: Is Google Earth Pro visible in any frames?
2. TAAL_LAKE_AREA: Do any frames show Taal Lake (a large lake with an island in the center)?
3. POLYGON_CREATION: Is there evidence of polygon creation (polygon tool used, points being placed)?
4. INNER_BOUNDARY_EVIDENCE: Is there any visual evidence of creating an inner boundary/hole?
   - Look for: a second set of points inside the polygon, donut shape, or polygon editing
5. WORKFLOW_PROGRESSION: Do the frames show meaningful progression through the task?

Respond in JSON format:
{
    "google_earth_visible": true/false,
    "taal_lake_area_shown": true/false,
    "polygon_creation_visible": true/false,
    "inner_boundary_evidence": true/false,
    "workflow_progression": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see across the frames"
}
"""


def verify_lake_annulus_polygon(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the Taal Lake Annulus Polygon task.
    
    Uses multiple verification signals:
    1. KML file analysis (programmatic)
    2. Timestamp verification (anti-gaming)
    3. Geographic validation
    4. VLM trajectory verification
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
    expected_output_path = metadata.get('expected_output_path', '/home/ga/Documents/taal_lake_polygon.kml')
    
    feedback_parts = []
    details = {}
    score = 0
    max_score = 100
    
    # ================================================================
    # STEP 1: Copy result file from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
        details["result_data_loaded"] = True
    except Exception as e:
        logger.warning(f"Could not load result JSON: {e}")
        details["result_data_loaded"] = False
        details["result_error"] = str(e)
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # STEP 2: Copy and analyze KML file
    # ================================================================
    temp_kml = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
    kml_content = ""
    kml_copied = False
    
    try:
        copy_from_env("/tmp/taal_lake_polygon.kml", temp_kml.name)
        with open(temp_kml.name, 'r') as f:
            kml_content = f.read()
        kml_copied = True
    except Exception as e1:
        # Try alternate path
        try:
            copy_from_env(expected_output_path, temp_kml.name)
            with open(temp_kml.name, 'r') as f:
                kml_content = f.read()
            kml_copied = True
        except Exception as e2:
            logger.warning(f"Could not copy KML file: {e1}, {e2}")
    finally:
        if os.path.exists(temp_kml.name):
            os.unlink(temp_kml.name)
    
    # Also try getting KML content from result JSON
    if not kml_content and result_data.get("kml_content"):
        kml_content = result_data.get("kml_content", "")
        if kml_content:
            kml_copied = True
    
    # ================================================================
    # CRITERION 1: KML file exists and was created during task (20 points)
    # ================================================================
    output_exists = result_data.get("output_exists", False) or kml_copied
    file_created_during_task = result_data.get("file_created_during_task", False)
    
    if output_exists:
        score += 10
        feedback_parts.append("✅ KML file exists")
        details["kml_exists"] = True
        
        if file_created_during_task:
            score += 10
            feedback_parts.append("✅ File created during task (anti-gaming check passed)")
            details["created_during_task"] = True
        else:
            feedback_parts.append("⚠️ File may have existed before task")
            details["created_during_task"] = False
    else:
        feedback_parts.append("❌ KML file not found")
        details["kml_exists"] = False
        # Without the KML file, we can only do VLM verification
    
    # ================================================================
    # CRITERION 2-6: KML Content Analysis
    # ================================================================
    kml_analysis = parse_kml_for_polygon(kml_content)
    details["kml_analysis"] = kml_analysis
    
    # CRITERION 2: Valid KML structure (10 points)
    if kml_analysis["valid_xml"] and kml_analysis["has_polygon"]:
        score += 10
        feedback_parts.append("✅ Valid KML with Polygon element")
    elif kml_analysis["valid_xml"]:
        score += 5
        feedback_parts.append("⚠️ Valid XML but no Polygon found")
    else:
        feedback_parts.append("❌ Invalid KML structure")
        if kml_analysis["error"]:
            details["kml_error"] = kml_analysis["error"]
    
    # CRITERION 3: Has outer boundary (15 points)
    if kml_analysis["has_outer_boundary"]:
        outer_count = len(kml_analysis["outer_coords"])
        score += 15
        feedback_parts.append(f"✅ Outer boundary found ({outer_count} points)")
        details["outer_boundary_points"] = outer_count
    else:
        feedback_parts.append("❌ No outer boundary found")
    
    # CRITERION 4: Has inner boundary - CRITICAL (25 points)
    has_inner = kml_analysis["has_inner_boundary"]
    if has_inner:
        inner_count = len(kml_analysis["inner_coords"])
        score += 25
        feedback_parts.append(f"✅ INNER BOUNDARY (hole) found ({inner_count} points) - CRITICAL REQUIREMENT MET")
        details["inner_boundary_points"] = inner_count
        details["has_inner_ring"] = True
    else:
        feedback_parts.append("❌ NO INNER BOUNDARY - Polygon must have hole around Volcano Island!")
        details["has_inner_ring"] = False
    
    # CRITERION 5: Outer boundary within Taal Lake bounds (10 points)
    if kml_analysis["outer_coords"]:
        if coords_within_bounds(kml_analysis["outer_coords"], TAAL_BOUNDS):
            score += 10
            feedback_parts.append("✅ Outer boundary positioned at Taal Lake")
            details["outer_location_correct"] = True
        else:
            score += 3  # Partial credit
            feedback_parts.append("⚠️ Outer boundary location may be off")
            details["outer_location_correct"] = False
    
    # CRITERION 6: Inner boundary near Volcano Island (10 points)
    if kml_analysis["inner_coords"]:
        if coords_near_location(kml_analysis["inner_coords"], 
                               VOLCANO_ISLAND_CENTER["lat"], 
                               VOLCANO_ISLAND_CENTER["lon"]):
            score += 10
            feedback_parts.append("✅ Inner boundary correctly positioned around Volcano Island")
            details["inner_location_correct"] = True
        else:
            score += 4  # Partial credit
            feedback_parts.append("⚠️ Inner boundary location may not match Volcano Island")
            details["inner_location_correct"] = False
    
    # Calculate areas if we have coordinates
    if kml_analysis["outer_coords"]:
        outer_area = calculate_polygon_area_km2(kml_analysis["outer_coords"])
        details["outer_area_km2"] = round(outer_area, 2)
        
        if kml_analysis["inner_coords"]:
            inner_area = calculate_polygon_area_km2(kml_analysis["inner_coords"])
            water_area = outer_area - inner_area
            details["inner_area_km2"] = round(inner_area, 2)
            details["water_area_km2"] = round(water_area, 2)
    
    # ================================================================
    # CRITERION 7: VLM Trajectory Verification (10 points)
    # ================================================================
    vlm_score = 0
    
    if query_vlm:
        # Get trajectory frames
        frames = traj.get('frames', [])
        trajectory_images = []
        
        # Sample frames across trajectory (up to 6 frames)
        if frames:
            n_frames = len(frames)
            if n_frames <= 6:
                indices = list(range(n_frames))
            else:
                # Sample evenly across trajectory
                step = n_frames // 5
                indices = [0, step, 2*step, 3*step, 4*step, n_frames-1]
            
            for idx in indices:
                if idx < len(frames) and frames[idx]:
                    trajectory_images.append(frames[idx])
        
        # Also check for screenshot files in episode directory
        episode_dir = traj.get('episode_dir', '')
        if episode_dir and os.path.isdir(episode_dir):
            import glob
            screenshot_files = sorted(glob.glob(os.path.join(episode_dir, '*.png')))[:6]
            for sf in screenshot_files:
                try:
                    with open(sf, 'rb') as f:
                        trajectory_images.append(f.read())
                except:
                    pass
        
        if trajectory_images:
            try:
                vlm_result = query_vlm(
                    prompt=TRAJECTORY_VERIFICATION_PROMPT,
                    images=trajectory_images[:6]  # Limit to 6 images
                )
                
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    details["vlm_analysis"] = parsed
                    
                    # Score VLM criteria
                    vlm_criteria = 0
                    if parsed.get("google_earth_visible"):
                        vlm_criteria += 1
                    if parsed.get("taal_lake_area_shown"):
                        vlm_criteria += 1
                    if parsed.get("polygon_creation_visible"):
                        vlm_criteria += 1
                    if parsed.get("inner_boundary_evidence"):
                        vlm_criteria += 2  # Extra weight for inner boundary evidence
                    if parsed.get("workflow_progression"):
                        vlm_criteria += 1
                    
                    # Max 6 criteria points -> 10 score points
                    vlm_score = min(10, int((vlm_criteria / 6) * 10))
                    
                    confidence = parsed.get("confidence", "low")
                    if confidence == "high":
                        vlm_score = min(10, vlm_score + 2)
                    elif confidence == "low":
                        vlm_score = max(0, vlm_score - 2)
                    
                    score += vlm_score
                    feedback_parts.append(f"✅ VLM verification: {vlm_score}/10 points")
                else:
                    feedback_parts.append("⚠️ VLM verification inconclusive")
                    details["vlm_error"] = vlm_result.get("error", "Unknown")
            except Exception as e:
                feedback_parts.append(f"⚠️ VLM verification failed: {e}")
                details["vlm_exception"] = str(e)
        else:
            feedback_parts.append("⚠️ No trajectory images available for VLM verification")
    else:
        feedback_parts.append("⚠️ VLM not available for trajectory verification")
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    details["vlm_score"] = vlm_score
    details["total_score"] = score
    details["max_score"] = max_score
    
    # Pass criteria: 70+ points AND must have inner boundary
    passed = score >= 70 and has_inner
    
    if not has_inner:
        feedback_parts.append("\n⚠️ TASK FAILED: Inner boundary (hole) is REQUIRED for this task!")
    
    # Generate summary
    summary = f"Score: {score}/{max_score}"
    if has_inner:
        summary += " | ✅ Has inner ring (annulus shape)"
    else:
        summary += " | ❌ Missing inner ring"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "summary": summary,
        "details": details
    }