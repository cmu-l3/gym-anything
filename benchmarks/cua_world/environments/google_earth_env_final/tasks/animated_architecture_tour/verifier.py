#!/usr/bin/env python3
"""
Verifier for animated_architecture_tour@1 task.

VERIFICATION STRATEGY:
1. KMZ/KML file exists at expected path (10 pts)
2. File was created during task (anti-gaming) (10 pts)
3. Valid KMZ/KML structure (10 pts)
4. Folder "Modern Architecture Tour" exists (10 pts)
5. Sydney Opera House placemark correct (15 pts)
6. Burj Khalifa placemark correct (15 pts)
7. Guggenheim Bilbao placemark correct (15 pts)
8. Tour element present (10 pts)
9. VLM trajectory verification (5 pts)

Pass threshold: 70 points with at least 2 correct locations and valid file
"""

import json
import tempfile
import os
import zipfile
import xml.etree.ElementTree as ET
import math
import logging
from typing import Dict, Any, List, Optional, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# KML namespaces
KML_NS = {
    'kml': 'http://www.opengis.net/kml/2.2',
    'gx': 'http://www.google.com/kml/ext/2.2',
    'atom': 'http://www.w3.org/2005/Atom'
}

# Expected locations from task metadata
EXPECTED_LOCATIONS = {
    "sydney": {
        "name_patterns": ["sydney", "opera"],
        "lat": -33.857,
        "lon": 151.215,
        "tolerance": 0.1
    },
    "dubai": {
        "name_patterns": ["burj", "khalifa", "dubai"],
        "lat": 25.197,
        "lon": 55.274,
        "tolerance": 0.1
    },
    "bilbao": {
        "name_patterns": ["guggenheim", "bilbao"],
        "lat": 43.269,
        "lon": -2.934,
        "tolerance": 0.1
    }
}


