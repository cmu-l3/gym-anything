#!/usr/bin/env python3
"""
Verifier for camera_viewpoint_save task.

VERIFICATION STRATEGY:
1. Parse myplaces.kml for placemark with 'Horseshoe' in name (15 pts)
2. Verify coordinates are near Horseshoe Bend (20 pts)
3. Verify camera heading is 160-200 degrees (20 pts)
4. Verify camera tilt is 60-80 degrees (20 pts)
5. Verify camera range is 800-2000 meters (15 pts)
6. Verify file was modified during task - anti-gaming (10 pts)

Secondary: VLM trajectory verification to confirm workflow

Pass threshold: 70 points with coordinates correct and at least 2/3 camera params correct
"""

import json
import tempfile
import os
import re
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_myplaces_kml(kml_content):
    """
    Parse myplaces.kml content and extract placemarks with LookAt/Camera data.
    
    Returns list of placemark dicts with name and camera parameters.
    """
    placemarks = []
    
    try:
        # Try parsing as XML
        root = ET.fromstring(kml_content)
        
        # Define namespaces (Google Earth uses KML namespace)
        namespaces = {
            'kml': 'http://www.opengis.net/kml/2.2',
            'gx': 'http://www.google.com/kml/ext/2.2'
        }
        
        # Try both with and without namespace
        for ns_prefix in ['kml:', '']:
            # Find all Placemark elements
            if ns_prefix:
                placemark_elements = root.findall(f'.//{ns_prefix}Placemark', namespaces)
            else:
                placemark_elements = root.findall('.//Placemark')
            
            for pm in placemark_elements:
                placemark_data = extract_placemark_data(pm, ns_prefix, namespaces)
                if placemark_data and placemark_data.get('name'):
                    placemarks.append(placemark_data)
        
    except ET.ParseError as e:
        logger.warning(f"XML parse error: {e}")
        # Fallback: regex-based parsing
        placemarks = parse_kml_with_regex(kml_content)
    
    return placemarks


def extract_placemark_data(pm_element, ns_prefix, namespaces):
    """Extract placemark name and LookAt/Camera parameters from XML element."""
    data = {}
    
    # Get name
    if ns_prefix:
        name_elem = pm_element.find(f'{ns_prefix}name', namespaces)
    else:
        name_elem = pm_element.find('name')
    
    if name_elem is not None and name_elem.text:
        data['name'] = name_elem.text.strip()
    else:
        data['name'] = ''
    
    # Try to find LookAt element
    lookat = None
    if ns_prefix:
        lookat = pm_element.find(f'{ns_prefix}LookAt', namespaces)
    else:
        lookat = pm_element.find('LookAt')
    
    # If no LookAt, try Camera
    if lookat is None:
        if ns_prefix:
            lookat = pm_element.find(f'{ns_prefix}Camera', namespaces)
        else:
            lookat = pm_element.find('Camera')
    
    if lookat is not None:
        # Extract camera parameters
        params = ['longitude', 'latitude', 'heading', 'tilt', 'range', 'altitude']
        for param in params:
            if ns_prefix:
                elem = lookat.find(f'{ns_prefix}{param}', namespaces)
            else:
                elem = lookat.find(param)
            
            if elem is not None and elem.text:
                try:
                    data[param] = float(elem.text.strip())
                except ValueError:
                    pass
    
    return data


def parse_kml_with_regex(kml_content):
    """Fallback regex-based KML parsing."""
    placemarks = []
    
    # Find all Placemark blocks
    placemark_pattern = r'<Placemark[^>]*>(.*?)</Placemark>'
    matches = re.findall(placemark_pattern, kml_content, re.DOTALL | re.IGNORECASE)
    
    for pm_content in matches:
        data = {}
        
        # Extract name
        name_match = re.search(r'<name[^>]*>(.*?)</name>', pm_content, re.DOTALL | re.IGNORECASE)
        if name_match:
            data['name'] = name_match.group(1).strip()
        
        # Extract LookAt or Camera parameters
        lookat_match = re.search(r'<LookAt[^>]*>(.*?)</LookAt>', pm_content, re.DOTALL | re.IGNORECASE)
        if not lookat_match:
            lookat_match = re.search(r'<Camera[^>]*>(.*?)</Camera>', pm_content, re.DOTALL | re.IGNORECASE)
        
        if lookat_match:
            lookat_content = lookat_match.group(1)
            
            for param in ['longitude', 'latitude', 'heading', 'tilt', 'range', 'altitude']:
                param_match = re.search(rf'<{param}[^>]*>(.*?)</{param}>', lookat_content, re.IGNORECASE)
                if param_match:
                    try:
                        data[param] = float(param_match.group(1).strip())
                    except ValueError:
                        pass
        
        if data.get('name'):
            placemarks.append(data)
    
    return placemarks


