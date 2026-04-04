#!/usr/bin/env python3
"""
Verifier for River Sinuosity Analysis task.

VERIFICATION STRATEGY:
1. KML file existence and creation timing (20 points)
2. Placemark count and names (20 points)
3. Coordinate verification for start/end placemarks (15 points)
4. Measurement data extraction and validation (20 points)
5. Sinuosity calculation correctness (15 points)
6. VLM trajectory verification (10 points)

Pass threshold: 60 points with KML file created during task
"""

import json
import tempfile
import os
import re
import logging
import xml.etree.ElementTree as ET
from typing import Dict, Any, Optional, List, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_kml_content(kml_content: str) -> Optional[List[Dict]]:
    """Parse KML content and extract placemark data."""
    if not kml_content:
        return None
    
    try:
        # Handle potential encoding issues
        kml_content = kml_content.strip()
        if not kml_content.startswith('<?xml'):
            kml_content = '<?xml version="1.0" encoding="UTF-8"?>\n' + kml_content
        
        root = ET.fromstring(kml_content)
        
        # Define possible namespaces
        namespaces = [
            {'kml': 'http://www.opengis.net/kml/2.2'},
            {'kml': 'http://earth.google.com/kml/2.2'},
            {'kml': 'http://earth.google.com/kml/2.1'},
            {}  # No namespace
        ]
        
        placemarks = []
        
        for ns in namespaces:
            if ns:
                # Try with namespace
                pms = root.findall('.//{%s}Placemark' % ns.get('kml', ''))
            else:
                # Try without namespace
                pms = root.findall('.//Placemark')
            
            if pms:
                for pm in pms:
                    placemark_data = extract_placemark_data(pm, ns)
                    if placemark_data:
                        placemarks.append(placemark_data)
                break
        
        return placemarks if placemarks else None
        
    except ET.ParseError as e:
        logger.warning(f"KML parse error: {e}")
        return None
    except Exception as e:
        logger.warning(f"KML processing error: {e}")
        return None


def extract_placemark_data(pm_element, ns: dict) -> Optional[Dict]:
    """Extract data from a single placemark element."""
    try:
        ns_prefix = '{%s}' % ns.get('kml', '') if ns else ''
        
        # Get name
        name_elem = pm_element.find(f'{ns_prefix}name') if ns_prefix else pm_element.find('name')
        name = name_elem.text if name_elem is not None and name_elem.text else ""
        
        # Get description
        desc_elem = pm_element.find(f'{ns_prefix}description') if ns_prefix else pm_element.find('description')
        description = desc_elem.text if desc_elem is not None and desc_elem.text else ""
        
        # Get coordinates (try multiple paths)
        coords = ""
        coord_paths = [
            f'.//{ns_prefix}coordinates',
            './/coordinates',
            f'{ns_prefix}Point/{ns_prefix}coordinates',
            'Point/coordinates'
        ]
        
        for path in coord_paths:
            coord_elem = pm_element.find(path)
            if coord_elem is not None and coord_elem.text:
                coords = coord_elem.text.strip()
                break
        
        return {
            'name': name,
            'description': description,
            'coordinates': coords
        }
    except Exception as e:
        logger.warning(f"Error extracting placemark data: {e}")
        return None


def parse_coordinates(coord_string: str) -> Optional[Dict[str, float]]:
    """Parse KML coordinate string (lon,lat,alt) to dict."""
    if not coord_string:
        return None
    try:
        # Clean and split
        coord_string = coord_string.strip()
        parts = coord_string.split(',')
        if len(parts) >= 2:
            lon = float(parts[0].strip())
            lat = float(parts[1].strip())
            return {'lat': lat, 'lon': lon}
    except (ValueError, IndexError):
        pass
    return None


def verify_coordinate_proximity(actual: Dict, expected: Dict, tolerance: float) -> bool:
    """Check if coordinates are within tolerance."""
    if not actual or not expected:
        return False
    lat_diff = abs(actual.get('lat', 0) - expected.get('lat', 0))
    lon_diff = abs(actual.get('lon', 0) - expected.get('lon', 0))
    return lat_diff <= tolerance and lon_diff <= tolerance


def extract_numbers_from_text(text: str) -> List[float]:
    """Extract all numeric values from text."""
    if not text:
        return []
    # Match numbers including decimals
    pattern = r'[-+]?\d*\.?\d+'
    matches = re.findall(pattern, text)
    numbers = []
    for m in matches:
        try:
            numbers.append(float(m))
        except ValueError:
            pass
    return numbers


def classify_sinuosity(value: float) -> str:
    """Classify sinuosity value."""
    if value < 1.3:
        return "Straight"
    elif value <= 1.5:
        return "Sinuous"
    else:
        return "Meandering"


def analyze_measurements(description: str, metadata: Dict) -> Dict[str, Any]:
    """Analyze measurement data from placemark description."""
    result = {
        'straight_distance': None,
        'channel_length': None,
        'sinuosity': None,
        'classification': None,
        'valid_measurements': False,
        'calculation_correct': False
    }
    
    if not description:
        return result
    
    numbers = extract_numbers_from_text(description)
    desc_lower = description.lower()
    
    # Expected ranges from metadata
    straight_range = metadata.get('straight_distance_km', {'min': 20, 'max': 28})
    channel_range = metadata.get('channel_length_km', {'min': 32, 'max': 48})
    sinuosity_range = metadata.get('sinuosity_range', {'min': 1.3, 'max': 2.0})
    
    # Try to identify values by range heuristics
    for n in numbers:
        # Sinuosity is typically 1.0 - 2.5
        if 1.0 < n < 2.5 and result['sinuosity'] is None:
            result['sinuosity'] = n
        # Straight distance
        elif straight_range['min'] - 5 < n < straight_range['max'] + 5 and result['straight_distance'] is None:
            result['straight_distance'] = n
        # Channel length
        elif channel_range['min'] - 10 < n < channel_range['max'] + 10 and result['channel_length'] is None:
            result['channel_length'] = n
    
    # Check for classification keywords
    if 'meandering' in desc_lower:
        result['classification'] = 'Meandering'
    elif 'sinuous' in desc_lower:
        result['classification'] = 'Sinuous'
    elif 'straight' in desc_lower:
        result['classification'] = 'Straight'
    
    # Validate measurements
    if result['straight_distance'] and result['channel_length']:
        # Check ranges
        straight_valid = straight_range['min'] <= result['straight_distance'] <= straight_range['max']
        channel_valid = channel_range['min'] <= result['channel_length'] <= channel_range['max']
        result['valid_measurements'] = straight_valid and channel_valid
        
        # Check calculation
        if result['sinuosity']:
            expected_sinuosity = result['channel_length'] / result['straight_distance']
            result['calculation_correct'] = abs(result['sinuosity'] - expected_sinuosity) < 0.15
            
            # Check classification matches
            if result['classification']:
                expected_class = classify_sinuosity(result['sinuosity'])
                result['classification_correct'] = result['classification'] == expected_class
    
    return result


