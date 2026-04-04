#!/usr/bin/env python3
"""
Verifier for 3D Building Extrusion task (building_extrusion_polygon@1).

VERIFICATION STRATEGY:
1. KML file exists and was created during task (15 points)
2. KML has valid polygon structure (10 points)
3. KML has extrusion enabled (15 points)
4. KML has correct altitude mode (15 points)
5. Location is correct (within tolerance of Chicago target) (15 points)
6. Polygon name is correct (5 points)
7. Screenshot exists and was created during task (10 points)
8. VLM: Trajectory shows polygon creation workflow (15 points)

Pass threshold: 60 points with key criteria (KML created + extrusion enabled)
"""

import json
import tempfile
import os
import re
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_kml_coordinates(coord_string):
    """Parse KML coordinate string and return list of (lat, lon, alt) tuples."""
    coordinates = []
    if not coord_string:
        return coordinates
    
    # KML format: lon,lat,alt lon,lat,alt ...
    coord_string = coord_string.strip()
    for coord in coord_string.split():
        parts = coord.split(',')
        if len(parts) >= 2:
            try:
                lon = float(parts[0])
                lat = float(parts[1])
                alt = float(parts[2]) if len(parts) > 2 else 0
                coordinates.append((lat, lon, alt))
            except (ValueError, IndexError):
                continue
    return coordinates


def parse_kml_file(kml_content):
    """Parse KML file content and extract relevant data."""
    result = {
        "valid": False,
        "has_polygon": False,
        "has_extrude": False,
        "extrude_value": None,
        "altitude_mode": None,
        "polygon_name": None,
        "coordinates": [],
        "error": None
    }
    
    try:
        # Handle KML namespace
        # Remove default namespace for easier parsing
        kml_content = re.sub(r'\sxmlns="[^"]+"', '', kml_content, count=1)
        
        root = ET.fromstring(kml_content)
        result["valid"] = True
        
        # Find Polygon element
        polygon = root.find('.//Polygon')
        if polygon is not None:
            result["has_polygon"] = True
        
        # Find extrude element
        extrude = root.find('.//extrude')
        if extrude is not None and extrude.text:
            result["extrude_value"] = extrude.text.strip()
            result["has_extrude"] = result["extrude_value"] == "1"
        
        # Find altitude mode
        alt_mode = root.find('.//altitudeMode')
        if alt_mode is not None and alt_mode.text:
            result["altitude_mode"] = alt_mode.text.strip()
        
        # Find Placemark name
        placemark = root.find('.//Placemark')
        if placemark is not None:
            name_elem = placemark.find('name')
            if name_elem is not None and name_elem.text:
                result["polygon_name"] = name_elem.text.strip()
        
        # Find coordinates
        coords_elem = root.find('.//coordinates')
        if coords_elem is not None and coords_elem.text:
            result["coordinates"] = parse_kml_coordinates(coords_elem.text)
        
    except ET.ParseError as e:
        result["error"] = f"XML parse error: {e}"
    except Exception as e:
        result["error"] = f"Parse error: {e}"
    
    return result


def check_location(coordinates, target_lat, target_lon, tolerance):
    """Check if polygon coordinates are near target location."""
    if not coordinates:
        return False, 0, 0
    
    # Calculate centroid of polygon
    avg_lat = sum(c[0] for c in coordinates) / len(coordinates)
    avg_lon = sum(c[1] for c in coordinates) / len(coordinates)
    
    lat_diff = abs(avg_lat - target_lat)
    lon_diff = abs(avg_lon - target_lon)
    
    is_correct = lat_diff <= tolerance and lon_diff <= tolerance
    return is_correct, avg_lat, avg_lon


def check_altitude(coordinates, target_alt, tolerance):
    """Check if polygon has correct altitude."""
    if not coordinates:
        return False, 0
    
    # Get max altitude from coordinates
    altitudes = [c[2] for c in coordinates if len(c) > 2 and c[2] > 0]
    if not altitudes:
        return False, 0
    
    max_alt = max(altitudes)
    is_correct = abs(max_alt - target_alt) <= tolerance
    return is_correct, max_alt