def find_horseshoe_placemark(placemarks, name_substring):
    """Find placemark containing the required name substring."""
    name_substring = name_substring.lower()
    
    for pm in placemarks:
        if name_substring in pm.get('name', '').lower():
            return pm
    
    return None


def verify_camera_viewpoint_save(traj, env_info, task_info):
    """
    Verify that a correctly configured viewpoint was saved to My Places.
    
    Uses multiple verification signals:
    1. KML file parsing for placemark data
    2. Timestamp checking for anti-gaming
    3. VLM trajectory verification
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Get metadata with defaults
    metadata = task_info.get('metadata', {})
    target_lat = metadata.get('target_latitude', 36.8791)
    target_lon = metadata.get('target_longitude', -111.5103)
    coord_tolerance = metadata.get('coord_tolerance', 0.05)
    heading_min = metadata.get('heading_min', 160)
    heading_max = metadata.get('heading_max', 200)
    tilt_min = metadata.get('tilt_min', 60)
    tilt_max = metadata.get('tilt_max', 80)
    range_min = metadata.get('range_min', 800)
    range_max = metadata.get('range_max', 2000)
    name_substring = metadata.get('required_name_substring', 'horseshoe')
    
    feedback_parts = []
    score = 0
    details = {}
    
    # ================================================================
    # Copy task result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        details['task_result'] = result
    except Exception as e:
        logger.warning(f"Could not read task result: {e}")
        result = {}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # Copy and parse myplaces.kml
    # ================================================================
    temp_kml = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
    kml_content = ""
    placemarks = []
    
    try:
        copy_from_env("/tmp/myplaces_final.kml", temp_kml.name)
        with open(temp_kml.name, 'r', encoding='utf-8', errors='ignore') as f:
            kml_content = f.read()
        placemarks = parse_myplaces_kml(kml_content)
        details['placemarks_found'] = len(placemarks)
        logger.info(f"Found {len(placemarks)} placemarks in myplaces.kml")
    except Exception as e:
        logger.warning(f"Could not read myplaces.kml: {e}")
        details['kml_error'] = str(e)
    finally:
        if os.path.exists(temp_kml.name):
            os.unlink(temp_kml.name)
    
    # ================================================================
    # CRITERION 1: Find placemark with 'Horseshoe' in name (15 pts)
    # ================================================================
    horseshoe_pm = find_horseshoe_placemark(placemarks, name_substring)
    
    if horseshoe_pm:
        score += 15
        feedback_parts.append(f"✅ Placemark found: '{horseshoe_pm.get('name', '')}'")
        details['placemark_name'] = horseshoe_pm.get('name', '')
        details['placemark_data'] = horseshoe_pm
    else:
        feedback_parts.append(f"❌ No placemark with '{name_substring}' in name")
        # Check if any placemarks exist at all
        if placemarks:
            names = [pm.get('name', 'unnamed') for pm in placemarks[:5]]
            feedback_parts.append(f"   Found placemarks: {names}")
        
        # Early exit if no matching placemark
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: Verify coordinates (20 pts)
    # ================================================================
    lat = horseshoe_pm.get('latitude')
    lon = horseshoe_pm.get('longitude')
    
    details['extracted_latitude'] = lat
    details['extracted_longitude'] = lon
    
    coords_correct = False
    if lat is not None and lon is not None:
        lat_diff = abs(lat - target_lat)
        lon_diff = abs(lon - target_lon)
        
        if lat_diff <= coord_tolerance and lon_diff <= coord_tolerance:
            score += 20
            coords_correct = True
            feedback_parts.append(f"✅ Coordinates correct ({lat:.4f}, {lon:.4f})")
        else:
            feedback_parts.append(f"❌ Coordinates incorrect ({lat:.4f}, {lon:.4f}) - expected near ({target_lat}, {target_lon})")
    else:
        feedback_parts.append("❌ No coordinates found in placemark")
    
    # ================================================================
    # CRITERION 3: Verify heading (20 pts)
    # ================================================================
    heading = horseshoe_pm.get('heading')
    details['extracted_heading'] = heading
    
    heading_correct = False
    if heading is not None:
        # Normalize heading to 0-360
        heading = heading % 360
        if heading_min <= heading <= heading_max:
            score += 20
            heading_correct = True
            feedback_parts.append(f"✅ Heading correct ({heading:.1f}°)")
        else:
            feedback_parts.append(f"❌ Heading incorrect ({heading:.1f}°) - expected {heading_min}°-{heading_max}°")
    else:
        feedback_parts.append("❌ No heading found in placemark")
    
    # ================================================================
    # CRITERION 4: Verify tilt (20 pts)
    # ================================================================
    tilt = horseshoe_pm.get('tilt')
    details['extracted_tilt'] = tilt
    
    tilt_correct = False
    if tilt is not None:
        if tilt_min <= tilt <= tilt_max:
            score += 20
            tilt_correct = True
            feedback_parts.append(f"✅ Tilt correct ({tilt:.1f}°)")
        else:
            feedback_parts.append(f"❌ Tilt incorrect ({tilt:.1f}°) - expected {tilt_min}°-{tilt_max}°")
    else:
        feedback_parts.append("❌ No tilt found in placemark")
    
    # ================================================================
    # CRITERION 5: Verify range/altitude (15 pts)
    # ================================================================
    range_val = horseshoe_pm.get('range') or horseshoe_pm.get('altitude')
    details['extracted_range'] = range_val
    
    range_correct = False
    if range_val is not None:
        if range_min <= range_val <= range_max:
            score += 15
            range_correct = True
            feedback_parts.append(f"✅ Range/altitude correct ({range_val:.0f}m)")
        else:
            feedback_parts.append(f"❌ Range incorrect ({range_val:.0f}m) - expected {range_min}-{range_max}m")
    else:
        feedback_parts.append("❌ No range/altitude found in placemark")
    
    # ================================================================
    # CRITERION 6: File modified during task - anti-gaming (10 pts)
    # ================================================================
    file_modified = result.get('file_modified_during_task', False)
    new_placemarks = result.get('new_placemarks_created', 0)
    
    if file_modified and new_placemarks > 0:
        score += 10
        feedback_parts.append(f"✅ File modified during task ({new_placemarks} new placemarks)")
    elif file_modified:
        score += 5
        feedback_parts.append("⚠️ File modified but no new placemarks detected")
    else:
        feedback_parts.append("❌ File not modified during task (possible pre-existing data)")
    
    # ================================================================
    # VLM Trajectory Verification (bonus validation)
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    vlm_score_bonus = 0
    
    if query_vlm and traj:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Get trajectory frames for process verification
            frames = sample_trajectory_frames(traj, n=5)
            final = get_final_screenshot(traj)
            
            if frames or final:
                vlm_prompt = """Analyze these Google Earth Pro screenshots from a task to save a viewpoint of Horseshoe Bend.

