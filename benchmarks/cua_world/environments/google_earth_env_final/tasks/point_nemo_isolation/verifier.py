#!/usr/bin/env python3
"""
Verifier for Point Nemo Isolation task.

ROBUST MULTI-SIGNAL VERIFICATION:
1. KML file exists and was created during task (15 points)
2. Point Nemo placemark exists at correct coordinates (20 points)
3. Point Nemo placemark properly named (10 points)
4. Ducie Island placemark exists at correct coordinates (20 points)
5. Ducie Island placemark properly named (10 points)
6. Distance measurement path exists (15 points)
7. Distance measurement accurate (~2688 km) (10 points)

VLM TRAJECTORY VERIFICATION (bonus validation):
- Verify agent navigated to remote ocean areas
- Verify ruler/measurement tool was used
- Verify placemark creation dialogs appeared

Pass threshold: 70 points with at least one correctly placed placemark and valid path
"""

import json
import tempfile
import os
import math
import re
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected coordinates
EXPECTED_NEMO = (-48.8767, -123.3933)  # lat, lon
EXPECTED_DUCIE = (-24.6667, -124.7833)  # lat, lon
EXPECTED_DISTANCE_KM = 2688
COORD_TOLERANCE_KM = 50
DISTANCE_TOLERANCE_KM = 100


def haversine_km(lat1, lon1, lat2, lon2):
    """Calculate distance between two coordinates in km using Haversine formula."""
    R = 6371  # Earth's radius in km
    lat1, lon1, lat2, lon2 = map(math.radians, [lat1, lon1, lat2, lon2])
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    a = math.sin(dlat/2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon/2)**2
    return 2 * R * math.asin(math.sqrt(a))


def parse_kml_coordinates(coord_string):
    """Parse KML coordinate string (lon,lat,alt) to (lat, lon)."""
    if not coord_string:
        return None
    coord_string = coord_string.strip()
    # KML format is longitude,latitude,altitude
    parts = coord_string.split(',')
    if len(parts) >= 2:
        try:
            lon = float(parts[0].strip())
            lat = float(parts[1].strip())
            return (lat, lon)
        except ValueError:
            return None
    return None


def extract_placemarks_from_kml(kml_content):
    """Extract placemarks from KML content string."""
    placemarks = []
    
    if not kml_content:
        return placemarks
    
    try:
        # Try to parse as XML
        root = ET.fromstring(kml_content)
        
        # Handle KML namespace
        namespaces = {
            'kml': 'http://www.opengis.net/kml/2.2',
            'gx': 'http://www.google.com/kml/ext/2.2'
        }
        
        # Try with namespace first
        for pm in root.findall('.//kml:Placemark', namespaces):
            name_elem = pm.find('kml:name', namespaces)
            coord_elem = pm.find('.//kml:coordinates', namespaces)
            
            name = name_elem.text if name_elem is not None and name_elem.text else ""
            coords = None
            if coord_elem is not None and coord_elem.text:
                # For placemarks, coordinates is usually a single point
                coord_text = coord_elem.text.strip().split()[0]  # Take first point
                coords = parse_kml_coordinates(coord_text)
            
            placemarks.append({'name': name, 'coords': coords})
        
        # If no placemarks found with namespace, try without
        if not placemarks:
            for pm in root.findall('.//Placemark'):
                name_elem = pm.find('name')
                coord_elem = pm.find('.//coordinates')
                
                name = name_elem.text if name_elem is not None and name_elem.text else ""
                coords = None
                if coord_elem is not None and coord_elem.text:
                    coord_text = coord_elem.text.strip().split()[0]
                    coords = parse_kml_coordinates(coord_text)
                
                placemarks.append({'name': name, 'coords': coords})
                
    except ET.ParseError as e:
        logger.warning(f"XML parse error: {e}")
        # Fall back to regex parsing
        placemark_pattern = r'<Placemark[^>]*>.*?</Placemark>'
        name_pattern = r'<name>([^<]*)</name>'
        coords_pattern = r'<coordinates>([^<]*)</coordinates>'
        
        for match in re.finditer(placemark_pattern, kml_content, re.DOTALL | re.IGNORECASE):
            pm_text = match.group(0)
            
            name_match = re.search(name_pattern, pm_text, re.IGNORECASE)
            coords_match = re.search(coords_pattern, pm_text, re.IGNORECASE)
            
            name = name_match.group(1) if name_match else ""
            coords = None
            if coords_match:
                coord_text = coords_match.group(1).strip().split()[0]
                coords = parse_kml_coordinates(coord_text)
            
            placemarks.append({'name': name, 'coords': coords})
    
    return placemarks