def verify_building_extrusion(traj, env_info, task_info):
    """
    Verify that a 3D extruded polygon was created correctly.
    
    Uses multiple independent signals for robust verification.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Get metadata with defaults
    metadata = task_info.get('metadata', {})
    target_lat = metadata.get('target_latitude', 41.8839)
    target_lon = metadata.get('target_longitude', -87.6416)
    target_height = metadata.get('target_height_meters', 75)
    height_tolerance = metadata.get('height_tolerance_meters', 5)
    coord_tolerance = metadata.get('coordinate_tolerance_degrees', 0.01)
    expected_name = metadata.get('expected_polygon_name', 'Proposed Office Tower')
    min_kml_size = metadata.get('min_kml_size_bytes', 500)
    min_screenshot_size = metadata.get('min_screenshot_size_bytes', 10000)
    
    feedback_parts = []
    score = 0
    details = {}
    
    # ================================================================
    # Copy result JSON from container
    # ================================================================
    result = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        details['export_result'] = result
    except Exception as e:
        logger.warning(f"Could not read task result: {e}")
        details['export_error'] = str(e)
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # Copy and parse KML file
    # ================================================================
    kml_data = {"valid": False}
    kml_content = ""
    
    temp_kml = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
    try:
        copy_from_env("/tmp/exported_building.kml", temp_kml.name)
        with open(temp_kml.name, 'r') as f:
            kml_content = f.read()
        kml_data = parse_kml_file(kml_content)
        details['kml_parsed'] = kml_data
    except Exception as e:
        logger.warning(f"Could not read KML file: {e}")
        details['kml_error'] = str(e)
    finally:
        if os.path.exists(temp_kml.name):
            os.unlink(temp_kml.name)
    
    # ================================================================
    # CRITERION 1: KML file exists and was created during task (15 pts)
    # ================================================================
    kml_info = result.get('kml', {})
    kml_exists = kml_info.get('exists', False)
    kml_created = kml_info.get('created_during_task', False)
    kml_size = kml_info.get('size_bytes', 0)
    
    if kml_exists and kml_created and kml_size >= min_kml_size:
        score += 15
        feedback_parts.append(f"✅ KML file created ({kml_size} bytes)")
    elif kml_exists and kml_size >= min_kml_size:
        score += 8
        feedback_parts.append(f"⚠️ KML exists but timestamp suspicious ({kml_size} bytes)")
    elif kml_exists:
        score += 5
        feedback_parts.append(f"⚠️ KML exists but small ({kml_size} bytes)")
    else:
        feedback_parts.append("❌ KML file not found")
        # Early exit with partial score
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: KML has valid polygon structure (10 pts)
    # ================================================================
    if kml_data.get('valid') and kml_data.get('has_polygon'):
        score += 10
        feedback_parts.append("✅ Valid polygon in KML")
    elif kml_data.get('valid'):
        score += 5
        feedback_parts.append("⚠️ Valid KML but no polygon element")
    else:
        feedback_parts.append(f"❌ Invalid KML: {kml_data.get('error', 'unknown error')}")
    
    # ================================================================
    # CRITERION 3: KML has extrusion enabled (15 pts)
    # ================================================================
    if kml_data.get('has_extrude'):
        score += 15
        feedback_parts.append("✅ Extrusion enabled (extrude=1)")
    else:
        feedback_parts.append(f"❌ Extrusion not enabled (value={kml_data.get('extrude_value')})")
    
    # ================================================================
    # CRITERION 4: KML has correct altitude mode (15 pts)
    # ================================================================
    alt_mode = kml_data.get('altitude_mode', '')
    if alt_mode and 'relativetoground' in alt_mode.lower():
        score += 15
        feedback_parts.append("✅ Altitude mode: relativeToGround")
    elif alt_mode:
        score += 5
        feedback_parts.append(f"⚠️ Altitude mode: {alt_mode} (expected relativeToGround)")
    else:
        feedback_parts.append("❌ No altitude mode specified")
    
    # ================================================================
    # CRITERION 5: Location is correct (15 pts)
    # ================================================================
    coordinates = kml_data.get('coordinates', [])
    loc_correct, avg_lat, avg_lon = check_location(coordinates, target_lat, target_lon, coord_tolerance)
    
    if loc_correct:
        score += 15
        feedback_parts.append(f"✅ Location correct ({avg_lat:.4f}, {avg_lon:.4f})")
    elif coordinates:
        # Check with larger tolerance
        loc_approx, _, _ = check_location(coordinates, target_lat, target_lon, coord_tolerance * 3)
        if loc_approx:
            score += 8
            feedback_parts.append(f"⚠️ Location approximately correct ({avg_lat:.4f}, {avg_lon:.4f})")
        else:
            feedback_parts.append(f"❌ Location incorrect ({avg_lat:.4f}, {avg_lon:.4f})")
    else:
        feedback_parts.append("❌ No coordinates found in KML")
    
    # ================================================================
    # CRITERION 6: Polygon name is correct (5 pts)
    # ================================================================
    polygon_name = kml_data.get('polygon_name', '')
    name_lower = polygon_name.lower() if polygon_name else ''
    expected_lower = expected_name.lower()
    
    # Check if key words are present
    has_proposed = 'proposed' in name_lower
    has_tower = 'tower' in name_lower or 'building' in name_lower or 'office' in name_lower
    
    if polygon_name and (has_proposed and has_tower):
        score += 5
        feedback_parts.append(f"✅ Polygon named: '{polygon_name}'")
    elif polygon_name:
        score += 2
        feedback_parts.append(f"⚠️ Polygon named: '{polygon_name}' (expected similar to '{expected_name}')")
    else:
        feedback_parts.append("❌ Polygon name not found")
    
    # ================================================================
    # CRITERION 7: Screenshot exists and was created during task (10 pts)
    # ================================================================
    screenshot_info = result.get('screenshot', {})
    screenshot_exists = screenshot_info.get('exists', False)
    screenshot_created = screenshot_info.get('created_during_task', False)
    screenshot_size = screenshot_info.get('size_bytes', 0)
    
    if screenshot_exists and screenshot_created and screenshot_size >= min_screenshot_size:
        score += 10
        feedback_parts.append(f"✅ Screenshot saved ({screenshot_size} bytes)")
    elif screenshot_exists and screenshot_size >= min_screenshot_size:
        score += 5
        feedback_parts.append(f"⚠️ Screenshot exists but timestamp suspicious")
    elif screenshot_exists:
        score += 3
        feedback_parts.append(f"⚠️ Screenshot exists but small ({screenshot_size} bytes)")
    else:
        feedback_parts.append("❌ Screenshot not found")
    
    # ================================================================
    # CRITERION 8: VLM trajectory verification (15 pts)
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    vlm_score = 0
    
    if query_vlm:
        try:
            # Import trajectory frame utilities
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Sample trajectory frames for process verification
            traj_frames = sample_trajectory_frames(traj, n=5)
            final_frame = get_final_screenshot(traj)
            
            if traj_frames or final_frame:
                all_frames = (traj_frames or []) + ([final_frame] if final_frame else [])
                
                vlm_prompt = """You are verifying if an agent created a 3D extruded polygon in Google Earth Pro.

The task was to:
1. Navigate to Chicago (41.8839°N, 87.6416°W)
2. Create a polygon and configure it as a 3D building (75m tall)
3. Save the polygon as KML and take a screenshot

Analyze these trajectory screenshots and determine:
1. Is Google Earth Pro visible?
2. Is there evidence of polygon creation (Add Polygon dialog, drawing on map)?
3. Is there a 3D extruded shape visible (a box/building shape)?
4. Does any frame show Chicago/urban area?
5. Is there evidence of saving files (Save dialog, file browser)?

Respond in JSON:
{
    "google_earth_visible": true/false,
    "polygon_creation_evidence": true/false,
    "extruded_shape_visible": true/false,
    "chicago_area_visible": true/false,
    "file_save_evidence": true/false,
    "workflow_progression": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}"""
                
                vlm_result = query_vlm(prompt=vlm_prompt, images=all_frames)
                details['vlm_result'] = vlm_result
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    
                    vlm_criteria = 0
                    if parsed.get('google_earth_visible'):
                        vlm_criteria += 1
                    if parsed.get('polygon_creation_evidence'):
                        vlm_criteria += 1
                    if parsed.get('extruded_shape_visible'):
                        vlm_criteria += 2
                    if parsed.get('chicago_area_visible'):
                        vlm_criteria += 1
                    if parsed.get('workflow_progression'):
                        vlm_criteria += 1
                    
                    confidence = parsed.get('confidence', 'low')
                    confidence_mult = {'high': 1.0, 'medium': 0.85, 'low': 0.7}.get(confidence, 0.7)
                    
                    vlm_score = int((vlm_criteria / 6) * 15 * confidence_mult)
                    score += vlm_score
                    
                    if vlm_score >= 10:
                        feedback_parts.append(f"✅ VLM: Workflow verified ({vlm_score}/15)")
                    elif vlm_score >= 5:
                        feedback_parts.append(f"⚠️ VLM: Partial workflow evidence ({vlm_score}/15)")
                    else:
                        feedback_parts.append(f"❌ VLM: Insufficient evidence ({vlm_score}/15)")
                else:
                    feedback_parts.append(f"⚠️ VLM query failed: {vlm_result.get('error', 'unknown')}")
            else:
                feedback_parts.append("⚠️ No trajectory frames available for VLM")
        except ImportError:
            logger.warning("VLM utilities not available")
            feedback_parts.append("⚠️ VLM verification skipped (not available)")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            feedback_parts.append(f"⚠️ VLM error: {str(e)[:50]}")
    else:
        feedback_parts.append("⚠️ VLM not available for trajectory verification")
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    details['score_breakdown'] = {
        'kml_exists': 15 if (kml_exists and kml_created) else 0,
        'polygon_valid': 10 if kml_data.get('has_polygon') else 0,
        'extrusion_enabled': 15 if kml_data.get('has_extrude') else 0,
        'altitude_mode': 15 if alt_mode and 'relativetoground' in alt_mode.lower() else 0,
        'location_correct': 15 if loc_correct else 0,
        'name_correct': 5 if (has_proposed and has_tower) else 0,
        'screenshot': 10 if (screenshot_exists and screenshot_created) else 0,
        'vlm_verification': vlm_score
    }
    
    # Key criteria: KML created with extrusion
    key_criteria_met = (
        kml_exists and 
        kml_data.get('has_polygon', False) and 
        kml_data.get('has_extrude', False)
    )
    
    passed = score >= 60 and key_criteria_met
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "details": details
    }