def verify_river_sinuosity_analysis(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the River Sinuosity Analysis task completion.
    
    Multi-criteria scoring with anti-gaming measures.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }
    
    metadata = task_info.get('metadata', {})
    feedback_parts = []
    score = 0
    details = {}
    
    # ================================================================
    # STEP 1: Copy and parse task result JSON
    # ================================================================
    result_data = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
        details['result_loaded'] = True
    except Exception as e:
        logger.warning(f"Failed to load task result: {e}")
        details['result_loaded'] = False
        details['result_error'] = str(e)
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # CRITERION 1: KML file exists and was created during task (20 pts)
    # ================================================================
    kml_output = result_data.get('kml_output', {})
    kml_exists = kml_output.get('exists', False)
    created_during_task = kml_output.get('created_during_task', False)
    kml_size = kml_output.get('size_bytes', 0)
    
    if kml_exists and created_during_task and kml_size > 100:
        score += 20
        feedback_parts.append("✅ KML file created during task")
        details['kml_valid'] = True
    elif kml_exists and kml_size > 100:
        score += 10
        feedback_parts.append("⚠️ KML exists but may predate task")
        details['kml_valid'] = False
    else:
        feedback_parts.append("❌ KML file not found or empty")
        details['kml_valid'] = False
    
    # ================================================================
    # STEP 2: Copy and parse KML content
    # ================================================================
    kml_content = ""
    placemarks = []
    
    if kml_exists:
        temp_kml = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
        try:
            copy_from_env("/tmp/exported_kml.kml", temp_kml.name)
            with open(temp_kml.name, 'r', encoding='utf-8', errors='ignore') as f:
                kml_content = f.read()
            placemarks = parse_kml_content(kml_content) or []
            details['placemark_count'] = len(placemarks)
        except Exception as e:
            logger.warning(f"Failed to parse KML: {e}")
            details['kml_parse_error'] = str(e)
        finally:
            if os.path.exists(temp_kml.name):
                os.unlink(temp_kml.name)
    
    # ================================================================
    # CRITERION 2: Placemark count and names (20 pts)
    # ================================================================
    expected_names = metadata.get('placemark_names', ['Sinuosity_Start', 'Sinuosity_End', 'Sinuosity_Analysis'])
    
    start_pm = None
    end_pm = None
    analysis_pm = None
    
    for pm in placemarks:
        name_lower = pm.get('name', '').lower()
        if 'start' in name_lower:
            start_pm = pm
        elif 'end' in name_lower:
            end_pm = pm
        elif 'analysis' in name_lower:
            analysis_pm = pm
    
    placemark_score = 0
    if start_pm:
        placemark_score += 6
        feedback_parts.append("✅ Start placemark found")
    else:
        feedback_parts.append("❌ Start placemark missing")
    
    if end_pm:
        placemark_score += 6
        feedback_parts.append("✅ End placemark found")
    else:
        feedback_parts.append("❌ End placemark missing")
    
    if analysis_pm:
        placemark_score += 8
        feedback_parts.append("✅ Analysis placemark found")
    else:
        feedback_parts.append("❌ Analysis placemark missing")
    
    score += placemark_score
    details['has_start'] = start_pm is not None
    details['has_end'] = end_pm is not None
    details['has_analysis'] = analysis_pm is not None
    
    # ================================================================
    # CRITERION 3: Coordinate verification (15 pts)
    # ================================================================
    coord_tolerance = metadata.get('coord_tolerance', 0.05)
    expected_start = metadata.get('start_coords', {'lat': 33.4000, 'lon': -91.0500})
    expected_end = metadata.get('end_coords', {'lat': 33.2500, 'lon': -91.2000})
    
    coord_score = 0
    
    if start_pm:
        start_coords = parse_coordinates(start_pm.get('coordinates', ''))
        if start_coords and verify_coordinate_proximity(start_coords, expected_start, coord_tolerance):
            coord_score += 7
            feedback_parts.append("✅ Start coordinates correct")
            details['start_coords_valid'] = True
        else:
            feedback_parts.append("⚠️ Start coordinates off target")
            details['start_coords_valid'] = False
            details['start_coords_actual'] = start_coords
    
    if end_pm:
        end_coords = parse_coordinates(end_pm.get('coordinates', ''))
        if end_coords and verify_coordinate_proximity(end_coords, expected_end, coord_tolerance):
            coord_score += 8
            feedback_parts.append("✅ End coordinates correct")
            details['end_coords_valid'] = True
        else:
            feedback_parts.append("⚠️ End coordinates off target")
            details['end_coords_valid'] = False
            details['end_coords_actual'] = end_coords
    
    score += coord_score
    
    # ================================================================
    # CRITERION 4: Measurement data validation (20 pts)
    # ================================================================
    measurement_score = 0
    measurement_analysis = {}
    
    if analysis_pm:
        description = analysis_pm.get('description', '')
        measurement_analysis = analyze_measurements(description, metadata)
        details['measurements'] = measurement_analysis
        
        if measurement_analysis.get('straight_distance'):
            measurement_score += 5
            feedback_parts.append(f"✅ Straight distance: {measurement_analysis['straight_distance']:.1f} km")
        
        if measurement_analysis.get('channel_length'):
            measurement_score += 5
            feedback_parts.append(f"✅ Channel length: {measurement_analysis['channel_length']:.1f} km")
        
        if measurement_analysis.get('valid_measurements'):
            measurement_score += 5
            feedback_parts.append("✅ Measurements in expected range")
        
        if measurement_analysis.get('sinuosity'):
            measurement_score += 5
            feedback_parts.append(f"✅ Sinuosity recorded: {measurement_analysis['sinuosity']:.2f}")
    
    score += measurement_score
    
    # ================================================================
    # CRITERION 5: Sinuosity calculation correctness (15 pts)
    # ================================================================
    calc_score = 0
    
    if measurement_analysis.get('calculation_correct'):
        calc_score += 10
        feedback_parts.append("✅ Sinuosity calculation correct")
    elif measurement_analysis.get('sinuosity'):
        calc_score += 5
        feedback_parts.append("⚠️ Sinuosity value present but calculation may be off")
    
    if measurement_analysis.get('classification'):
        expected_class = metadata.get('expected_classification', 'Meandering')
        if measurement_analysis['classification'] == expected_class:
            calc_score += 5
            feedback_parts.append(f"✅ Classification correct: {expected_class}")
        else:
            calc_score += 2
            feedback_parts.append(f"⚠️ Classification: {measurement_analysis['classification']} (expected {expected_class})")
    
    score += calc_score
    
    # ================================================================
    # CRITERION 6: VLM trajectory verification (10 pts)
    # ================================================================
    vlm_score = 0
    
    if query_vlm:
        try:
            # Import VLM utilities
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Get trajectory frames for process verification
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            
            all_frames = frames + ([final_frame] if final_frame else [])
            
            if all_frames:
                vlm_prompt = """Analyze these screenshots from a Google Earth task to measure river sinuosity.

The task required:
1. Navigate to Mississippi River near Greenville, MS
2. Create placemarks at start and end points
3. Use ruler tool to measure distances
4. Create an analysis placemark with calculations

Look for evidence of:
- Google Earth application visible
- Mississippi River area (meandering river with oxbow lakes)
- Ruler/measurement tool usage
- Placemark creation or editing dialogs
- KML export dialog

Respond in JSON:
{
    "google_earth_visible": true/false,
    "river_area_shown": true/false,
    "measurement_tool_used": true/false,
    "placemark_activity": true/false,
    "meaningful_progress": true/false,
    "confidence": "low"/"medium"/"high"
}"""
                
                vlm_result = query_vlm(prompt=vlm_prompt, images=all_frames)
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    details['vlm_analysis'] = parsed
                    
                    if parsed.get('google_earth_visible'):
                        vlm_score += 3
                    if parsed.get('river_area_shown'):
                        vlm_score += 3
                    if parsed.get('measurement_tool_used') or parsed.get('placemark_activity'):
                        vlm_score += 4
                    
                    if vlm_score > 0:
                        feedback_parts.append(f"✅ VLM verification: {vlm_score}/10 points")
                    else:
                        feedback_parts.append("⚠️ VLM could not confirm task activity")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            details['vlm_error'] = str(e)
    
    score += vlm_score
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    
    # Key criteria for passing
    key_criteria_met = (
        details.get('kml_valid', False) and
        (details.get('has_start', False) or details.get('has_end', False)) and
        (details.get('has_analysis', False) or measurement_analysis.get('sinuosity') is not None)
    )
    
    passed = score >= 60 and key_criteria_met
    
    # Bonus for exceptional work
    if score >= 90 and measurement_analysis.get('calculation_correct'):
        score = min(100, score + 5)
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts),
        "details": details
    }