def extract_paths_from_kml(kml_content):
    """Extract LineString paths from KML content."""
    paths = []
    
    if not kml_content:
        return paths
    
    try:
        root = ET.fromstring(kml_content)
        namespaces = {'kml': 'http://www.opengis.net/kml/2.2'}
        
        # Find all LineString elements
        for elem in root.findall('.//kml:LineString', namespaces) + root.findall('.//LineString'):
            coord_elem = elem.find('.//kml:coordinates', namespaces)
            if coord_elem is None:
                coord_elem = elem.find('.//coordinates')
            
            if coord_elem is not None and coord_elem.text:
                points = []
                for coord_str in coord_elem.text.strip().split():
                    coord = parse_kml_coordinates(coord_str)
                    if coord:
                        points.append(coord)
                if len(points) >= 2:
                    paths.append(points)
                    
    except ET.ParseError:
        # Fall back to regex
        linestring_pattern = r'<LineString[^>]*>.*?</LineString>'
        coords_pattern = r'<coordinates>([^<]*)</coordinates>'
        
        for match in re.finditer(linestring_pattern, kml_content, re.DOTALL | re.IGNORECASE):
            ls_text = match.group(0)
            coords_match = re.search(coords_pattern, ls_text, re.IGNORECASE)
            
            if coords_match:
                points = []
                for coord_str in coords_match.group(1).strip().split():
                    coord = parse_kml_coordinates(coord_str)
                    if coord:
                        points.append(coord)
                if len(points) >= 2:
                    paths.append(points)
    
    return paths


def calculate_path_distance(path_points):
    """Calculate total distance of a path in km."""
    if len(path_points) < 2:
        return 0
    
    total_dist = 0
    for i in range(len(path_points) - 1):
        total_dist += haversine_km(
            path_points[i][0], path_points[i][1],
            path_points[i+1][0], path_points[i+1][1]
        )
    return total_dist


def verify_point_nemo_isolation(traj, env_info, task_info):
    """
    Verify the Point Nemo isolation measurement task.
    
    Uses multiple independent signals to verify:
    1. Programmatic: KML file content analysis
    2. Anti-gaming: File timestamp verification
    3. VLM: Trajectory verification for process confirmation
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/Documents/point_nemo_isolation.kml')
    
    feedback_parts = []
    score = 0
    details = {}
    
    # ================================================================
    # STEP 1: Copy result JSON from container
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
    
    details['export_result'] = {k: v for k, v in result.items() if k != 'kml_content'}
    
    # ================================================================
    # STEP 2: Check file exists and was created during task (anti-gaming)
    # ================================================================
    output_exists = result.get('output_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    output_size = result.get('output_size_bytes', 0)
    
    if not output_exists:
        feedback_parts.append("❌ KML file not found at expected path")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    if file_created_during_task:
        score += 10
        feedback_parts.append("✅ KML file created during task")
    else:
        feedback_parts.append("⚠️ KML file may predate task (timestamp check failed)")
        # Continue but with reduced score potential
    
    if output_size < 500:
        feedback_parts.append(f"⚠️ KML file suspiciously small ({output_size} bytes)")
    else:
        score += 5
        feedback_parts.append(f"✅ KML file has reasonable size ({output_size} bytes)")
    
    # ================================================================
    # STEP 3: Parse and analyze KML content
    # ================================================================
    kml_content = result.get('kml_content', '')
    
    if not kml_content or len(kml_content) < 100:
        feedback_parts.append("❌ KML content is empty or too short")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # Extract placemarks
    placemarks = extract_placemarks_from_kml(kml_content)
    details['placemarks_found'] = len(placemarks)
    feedback_parts.append(f"Found {len(placemarks)} placemark(s)")
    
    # Extract paths
    paths = extract_paths_from_kml(kml_content)
    details['paths_found'] = len(paths)
    feedback_parts.append(f"Found {len(paths)} path(s)")
    
    # ================================================================
    # STEP 4: Verify Point Nemo placemark (30 points total)
    # ================================================================
    nemo_found = False
    nemo_named = False
    nemo_details = {}
    
    for pm in placemarks:
        if pm['coords']:
            dist_to_nemo = haversine_km(
                pm['coords'][0], pm['coords'][1],
                EXPECTED_NEMO[0], EXPECTED_NEMO[1]
            )
            nemo_details[pm.get('name', 'unnamed')] = f"{dist_to_nemo:.1f}km from target"
            
            if dist_to_nemo <= COORD_TOLERANCE_KM:
                nemo_found = True
                score += 20
                feedback_parts.append(f"✅ Point Nemo placemark found ({dist_to_nemo:.1f}km from target)")
                
                # Check naming
                name = pm.get('name', '').lower()
                if 'nemo' in name or 'pole' in name or 'inaccessib' in name:
                    nemo_named = True
                    score += 10
                    feedback_parts.append("✅ Point Nemo placemark properly named")
                else:
                    feedback_parts.append(f"⚠️ Point Nemo placemark name unclear: '{pm.get('name', '')}'")
                break
    
    if not nemo_found:
        feedback_parts.append("❌ Point Nemo placemark not found at correct location")
        details['nemo_distances'] = nemo_details
    
    # ================================================================
    # STEP 5: Verify Ducie Island placemark (30 points total)
    # ================================================================
    ducie_found = False
    ducie_named = False
    ducie_details = {}
    
    for pm in placemarks:
        if pm['coords']:
            dist_to_ducie = haversine_km(
                pm['coords'][0], pm['coords'][1],
                EXPECTED_DUCIE[0], EXPECTED_DUCIE[1]
            )
            ducie_details[pm.get('name', 'unnamed')] = f"{dist_to_ducie:.1f}km from target"
            
            if dist_to_ducie <= COORD_TOLERANCE_KM:
                ducie_found = True
                score += 20
                feedback_parts.append(f"✅ Ducie Island placemark found ({dist_to_ducie:.1f}km from target)")
                
                # Check naming
                name = pm.get('name', '').lower()
                if 'ducie' in name:
                    ducie_named = True
                    score += 10
                    feedback_parts.append("✅ Ducie Island placemark properly named")
                else:
                    feedback_parts.append(f"⚠️ Ducie placemark name unclear: '{pm.get('name', '')}'")
                break
    
    if not ducie_found:
        feedback_parts.append("❌ Ducie Island placemark not found at correct location")
        details['ducie_distances'] = ducie_details
    
    # ================================================================
    # STEP 6: Verify distance measurement path (25 points total)
    # ================================================================
    path_found = False
    distance_accurate = False
    path_details = {}
    
    for i, path in enumerate(paths):
        if len(path) >= 2:
            total_dist = calculate_path_distance(path)
            path_details[f'path_{i}'] = f"{total_dist:.0f}km"
            
            # Check if path connects the two target locations
            start_near_nemo = haversine_km(
                path[0][0], path[0][1],
                EXPECTED_NEMO[0], EXPECTED_NEMO[1]
            ) <= COORD_TOLERANCE_KM * 2
            
            end_near_ducie = haversine_km(
                path[-1][0], path[-1][1],
                EXPECTED_DUCIE[0], EXPECTED_DUCIE[1]
            ) <= COORD_TOLERANCE_KM * 2
            
            start_near_ducie = haversine_km(
                path[0][0], path[0][1],
                EXPECTED_DUCIE[0], EXPECTED_DUCIE[1]
            ) <= COORD_TOLERANCE_KM * 2
            
            end_near_nemo = haversine_km(
                path[-1][0], path[-1][1],
                EXPECTED_NEMO[0], EXPECTED_NEMO[1]
            ) <= COORD_TOLERANCE_KM * 2
            
            connects_targets = (start_near_nemo and end_near_ducie) or (start_near_ducie and end_near_nemo)
            
            if connects_targets:
                path_found = True
                score += 15
                feedback_parts.append(f"✅ Distance measurement path found (length: {total_dist:.0f}km)")
                
                # Check distance accuracy
                if abs(total_dist - EXPECTED_DISTANCE_KM) <= DISTANCE_TOLERANCE_KM:
                    distance_accurate = True
                    score += 10
                    feedback_parts.append(f"✅ Distance measurement accurate (within {DISTANCE_TOLERANCE_KM}km tolerance)")
                else:
                    feedback_parts.append(f"⚠️ Distance measurement inaccurate: {total_dist:.0f}km (expected ~{EXPECTED_DISTANCE_KM}km)")
                break
    
    if not path_found:
        feedback_parts.append("❌ Valid measurement path not found connecting the two locations")
        details['path_distances'] = path_details
    
    # ================================================================
    # STEP 7: VLM trajectory verification (bonus validation)
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    vlm_score = 0
    
    if query_vlm and traj:
        try:
            # Import trajectory sampling utilities
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Sample frames from throughout the trajectory
            frames = sample_trajectory_frames(traj, n=5)
            final_frame = get_final_screenshot(traj)
            
            if frames or final_frame:
                all_frames = (frames or []) + ([final_frame] if final_frame else [])
                
                vlm_prompt = """Analyze these screenshots from a Google Earth session where the agent should have:
1. Navigated to Point Nemo (remote South Pacific Ocean)
2. Created placemarks at Point Nemo and Ducie Island
3. Used the ruler/measurement tool to measure distance between them
4. Saved the results as a KML file

Look for evidence of:
- Navigation to remote ocean areas (blue water, no nearby land)
- Placemark creation dialogs or icons
- Ruler/measurement tool being used
- File save dialog

Respond in JSON:
{
    "remote_ocean_navigation": true/false,
    "placemark_activity": true/false,
    "measurement_tool_used": true/false,
    "file_save_activity": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}"""
                
                vlm_result = query_vlm(prompt=vlm_prompt, images=all_frames)
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    details['vlm_verification'] = parsed
                    
                    # VLM provides supporting evidence but doesn't add/subtract from score
                    if parsed.get('remote_ocean_navigation') and parsed.get('measurement_tool_used'):
                        feedback_parts.append("✅ VLM confirms navigation and measurement activity")
                    elif parsed.get('confidence') == 'low':
                        feedback_parts.append("⚠️ VLM verification inconclusive")
                        
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            details['vlm_error'] = str(e)
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    details['score_breakdown'] = {
        'file_created_during_task': 10 if file_created_during_task else 0,
        'file_size_ok': 5 if output_size >= 500 else 0,
        'nemo_placemark_location': 20 if nemo_found else 0,
        'nemo_placemark_name': 10 if nemo_named else 0,
        'ducie_placemark_location': 20 if ducie_found else 0,
        'ducie_placemark_name': 10 if ducie_named else 0,
        'path_exists': 15 if path_found else 0,
        'distance_accurate': 10 if distance_accurate else 0
    }
    
    # Key criteria: at least one correct placemark AND a valid path
    key_criteria_met = (nemo_found or ducie_found) and path_found
    passed = score >= 70 and key_criteria_met
    
    details['key_criteria_met'] = key_criteria_met
    details['final_score'] = score
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "details": details
    }