Look for evidence of:
1. Navigation to Horseshoe Bend (distinctive horseshoe-shaped river bend visible)
2. Camera angle adjustment (changing view perspective)
3. Save dialog or placemark creation (Add Placemark dialog, naming the location)
4. My Places panel interaction

Respond in JSON:
{
    "horseshoe_bend_visible": true/false,
    "camera_adjusted": true/false,
    "save_dialog_shown": true/false,
    "workflow_completed": true/false,
    "confidence": "low"/"medium"/"high"
}"""
                
                images_to_check = frames + ([final] if final else [])
                if images_to_check:
                    vlm_result = query_vlm(prompt=vlm_prompt, images=images_to_check)
                    
                    if vlm_result.get('success'):
                        parsed = vlm_result.get('parsed', {})
                        details['vlm_verification'] = parsed
                        
                        if parsed.get('workflow_completed') and parsed.get('horseshoe_bend_visible'):
                            feedback_parts.append("✅ VLM: Workflow verified")
                        elif parsed.get('horseshoe_bend_visible'):
                            feedback_parts.append("⚠️ VLM: Location visible but workflow uncertain")
                        else:
                            feedback_parts.append("⚠️ VLM: Could not verify workflow")
        except ImportError:
            logger.info("VLM trajectory verification not available")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
    
    # ================================================================
    # Calculate pass/fail
    # ================================================================
    camera_params_correct = sum([heading_correct, tilt_correct, range_correct])
    details['camera_params_correct'] = camera_params_correct
    
    # Pass requires: 70+ points AND coordinates correct AND at least 2/3 camera params
    passed = score >= 70 and coords_correct and camera_params_correct >= 2
    
    # Build final feedback
    feedback = " | ".join(feedback_parts)
    
    logger.info(f"Final score: {score}/100, Passed: {passed}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }