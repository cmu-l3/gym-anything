#!/usr/bin/env python3
"""
Verifier for Wildlife Corridor River Crossing Documentation task.

ROBUST MULTI-SIGNAL VERIFICATION:
1. KML file exists and is valid XML (10 points)
2. KML was created during task (15 points) - anti-gaming
3. Coordinates in valid Mara River region (20 points)
4. Placemark properly named (10 points)
5. River width documented in description (15 points)
6. Width in valid range 25-75m (10 points)
7. Screenshot exists with content (10 points)
8. VLM trajectory: Shows navigation to Africa/river area (10 points)

Pass threshold: 60 points AND coordinates in valid region AND file created during task
"""

import json
import tempfile
import os
import re
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Valid Mara River region bounds
VALID_LAT_RANGE = (-1.55, -1.42)
VALID_LON_RANGE = (34.95, 35.12)

# Expected river width range in meters
VALID_WIDTH_RANGE = (25, 75)


def parse_kml_coordinates(kml_content):
    """Parse coordinates from KML content string."""
    try:
        root = ET.fromstring(kml_content)
        
        # Handle KML namespace
        ns = {'kml': 'http://www.opengis.net/kml/2.2'}
        
        # Try with namespace
        coords = root.find('.//kml:coordinates', ns)
        if coords is None:
            # Try without namespace
            coords = root.find('.//coordinates')
        
        if coords is not None and coords.text:
            coord_text = coords.text.strip()
            parts = coord_text.split(',')
            if len(parts) >= 2:
                lon = float(parts[0].strip())
                lat = float(parts[1].strip())
                return lat, lon
        
        # Try iterating through all elements
        for elem in root.iter():
            if 'coordinates' in elem.tag.lower() and elem.text:
                coord_text = elem.text.strip()
                parts = coord_text.split(',')
                if len(parts) >= 2:
                    lon = float(parts[0].strip())
                    lat = float(parts[1].strip())
                    return lat, lon
        
        return None, None
    except Exception as e:
        logger.error(f"Error parsing KML coordinates: {e}")
        return None, None


def extract_width_from_description(description):
    """Extract river width measurement from description text."""
    if not description:
        return None
    
    # Look for patterns like "30 meters", "45m", "width: 35", "River width: 42 meters"
    patterns = [
        r'(\d+(?:\.\d+)?)\s*(?:m|meters?|metre?s?)',
        r'width[:\s]+(\d+(?:\.\d+)?)',
        r'(\d+(?:\.\d+)?)\s*(?:m|meters?)\s*wide',
        r'width\s*[:\-=]\s*(\d+(?:\.\d+)?)',
    ]
    
    for pattern in patterns:
        match = re.search(pattern, description, re.IGNORECASE)
        if match:
            try:
                return float(match.group(1))
            except:
                pass
    
    # Also try to find any standalone number that could be a width
    numbers = re.findall(r'\b(\d+(?:\.\d+)?)\b', description)
    for num_str in numbers:
        try:
            num = float(num_str)
            if VALID_WIDTH_RANGE[0] <= num <= VALID_WIDTH_RANGE[1]:
                return num
        except:
            pass
    
    return None


def verify_wildlife_corridor_crossing(traj, env_info, task_info):
    """
    Verify that the wildlife corridor crossing was properly documented.
    
    Uses MULTIPLE INDEPENDENT SIGNALS to prevent gaming:
    1. File existence and timestamps
    2. KML content parsing and validation
    3. Coordinate verification
    4. VLM trajectory analysis
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    expected_kml_path = metadata.get('expected_kml_path', '/home/ga/Documents/mara_crossing.kml')
    expected_png_path = metadata.get('expected_screenshot_path', '/home/ga/Documents/mara_crossing_view.png')
    
    feedback_parts = []
    score = 0
    max_score = 100
    result_details = {}
    
    # ================================================================
    # Copy result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read task result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    result_details['task_result'] = result
    kml_data = result.get('kml', {})
    png_data = result.get('screenshot', {})
    
    # ================================================================
    # CRITERION 1: KML file exists and is valid (10 points)
    # ================================================================
    kml_exists = kml_data.get('exists', False)
    kml_size = kml_data.get('size_bytes', 0)
    
    if kml_exists and kml_size > 100:
        score += 10
        feedback_parts.append("✅ KML file exists")
        result_details['kml_exists'] = True
    elif kml_exists:
        score += 5
        feedback_parts.append("⚠️ KML file exists but very small")
        result_details['kml_exists'] = True
    else:
        feedback_parts.append("❌ KML file NOT found")
        result_details['kml_exists'] = False
        # Cannot continue without KML file
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": result_details
        }
    
    # ================================================================
    # CRITERION 2: KML created during task (15 points) - ANTI-GAMING
    # ================================================================
    kml_created_during_task = kml_data.get('created_during_task', False)
    
    if kml_created_during_task:
        score += 15
        feedback_parts.append("✅ KML created during task")
        result_details['kml_created_during_task'] = True
    else:
        feedback_parts.append("❌ KML NOT created during task (possible gaming)")
        result_details['kml_created_during_task'] = False
    
    # ================================================================
    # CRITERION 3: Coordinates in valid Mara River region (20 points)
    # ================================================================
    lat = None
    lon = None
    coordinates_str = kml_data.get('coordinates', '')
    
    # Try to parse coordinates from the exported string
    if coordinates_str:
        try:
            parts = coordinates_str.strip().split(',')
            if len(parts) >= 2:
                lon = float(parts[0].strip())
                lat = float(parts[1].strip())
        except:
            pass
    
    # If that failed, try to copy and parse the actual KML file
    if lat is None or lon is None:
        temp_kml = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
        try:
            copy_from_env(expected_kml_path, temp_kml.name)
            with open(temp_kml.name, 'r') as f:
                kml_content = f.read()
            lat, lon = parse_kml_coordinates(kml_content)
        except Exception as e:
            logger.warning(f"Could not parse KML file: {e}")
        finally:
            if os.path.exists(temp_kml.name):
                os.unlink(temp_kml.name)
    
    result_details['latitude'] = lat
    result_details['longitude'] = lon
    
    coordinates_valid = False
    if lat is not None and lon is not None:
        lat_valid = VALID_LAT_RANGE[0] <= lat <= VALID_LAT_RANGE[1]
        lon_valid = VALID_LON_RANGE[0] <= lon <= VALID_LON_RANGE[1]
        coordinates_valid = lat_valid and lon_valid
        
        if coordinates_valid:
            score += 20
            feedback_parts.append(f"✅ Coordinates in Mara region ({lat:.4f}, {lon:.4f})")
        else:
            feedback_parts.append(f"❌ Coordinates NOT in Mara region ({lat:.4f}, {lon:.4f})")
    else:
        feedback_parts.append("❌ Could not parse coordinates from KML")
    
    result_details['coordinates_valid'] = coordinates_valid
    
    # ================================================================
    # CRITERION 4: Placemark properly named (10 points)
    # ================================================================
    kml_name = kml_data.get('name', '').lower()
    expected_name = metadata.get('expected_placemark_name', 'Mara River Crossing Point').lower()
    
    name_valid = False
    if 'mara' in kml_name and 'cross' in kml_name:
        score += 10
        feedback_parts.append("✅ Placemark named correctly")
        name_valid = True
    elif 'mara' in kml_name or 'cross' in kml_name or 'river' in kml_name:
        score += 5
        feedback_parts.append("⚠️ Placemark name partially correct")
        name_valid = True
    else:
        feedback_parts.append(f"❌ Placemark name incorrect: '{kml_data.get('name', 'N/A')}'")
    
    result_details['name_valid'] = name_valid
    
    # ================================================================
    # CRITERION 5: River width documented in description (15 points)
    # ================================================================
    description = kml_data.get('description', '')
    width = extract_width_from_description(description)
    
    result_details['width_value'] = width
    result_details['description'] = description
    
    width_documented = False
    if width is not None:
        score += 15
        feedback_parts.append(f"✅ Width documented: {width}m")
        width_documented = True
    else:
        feedback_parts.append("❌ River width NOT documented in description")
    
    # ================================================================
    # CRITERION 6: Width in valid range 25-75m (10 points)
    # ================================================================
    width_valid = False
    if width is not None:
        if VALID_WIDTH_RANGE[0] <= width <= VALID_WIDTH_RANGE[1]:
            score += 10
            feedback_parts.append(f"✅ Width in valid range ({VALID_WIDTH_RANGE[0]}-{VALID_WIDTH_RANGE[1]}m)")
            width_valid = True
        else:
            feedback_parts.append(f"⚠️ Width outside expected range: {width}m")
    
    result_details['width_valid'] = width_valid
    
    # ================================================================
    # CRITERION 7: Screenshot exists with content (10 points)
    # ================================================================
    png_exists = png_data.get('exists', False)
    png_size = png_data.get('size_bytes', 0)
    png_created_during_task = png_data.get('created_during_task', False)
    
    if png_exists and png_size > 50000 and png_created_during_task:
        score += 10
        feedback_parts.append(f"✅ Screenshot saved ({png_size/1024:.1f}KB)")
    elif png_exists and png_size > 10000:
        score += 5
        feedback_parts.append(f"⚠️ Screenshot exists but small or pre-existing ({png_size/1024:.1f}KB)")
    else:
        feedback_parts.append("❌ Screenshot NOT found or too small")
    
    result_details['screenshot_valid'] = png_exists and png_size > 50000
    
    # ================================================================
    # CRITERION 8: VLM trajectory verification (10 points)
    # ================================================================
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm and traj:
        try:
            # Import trajectory sampling utility
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Sample frames from trajectory
            frames = sample_trajectory_frames(traj, n=5)
            final_frame = get_final_screenshot(traj)
            
            if frames or final_frame:
                all_frames = (frames or []) + ([final_frame] if final_frame else [])
                
                vlm_prompt = """You are verifying a Google Earth navigation task.

The agent was asked to:
1. Navigate to the Mara River in Kenya/Tanzania (East Africa)
2. Find a river crossing point
3. Create a placemark and measure the river

Analyze these trajectory screenshots and determine:
1. Did the agent navigate to Africa/East Africa? (Look for African terrain, savanna, the Mara River region)
2. Is a river visible in any frame? (Look for water body in satellite imagery)
3. Is there evidence of measurement or placemark creation? (Ruler tool, placemark dialog)
4. Does the final view show the Mara River area?

Respond in JSON format:
{
    "navigated_to_africa": true/false,
    "river_visible": true/false,
    "measurement_or_placemark_activity": true/false,
    "final_view_shows_river_area": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}"""
                
                vlm_result = query_vlm(prompt=vlm_prompt, images=all_frames)
                
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    result_details['vlm_result'] = parsed
                    
                    vlm_criteria = 0
                    if parsed.get("navigated_to_africa"):
                        vlm_criteria += 1
                    if parsed.get("river_visible"):
                        vlm_criteria += 1
                    if parsed.get("measurement_or_placemark_activity"):
                        vlm_criteria += 1
                    if parsed.get("final_view_shows_river_area"):
                        vlm_criteria += 1
                    
                    # Scale to 10 points max
                    vlm_score = int((vlm_criteria / 4) * 10)
                    
                    confidence = parsed.get("confidence", "low")
                    if confidence == "low":
                        vlm_score = int(vlm_score * 0.7)
                    elif confidence == "medium":
                        vlm_score = int(vlm_score * 0.85)
                    
                    if vlm_score > 0:
                        feedback_parts.append(f"✅ VLM trajectory verification: {vlm_score}/10 points")
                    else:
                        feedback_parts.append("⚠️ VLM could not verify workflow")
                else:
                    feedback_parts.append("⚠️ VLM verification unavailable")
            else:
                feedback_parts.append("⚠️ No trajectory frames available")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback_parts.append(f"⚠️ VLM verification error")
    else:
        feedback_parts.append("⚠️ VLM not available for trajectory verification")
    
    score += vlm_score
    result_details['vlm_score'] = vlm_score
    
    # ================================================================
    # Calculate final result
    # ================================================================
    # Pass requires: score >= 60 AND coordinates valid AND file created during task
    key_criteria_met = coordinates_valid and kml_created_during_task
    passed = score >= 60 and key_criteria_met
    
    # Add summary
    feedback_parts.append(f"\nTotal Score: {score}/{max_score}")
    feedback_parts.append(f"Key criteria (coords valid + created during task): {'MET' if key_criteria_met else 'NOT MET'}")
    feedback_parts.append(f"Result: {'PASS' if passed else 'FAIL'}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result_details
    }