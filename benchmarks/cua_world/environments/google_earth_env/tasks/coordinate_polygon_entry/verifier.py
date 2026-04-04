#!/usr/bin/env python3
"""
Verifier for coordinate_polygon_entry task.

VERIFICATION STRATEGY:
1. KML file exists and was created during task (anti-gaming)
2. KML contains valid polygon structure
3. Polygon name matches "TFR Zone Alpha"
4. All four vertices match expected coordinates within tolerance
5. VLM trajectory verification shows polygon creation workflow
6. Styling check (red color)

Uses copy_from_env (NOT exec_in_env) to retrieve files from container.
Uses trajectory frames for VLM verification to prevent gaming.
"""

import json
import tempfile
import os
import re
import logging
import xml.etree.ElementTree as ET
from typing import Dict, Any, List, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected coordinates for TFR Zone Alpha
EXPECTED_COORDS = [
    (36.2358, -115.0842),  # A - NW
    (36.2358, -115.0156),  # B - NE
    (36.1872, -115.0156),  # C - SE
    (36.1872, -115.0842),  # D - SW
]
EXPECTED_NAME = "TFR Zone Alpha"
TOLERANCE = 0.001  # degrees (~111 meters)


def coord_matches(actual: Tuple[float, float], expected: Tuple[float, float], tolerance: float) -> bool:
    """Check if a coordinate matches within tolerance."""
    lat_diff = abs(actual[0] - expected[0])
    lon_diff = abs(actual[1] - expected[1])
    return lat_diff <= tolerance and lon_diff <= tolerance


def parse_kml_coordinates(kml_content: str) -> Optional[List[Tuple[float, float]]]:
    """Parse KML content and extract polygon coordinates."""
    try:
        # Handle KML namespace
        kml_content = re.sub(r'xmlns="[^"]+"', '', kml_content)
        root = ET.fromstring(kml_content)
        
        # Find coordinates element (try different paths)
        coords_elem = None
        for path in ['.//coordinates', './/Polygon//coordinates', 
                     './/LinearRing/coordinates', './/outerBoundaryIs//coordinates']:
            coords_elem = root.find(path)
            if coords_elem is not None and coords_elem.text:
                break
        
        if coords_elem is None or not coords_elem.text:
            logger.warning("No coordinates element found in KML")
            return None
        
        coord_text = coords_elem.text.strip()
        coords = []
        
        # Parse "lon,lat,alt lon,lat,alt ..." format
        for point in coord_text.split():
            point = point.strip()
            if not point:
                continue
            parts = point.split(',')
            if len(parts) >= 2:
                try:
                    lon = float(parts[0])
                    lat = float(parts[1])
                    coords.append((lat, lon))
                except ValueError:
                    continue
        
        return coords if coords else None
        
    except ET.ParseError as e:
        logger.error(f"XML parse error: {e}")
        return None
    except Exception as e:
        logger.error(f"Error parsing KML: {e}")
        return None


def parse_kml_name(kml_content: str) -> Optional[str]:
    """Extract polygon/placemark name from KML."""
    try:
        kml_content = re.sub(r'xmlns="[^"]+"', '', kml_content)
        root = ET.fromstring(kml_content)
        
        # Try various paths for name
        for path in ['.//Placemark/name', './/name', './/Document/name']:
            name_elem = root.find(path)
            if name_elem is not None and name_elem.text:
                return name_elem.text.strip()
        
        return None
    except Exception as e:
        logger.error(f"Error parsing name: {e}")
        return None


def check_red_styling(kml_content: str) -> bool:
    """Check if KML has red-ish styling for the polygon."""
    try:
        content_lower = kml_content.lower()
        
        # Check for PolyStyle or Style elements
        has_style = 'polystyle' in content_lower or 'style' in content_lower
        
        # KML colors are in AABBGGRR format (alpha, blue, green, red)
        # Red would have high red channel: ....ff or similar
        # Common red patterns in KML
        red_patterns = [
            'ff0000ff',  # opaque red (AABBGGRR)
            '7f0000ff',  # semi-transparent red
            '990000ff',
            'cc0000ff',
            'ff',        # ends in ff (red channel)
            'color>7f0000',
            'color>ff0000',
        ]
        
        has_red = any(p in content_lower for p in red_patterns)
        
        # Also check for color element with any value (agent tried to style)
        has_color_elem = '<color>' in content_lower or 'color>' in content_lower
        
        return has_style and (has_red or has_color_elem)
    except Exception:
        return False


def find_matching_vertices(actual_coords: List[Tuple[float, float]], 
                          expected_coords: List[Tuple[float, float]], 
                          tolerance: float) -> Dict[int, int]:
    """Find which expected coordinates match actual coordinates."""
    matches = {}
    
    # Remove closing vertex if present (polygon closes by repeating first vertex)
    actual = actual_coords.copy()
    if len(actual) > len(expected_coords):
        # Check if last point equals first (closing vertex)
        if actual and coord_matches(actual[0], actual[-1], tolerance):
            actual = actual[:-1]
    
    # Find best matches for each expected coordinate
    for exp_idx, exp_coord in enumerate(expected_coords):
        for act_idx, act_coord in enumerate(actual):
            if act_idx not in matches.values():  # Don't reuse actual coords
                if coord_matches(act_coord, exp_coord, tolerance):
                    matches[exp_idx] = act_idx
                    break
    
    return matches


# VLM Prompts
TRAJECTORY_VERIFICATION_PROMPT = """You are analyzing a sequence of screenshots from an agent creating a polygon in Google Earth Pro.

The task was to create a polygon named "TFR Zone Alpha" with specific coordinates in the Nevada desert.

Look at these screenshots (chronologically ordered) and assess:

1. GOOGLE_EARTH_VISIBLE: Is Google Earth Pro clearly visible and being used?
2. POLYGON_CREATION_WORKFLOW: Do the frames show the polygon creation process? Look for:
   - Add Polygon dialog or menu being accessed
   - Polygon vertices being placed on the map
   - Polygon properties being configured (name, style)
   - A polygon shape appearing on the map
3. NEVADA_LOCATION: Does the map show desert/Nevada terrain (tan/brown desert landscape)?
4. RED_POLYGON_VISIBLE: Is a red or reddish polygon visible on the map at any point?
5. SAVE_EXPORT_ACTION: Is there evidence of saving or exporting (Save dialog, file browser)?

Respond in JSON format:
{
    "google_earth_visible": true/false,
    "polygon_creation_workflow": true/false,
    "nevada_location": true/false,
    "red_polygon_visible": true/false,
    "save_export_action": true/false,
    "workflow_stages_observed": ["list what you see"],
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of the progression"
}
"""

FINAL_STATE_PROMPT = """You are verifying the final state of a Google Earth Pro polygon creation task.

The task was to create a polygon named "TFR Zone Alpha" with four vertices forming a rectangle in the Nevada desert, styled with red fill.

Look at this final screenshot and assess:

1. IS_GOOGLE_EARTH: Is this Google Earth Pro (satellite imagery interface)?
2. POLYGON_VISIBLE: Is there a polygon shape visible on the map?
3. POLYGON_RED: Does the polygon appear to be red or reddish colored?
4. DESERT_TERRAIN: Does the background show desert/arid terrain (Nevada area)?
5. POLYGON_RECTANGULAR: Does the visible polygon have roughly 4 sides (rectangular shape)?
6. MY_PLACES_ENTRY: Is there an entry in the Places panel that might be the polygon?

Respond in JSON format:
{
    "is_google_earth": true/false,
    "polygon_visible": true/false,
    "polygon_red": true/false,
    "desert_terrain": true/false,
    "polygon_rectangular": true/false,
    "my_places_entry_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "what you see in the screenshot"
}
"""


def verify_coordinate_polygon_entry(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that the agent created a polygon with correct coordinates.
    
    Multi-signal verification:
    1. KML file exists and contains polygon (programmatic)
    2. Coordinates match expected values (programmatic)
    3. Trajectory shows polygon creation workflow (VLM)
    4. Final state shows polygon on map (VLM)
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
    expected_output = metadata.get('expected_output_path', '/home/ga/Documents/tfr_zone_alpha.kml')
    tolerance = metadata.get('tolerance_degrees', TOLERANCE)
    
    feedback_parts = []
    details = {}
    score = 0
    
    # ================================================================
    # STEP 1: Copy and parse task result JSON
    # ================================================================
    result_data = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
        details['result_data'] = result_data
    except Exception as e:
        logger.warning(f"Could not read task result: {e}")
        details['result_error'] = str(e)
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # CRITERION 1: KML file exists (10 points)
    # ================================================================
    kml_content = None
    temp_kml = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
    try:
        # Try the exported KML first
        copy_from_env("/tmp/tfr_zone_alpha.kml", temp_kml.name)
        with open(temp_kml.name, 'r', encoding='utf-8', errors='ignore') as f:
            kml_content = f.read()
        
        if kml_content and len(kml_content) > 50:
            score += 10
            feedback_parts.append("✅ KML file exists")
            details['kml_exists'] = True
            details['kml_size'] = len(kml_content)
        else:
            feedback_parts.append("❌ KML file empty or too small")
            details['kml_exists'] = False
    except Exception as e:
        logger.warning(f"Could not read KML file: {e}")
        feedback_parts.append("❌ KML file not found")
        details['kml_exists'] = False
        details['kml_error'] = str(e)
    finally:
        if os.path.exists(temp_kml.name):
            os.unlink(temp_kml.name)
    
    # If no KML, try myplaces.kml as fallback
    if not kml_content:
        temp_myplaces = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
        try:
            copy_from_env("/tmp/myplaces.kml", temp_myplaces.name)
            with open(temp_myplaces.name, 'r', encoding='utf-8', errors='ignore') as f:
                myplaces_content = f.read()
            if 'TFR Zone Alpha' in myplaces_content or 'tfr zone alpha' in myplaces_content.lower():
                kml_content = myplaces_content
                feedback_parts.append("⚠️ Found polygon in My Places (not exported)")
                details['found_in_myplaces'] = True
        except Exception:
            pass
        finally:
            if os.path.exists(temp_myplaces.name):
                os.unlink(temp_myplaces.name)
    
    # ================================================================
    # CRITERION 2: File created during task - anti-gaming (10 points)
    # ================================================================
    file_created_during_task = result_data.get('output_file', {}).get('created_during_task', False)
    if file_created_during_task:
        score += 10
        feedback_parts.append("✅ File created during task")
        details['created_during_task'] = True
    else:
        feedback_parts.append("⚠️ File timestamp issue (may predate task)")
        details['created_during_task'] = False
    
    # ================================================================
    # CRITERION 3: Valid KML structure with polygon (10 points)
    # ================================================================
    coords = None
    if kml_content:
        coords = parse_kml_coordinates(kml_content)
        if coords and len(coords) >= 4:
            score += 10
            feedback_parts.append(f"✅ Valid polygon with {len(coords)} vertices")
            details['valid_polygon'] = True
            details['vertex_count'] = len(coords)
        elif coords:
            score += 5
            feedback_parts.append(f"⚠️ Polygon has only {len(coords)} vertices (expected 4)")
            details['valid_polygon'] = False
        else:
            feedback_parts.append("❌ Could not parse polygon coordinates")
            details['valid_polygon'] = False
    else:
        details['valid_polygon'] = False
    
    # ================================================================
    # CRITERION 4: Polygon name correct (10 points)
    # ================================================================
    if kml_content:
        name = parse_kml_name(kml_content)
        details['found_name'] = name
        
        if name and EXPECTED_NAME.lower() in name.lower():
            score += 10
            feedback_parts.append(f"✅ Polygon name correct: '{name}'")
            details['name_correct'] = True
        elif name:
            score += 3
            feedback_parts.append(f"⚠️ Polygon name differs: '{name}' (expected '{EXPECTED_NAME}')")
            details['name_correct'] = False
        else:
            feedback_parts.append("❌ Could not find polygon name")
            details['name_correct'] = False
    
    # ================================================================
    # CRITERIA 5-8: Individual vertex coordinates (12 points each = 48 total)
    # ================================================================
    vertices_correct = 0
    vertex_labels = ["A (NW)", "B (NE)", "C (SE)", "D (SW)"]
    
    if coords:
        matches = find_matching_vertices(coords, EXPECTED_COORDS, tolerance)
        details['coordinate_matches'] = {}
        
        for i, (label, expected) in enumerate(zip(vertex_labels, EXPECTED_COORDS)):
            if i in matches:
                actual_idx = matches[i]
                actual = coords[actual_idx]
                score += 12
                vertices_correct += 1
                feedback_parts.append(f"✅ Vertex {label}: matched at ({actual[0]:.4f}, {actual[1]:.4f})")
                details['coordinate_matches'][label] = {
                    'matched': True,
                    'expected': expected,
                    'actual': actual
                }
            else:
                feedback_parts.append(f"❌ Vertex {label}: no match found (expected {expected})")
                details['coordinate_matches'][label] = {
                    'matched': False,
                    'expected': expected
                }
        
        details['vertices_correct'] = vertices_correct
    else:
        details['vertices_correct'] = 0
        for label, expected in zip(vertex_labels, EXPECTED_COORDS):
            feedback_parts.append(f"❌ Vertex {label}: cannot verify (no coordinates)")
    
    # ================================================================
    # CRITERION 9: Styling (red color) (5 points)
    # ================================================================
    if kml_content:
        has_styling = check_red_styling(kml_content)
        if has_styling:
            score += 5
            feedback_parts.append("✅ Red styling detected")
            details['styling_correct'] = True
        else:
            feedback_parts.append("⚠️ Red styling not detected in KML")
            details['styling_correct'] = False
    
    # ================================================================
    # CRITERION 10: VLM Trajectory Verification (7 points)
    # ================================================================
    vlm_trajectory_score = 0
    if query_vlm:
        try:
            # Get trajectory frames
            frames = traj.get('frames', [])
            
            # Sample frames across the trajectory
            if len(frames) >= 5:
                indices = [0, len(frames)//4, len(frames)//2, 3*len(frames)//4, -1]
                sampled_frames = [frames[i] for i in indices if abs(i) < len(frames)]
            else:
                sampled_frames = frames
            
            if sampled_frames:
                vlm_result = query_vlm(
                    prompt=TRAJECTORY_VERIFICATION_PROMPT,
                    images=sampled_frames
                )
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    details['vlm_trajectory'] = parsed
                    
                    # Score based on VLM observations
                    traj_criteria = [
                        parsed.get('google_earth_visible', False),
                        parsed.get('polygon_creation_workflow', False),
                        parsed.get('nevada_location', False),
                        parsed.get('red_polygon_visible', False),
                    ]
                    
                    traj_score = sum(traj_criteria)
                    if traj_score >= 3:
                        vlm_trajectory_score = 7
                        feedback_parts.append("✅ VLM: Trajectory shows polygon creation workflow")
                    elif traj_score >= 2:
                        vlm_trajectory_score = 4
                        feedback_parts.append("⚠️ VLM: Partial workflow evidence in trajectory")
                    else:
                        feedback_parts.append("❌ VLM: Trajectory doesn't show clear workflow")
                else:
                    feedback_parts.append("⚠️ VLM trajectory query failed")
        except Exception as e:
            logger.warning(f"VLM trajectory verification failed: {e}")
            feedback_parts.append("⚠️ VLM trajectory verification error")
    
    score += vlm_trajectory_score
    
    # ================================================================
    # Determine pass/fail
    # ================================================================
    # Pass requires: file exists AND at least 3 vertices correct
    key_criteria_met = details.get('kml_exists', False) and vertices_correct >= 3
    passed = score >= 60 and key_criteria_met
    
    # Summary
    feedback_parts.insert(0, f"Score: {score}/100 | Vertices correct: {vertices_correct}/4")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts[:10]),  # Limit feedback length
        "details": details
    }


if __name__ == "__main__":
    # Test mode
    print("Verifier module loaded successfully")
    print(f"Expected coordinates: {EXPECTED_COORDS}")
    print(f"Tolerance: {TOLERANCE} degrees")