def haversine_distance_deg(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate distance between two points in degrees (simplified for tolerance check)."""
    return math.sqrt((lat2 - lat1) ** 2 + (lon2 - lon1) ** 2)


def extract_kmz_content(filepath: str) -> Optional[str]:
    """Extract KML content from KMZ file."""
    try:
        with zipfile.ZipFile(filepath, 'r') as z:
            kml_files = [f for f in z.namelist() if f.endswith('.kml')]
            if not kml_files:
                return None
            kml_file = 'doc.kml' if 'doc.kml' in kml_files else kml_files[0]
            return z.read(kml_file).decode('utf-8')
    except (zipfile.BadZipFile, KeyError, Exception) as e:
        logger.warning(f"Error extracting KMZ: {e}")
        return None


def parse_kml_content(kml_content: str) -> Optional[ET.Element]:
    """Parse KML content and return root element."""
    try:
        for prefix, uri in KML_NS.items():
            ET.register_namespace(prefix, uri)
        return ET.fromstring(kml_content)
    except ET.ParseError as e:
        logger.warning(f"Error parsing KML: {e}")
        return None


def find_folder_by_name(root: ET.Element, folder_name_pattern: str) -> Optional[ET.Element]:
    """Find folder with matching name (case-insensitive)."""
    pattern_lower = folder_name_pattern.lower()
    
    for elem in root.iter():
        tag_local = elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag
        if tag_local in ['Folder', 'Document']:
            name_elem = elem.find('.//{http://www.opengis.net/kml/2.2}name')
            if name_elem is not None and name_elem.text:
                if pattern_lower in name_elem.text.lower():
                    return elem
    return None


def extract_placemarks(root: ET.Element) -> List[Dict[str, Any]]:
    """Extract all placemarks with their coordinates."""
    placemarks = []
    
    for placemark in root.iter('{http://www.opengis.net/kml/2.2}Placemark'):
        name_elem = placemark.find('{http://www.opengis.net/kml/2.2}name')
        coords_elem = placemark.find('.//{http://www.opengis.net/kml/2.2}coordinates')
        
        if coords_elem is not None and coords_elem.text:
            name = name_elem.text if name_elem is not None and name_elem.text else "Unnamed"
            coords_text = coords_elem.text.strip()
            
            try:
                # Parse coordinates (lon,lat,alt format)
                parts = coords_text.split(',')
                lon = float(parts[0].strip())
                lat = float(parts[1].strip())
                placemarks.append({
                    'name': name,
                    'lat': lat,
                    'lon': lon
                })
            except (ValueError, IndexError) as e:
                logger.debug(f"Could not parse coordinates: {coords_text}")
                continue
    
    return placemarks


def check_location_match(placemarks: List[Dict], location_info: Dict) -> Tuple[bool, Optional[Dict]]:
    """Check if any placemark matches the expected location."""
    for pm in placemarks:
        name_lower = pm['name'].lower()
        name_match = any(pattern in name_lower for pattern in location_info['name_patterns'])
        
        dist = haversine_distance_deg(
            pm['lat'], pm['lon'],
            location_info['lat'], location_info['lon']
        )
        coord_match = dist <= location_info['tolerance']
        
        # Accept if name matches with coordinates, or just coordinates alone
        if (name_match and coord_match) or coord_match:
            return True, pm
    
    return False, None


def check_tour_elements(root: ET.Element) -> Tuple[bool, int]:
    """Check for tour/animation elements in KML."""
    tour_found = False
    flyto_count = 0
    
    for elem in root.iter():
        tag = elem.tag
        if 'Tour' in tag:
            tour_found = True
        if 'FlyTo' in tag:
            flyto_count += 1
        if 'AnimatedUpdate' in tag:
            tour_found = True
        if 'Playlist' in tag:
            tour_found = True
    
    return tour_found, flyto_count


# VLM verification prompt for trajectory
VLM_TRAJECTORY_PROMPT = """Analyze these trajectory screenshots from a Google Earth tour creation task.

The agent was asked to:
1. Navigate to Sydney Opera House (Australia)
2. Navigate to Burj Khalifa (Dubai)
3. Navigate to Guggenheim Museum Bilbao (Spain)
4. Create placemarks at each location
5. Create a folder and record a tour
6. Export as KMZ file

Look for evidence of:
1. SYDNEY_VISITED: Screenshots showing Sydney/Australia with harbor or Opera House area
2. DUBAI_VISITED: Screenshots showing Dubai/UAE with tall skyscrapers or desert area
3. BILBAO_VISITED: Screenshots showing Bilbao/Spain or European coastal city
4. PLACEMARK_CREATION: "Add Placemark" dialogs or placemark pins visible
5. FOLDER_CREATION: Folder creation dialog or "Modern Architecture Tour" visible in Places panel
6. TOUR_RECORDING: Tour control bar visible, record button, or play controls
7. FILE_SAVE: Save dialog visible, file path showing architecture_tour.kmz

Respond in JSON:
{
    "sydney_visited": true/false,
    "dubai_visited": true/false,
    "bilbao_visited": true/false,
    "placemark_creation_seen": true/false,
    "folder_seen": true/false,
    "tour_controls_seen": true/false,
    "file_save_seen": true/false,
    "meaningful_progression": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}
"""


def verify_animated_architecture_tour(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that the animated architecture tour was created correctly.
    
    Uses multi-signal verification:
    - Programmatic KMZ/KML file analysis
    - Timestamp anti-gaming checks
    - VLM trajectory verification
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available"
        }
    
    metadata = task_info.get('metadata', {})
    feedback_parts = []
    details = {}
    score = 0
    
    # ================================================================
    # Copy task result from container
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
    # CRITERION 1: Output file exists (10 points)
    # ================================================================
    output_exists = result_data.get('output_exists', False)
    output_path = result_data.get('output_path', '')
    output_format = result_data.get('output_format', '')
    
    if output_exists:
        score += 10
        feedback_parts.append(f"✅ Output file exists ({output_format.upper()})")
        details['file_exists'] = True
    else:
        feedback_parts.append("❌ Output file not found")
        details['file_exists'] = False
        # Try VLM-only verification if no file
        if query_vlm and traj:
            vlm_score = _verify_via_vlm_only(traj, query_vlm)
            if vlm_score > 0:
                return {
                    "passed": False,
                    "score": vlm_score,
                    "feedback": "❌ No output file, but trajectory shows partial work | " + " | ".join(feedback_parts),
                    "details": details
                }
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: File created during task (10 points) - anti-gaming
    # ================================================================
    file_created_during_task = result_data.get('file_created_during_task', False)
    
    if file_created_during_task:
        score += 10
        feedback_parts.append("✅ File created during task")
        details['timestamp_valid'] = True
    else:
        feedback_parts.append("⚠️ File timestamp suspicious")
        details['timestamp_valid'] = False
    
    # ================================================================
    # Copy and analyze KMZ/KML file
    # ================================================================
    kml_content = None
    temp_output = tempfile.NamedTemporaryFile(delete=False, suffix=f'.{output_format}')
    try:
        copy_from_env(output_path, temp_output.name)
        
        if output_format == 'kmz':
            kml_content = extract_kmz_content(temp_output.name)
        else:
            with open(temp_output.name, 'r') as f:
                kml_content = f.read()
        
        details['kml_extracted'] = kml_content is not None
    except Exception as e:
        logger.warning(f"Could not copy/read output file: {e}")
        details['file_read_error'] = str(e)
    finally:
        if os.path.exists(temp_output.name):
            os.unlink(temp_output.name)
    
    # ================================================================
    # CRITERION 3: Valid KML structure (10 points)
    # ================================================================
    root = None
    if kml_content:
        root = parse_kml_content(kml_content)
        if root is not None:
            score += 10
            feedback_parts.append("✅ Valid KML structure")
            details['valid_kml'] = True
        else:
            feedback_parts.append("❌ Invalid KML structure")
            details['valid_kml'] = False
    else:
        feedback_parts.append("❌ Could not extract KML content")
        details['valid_kml'] = False
    
    if root is None:
        # Cannot proceed without valid KML
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 4: Folder exists (10 points)
    # ================================================================
    folder = find_folder_by_name(root, "modern architecture")
    if folder is not None:
        score += 10
        feedback_parts.append("✅ 'Modern Architecture Tour' folder found")
        details['folder_exists'] = True
    else:
        # Also accept if folder name is slightly different
        folder = find_folder_by_name(root, "architecture")
        if folder is not None:
            score += 7
            feedback_parts.append("⚠️ Architecture folder found (name variation)")
            details['folder_exists'] = True
        else:
            feedback_parts.append("❌ Folder not found")
            details['folder_exists'] = False
    
    # ================================================================
    # Extract and verify placemarks
    # ================================================================
    placemarks = extract_placemarks(root)
    details['placemarks_found'] = len(placemarks)
    details['placemark_names'] = [p['name'] for p in placemarks]
    
    # ================================================================
    # CRITERIA 5-7: Location verification (15 points each)
    # ================================================================
    locations_correct = 0
    
    for loc_key, loc_info in EXPECTED_LOCATIONS.items():
        match_found, matched_pm = check_location_match(placemarks, loc_info)
        if match_found:
            score += 15
            locations_correct += 1
            feedback_parts.append(f"✅ {loc_key.title()} placemark correct")
            details[f'{loc_key}_correct'] = True
            if matched_pm:
                details[f'{loc_key}_coords'] = f"({matched_pm['lat']:.3f}, {matched_pm['lon']:.3f})"
        else:
            feedback_parts.append(f"❌ {loc_key.title()} placemark not found/incorrect")
            details[f'{loc_key}_correct'] = False
    
    details['locations_correct_count'] = locations_correct
    
    # ================================================================
    # CRITERION 8: Tour element present (10 points)
    # ================================================================
    tour_found, flyto_count = check_tour_elements(root)
    
    if tour_found:
        score += 10
        feedback_parts.append(f"✅ Tour element found (FlyTo: {flyto_count})")
        details['tour_element'] = True
        details['flyto_count'] = flyto_count
    else:
        # Partial credit if placemarks exist but no tour
        if len(placemarks) >= 3:
            score += 3
            feedback_parts.append("⚠️ Placemarks exist but no tour element")
        else:
            feedback_parts.append("❌ No tour element found")
        details['tour_element'] = False
        details['flyto_count'] = flyto_count
    
    # ================================================================
    # CRITERION 9: VLM trajectory verification (5 points)
    # ================================================================
    vlm_score = 0
    if query_vlm and traj:
        vlm_result = _verify_trajectory_vlm(traj, query_vlm)
        vlm_score = vlm_result.get('score', 0)
        if vlm_score >= 3:
            score += 5
            feedback_parts.append("✅ Trajectory shows tour creation workflow")
        elif vlm_score > 0:
            score += vlm_score
            feedback_parts.append(f"⚠️ Partial trajectory evidence (+{vlm_score})")
        details['vlm_verification'] = vlm_result
    
    # ================================================================
    # Determine pass/fail
    # ================================================================
    # Pass requires: 70+ points AND at least 2 correct locations AND valid file
    key_criteria_met = (
        details.get('file_exists', False) and
        locations_correct >= 2
    )
    
    passed = score >= 70 and key_criteria_met
    
    # Final feedback
    feedback = f"Score: {score}/100 | " + " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }


def _verify_trajectory_vlm(traj: Dict[str, Any], query_vlm) -> Dict[str, Any]:
    """Verify trajectory using VLM on sampled frames."""
    try:
        # Import trajectory sampling utilities
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        # Sample frames across the trajectory
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        
        if final and final not in frames:
            frames.append(final)
        
        if not frames:
            return {'score': 0, 'error': 'No frames available'}
        
        # Query VLM with multiple frames
        vlm_result = query_vlm(
            prompt=VLM_TRAJECTORY_PROMPT,
            images=frames
        )
        
        if not vlm_result.get('success'):
            return {'score': 0, 'error': vlm_result.get('error', 'VLM failed')}
        
        parsed = vlm_result.get('parsed', {})
        
        # Calculate score from VLM results
        vlm_score = 0
        if parsed.get('sydney_visited'):
            vlm_score += 1
        if parsed.get('dubai_visited'):
            vlm_score += 1
        if parsed.get('bilbao_visited'):
            vlm_score += 1
        if parsed.get('placemark_creation_seen'):
            vlm_score += 1
        if parsed.get('tour_controls_seen') or parsed.get('file_save_seen'):
            vlm_score += 1
        
        return {
            'score': min(vlm_score, 5),
            'parsed': parsed,
            'confidence': parsed.get('confidence', 'low')
        }
        
    except ImportError:
        logger.warning("Could not import VLM utilities")
        return {'score': 0, 'error': 'VLM utilities not available'}
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        return {'score': 0, 'error': str(e)}


def _verify_via_vlm_only(traj: Dict[str, Any], query_vlm) -> int:
    """Fallback VLM-only verification when no output file exists."""
    try:
        vlm_result = _verify_trajectory_vlm(traj, query_vlm)
        # Give partial credit for demonstrated work
        return min(vlm_result.get('score', 0) * 5, 25)
    except Exception:
        return 0


if __name__ == "__main__":
    # Test mode
    print("Verifier module loaded successfully")
    print(f"Expected locations: {list(EXPECTED_LOCATIONS.keys())}")