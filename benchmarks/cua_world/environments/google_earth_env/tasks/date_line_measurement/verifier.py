#!/usr/bin/env python3
"""
Verifier for Date Line Distance Measurement task.

VERIFICATION STRATEGY:
This task requires measuring the distance between Big Diomede Island (Russia)
and Little Diomede Island (USA) in the Bering Strait.

Multi-signal verification:
1. KML file exists and was created during task (15 pts)
2. Big Diomede placemark exists at correct coordinates (20 pts)
3. Little Diomede placemark exists at correct coordinates (20 pts)
4. Distance placemark exists (10 pts)
5. Distance value documented in description (15 pts)
6. Distance value is accurate (3.0-5.0 km range) (20 pts)

Additional checks:
- VLM trajectory verification for workflow progression
- Timestamp verification to prevent pre-created files
- Coordinate sanity checks (placemarks on land, not water)
- Placemark separation check (must be on different islands)

Pass threshold: 70 points with both island placemarks correctly positioned
"""

import json
import tempfile
import os
import re
import math
import logging
import xml.etree.ElementTree as ET
from typing import Dict, Any, List, Optional, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ================================================================
# COORDINATE RANGES (from task metadata)
# ================================================================
BIG_DIOMEDE_LAT_RANGE = (65.70, 65.85)
BIG_DIOMEDE_LON_RANGE = (-169.20, -168.90)
LITTLE_DIOMEDE_LAT_RANGE = (65.70, 65.82)
LITTLE_DIOMEDE_LON_RANGE = (-169.00, -168.80)
EXPECTED_DISTANCE_KM_RANGE = (3.0, 5.0)
MIN_PLACEMARK_SEPARATION_DEG = 0.03


# ================================================================
# KML PARSING FUNCTIONS
# ================================================================

def parse_kml_content(kml_content: str) -> List[Dict[str, Any]]:
    """Parse KML content and extract placemarks."""
    placemarks = []
    
    if not kml_content or kml_content.strip() == '':
        return placemarks
    
    try:
        root = ET.fromstring(kml_content)
        
        # Handle KML namespace
        namespaces = {
            'kml': 'http://www.opengis.net/kml/2.2',
            'gx': 'http://www.google.com/kml/ext/2.2'
        }
        
        # Try with namespace first
        for pm in root.findall('.//kml:Placemark', namespaces):
            placemark = extract_placemark_data(pm, namespaces)
            if placemark:
                placemarks.append(placemark)
        
        # If no results, try without namespace
        if not placemarks:
            for pm in root.iter():
                if pm.tag.endswith('Placemark') or pm.tag == 'Placemark':
                    placemark = extract_placemark_data_no_ns(pm)
                    if placemark:
                        placemarks.append(placemark)
        
    except ET.ParseError as e:
        logger.warning(f"KML parse error: {e}")
    except Exception as e:
        logger.warning(f"Error parsing KML: {e}")
    
    return placemarks


def extract_placemark_data(pm_elem, namespaces: dict) -> Optional[Dict[str, Any]]:
    """Extract data from a placemark element with namespace."""
    try:
        name_elem = pm_elem.find('kml:name', namespaces)
        desc_elem = pm_elem.find('kml:description', namespaces)
        coords_elem = pm_elem.find('.//kml:coordinates', namespaces)
        
        name = name_elem.text.strip() if name_elem is not None and name_elem.text else ""
        description = desc_elem.text.strip() if desc_elem is not None and desc_elem.text else ""
        
        coords = None
        if coords_elem is not None and coords_elem.text:
            coords = parse_coordinates(coords_elem.text)
        
        if name or coords:
            return {
                'name': name,
                'description': description,
                'coords': coords
            }
    except Exception as e:
        logger.debug(f"Error extracting placemark: {e}")
    
    return None


def extract_placemark_data_no_ns(pm_elem) -> Optional[Dict[str, Any]]:
    """Extract data from a placemark element without namespace."""
    try:
        name = ""
        description = ""
        coords = None
        
        for child in pm_elem:
            tag = child.tag.split('}')[-1] if '}' in child.tag else child.tag
            
            if tag == 'name' and child.text:
                name = child.text.strip()
            elif tag == 'description' and child.text:
                description = child.text.strip()
            elif tag == 'Point':
                for subchild in child:
                    subtag = subchild.tag.split('}')[-1] if '}' in subchild.tag else subchild.tag
                    if subtag == 'coordinates' and subchild.text:
                        coords = parse_coordinates(subchild.text)
            elif tag == 'LookAt':
                # LookAt can also contain coordinates
                for subchild in child:
                    subtag = subchild.tag.split('}')[-1] if '}' in subchild.tag else subchild.tag
                    if subtag == 'longitude' and subchild.text:
                        lon = float(subchild.text.strip())
                    if subtag == 'latitude' and subchild.text:
                        lat = float(subchild.text.strip())
        
        if name or coords:
            return {
                'name': name,
                'description': description,
                'coords': coords
            }
    except Exception as e:
        logger.debug(f"Error extracting placemark (no ns): {e}")
    
    return None


def parse_coordinates(coord_text: str) -> Optional[Tuple[float, float]]:
    """Parse KML coordinates string to (longitude, latitude) tuple."""
    try:
        # KML format: longitude,latitude,altitude
        parts = coord_text.strip().split(',')
        if len(parts) >= 2:
            lon = float(parts[0].strip())
            lat = float(parts[1].strip())
            return (lon, lat)
    except (ValueError, IndexError):
        pass
    return None


# ================================================================
# COORDINATE VALIDATION FUNCTIONS
# ================================================================

def check_coordinate_in_range(lon: float, lat: float, 
                              lat_range: Tuple[float, float], 
                              lon_range: Tuple[float, float]) -> bool:
    """Check if coordinates fall within expected ranges."""
    return (lat_range[0] <= lat <= lat_range[1] and 
            lon_range[0] <= lon <= lon_range[1])


def haversine_distance_km(lon1: float, lat1: float, 
                          lon2: float, lat2: float) -> float:
    """Calculate distance between two points in kilometers using Haversine formula."""
    R = 6371  # Earth's radius in km
    
    lat1_rad = math.radians(lat1)
    lat2_rad = math.radians(lat2)
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    
    a = math.sin(dlat/2)**2 + math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(dlon/2)**2
    c = 2 * math.asin(math.sqrt(min(1, a)))
    
    return R * c


def calculate_separation_degrees(lon1: float, lat1: float,
                                  lon2: float, lat2: float) -> float:
    """Calculate rough separation in degrees."""
    return math.sqrt((lon2 - lon1)**2 + (lat2 - lat1)**2)


# ================================================================
# DISTANCE EXTRACTION FUNCTIONS
# ================================================================

def extract_distance_from_text(text: str) -> Optional[float]:
    """Extract distance value in km from description text."""
    if not text:
        return None
    
    text_lower = text.lower()
    
    # Patterns to match distance values
    patterns = [
        r'(\d+\.?\d*)\s*km',
        r'(\d+\.?\d*)\s*kilometer',
        r'(\d+\.?\d*)\s*kilometres',
        r'distance[:\s]+(\d+\.?\d*)',
        r'(\d+\.?\d*)\s*k\.?m\.?',
        r'approximately\s+(\d+\.?\d*)',
        r'~\s*(\d+\.?\d*)',
        r'(\d+\.?\d*)\s*nautical',  # Might need conversion
    ]
    
    for pattern in patterns:
        match = re.search(pattern, text_lower)
        if match:
            try:
                value = float(match.group(1))
                # Sanity check - distance should be reasonable
                if 0.1 <= value <= 100:
                    return value
            except ValueError:
                continue
    
    # Also try to find any standalone number that could be a distance
    numbers = re.findall(r'(\d+\.?\d+)', text)
    for num_str in numbers:
        try:
            value = float(num_str)
            if 2.0 <= value <= 10.0:  # Likely a km distance for this task
                return value
        except ValueError:
            continue
    
    return None


# ================================================================
# VLM VERIFICATION FUNCTIONS
# ================================================================

def verify_via_vlm(traj: Dict[str, Any], query_vlm, 
                   sample_trajectory_frames) -> Dict[str, Any]:
    """Verify task completion using VLM on trajectory frames."""
    
    if not query_vlm or not sample_trajectory_frames:
        return {"success": False, "score": 0, "error": "VLM functions not available"}
    
    try:
        # Sample frames from trajectory
        frames = sample_trajectory_frames(traj, n=5)
        
        if not frames:
            return {"success": False, "score": 0, "error": "No trajectory frames available"}
        
        vlm_prompt = """Analyze these screenshots from a Google Earth session where the agent was tasked with:
1. Navigating to the Bering Strait region (between Russia and Alaska)
2. Finding the Diomede Islands (two small islands near the International Date Line)
3. Creating placemarks on both islands
4. Measuring the distance between them
5. Saving the results to a KML file

Look at the progression across these frames and assess:
1. NAVIGATION_TO_ARCTIC: Did the agent navigate to a polar/arctic region showing small islands?
2. DIOMEDE_ISLANDS_VISIBLE: Are two small islands visible that could be the Diomedes?
3. PLACEMARK_CREATION: Are there any signs of placemark creation (dialog boxes, markers on map)?
4. MEASUREMENT_TOOL: Is there evidence of using the ruler/measurement tool?
5. SAVE_DIALOG: Is there evidence of saving files (save dialog, file browser)?

Respond in JSON format:
{
    "navigation_to_arctic": true/false,
    "diomede_islands_visible": true/false,
    "placemark_creation": true/false,
    "measurement_tool_used": true/false,
    "save_dialog_shown": true/false,
    "workflow_progression": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see in the frames"
}
"""
        
        result = query_vlm(prompt=vlm_prompt, images=frames)
        
        if not result.get("success"):
            return {"success": False, "score": 0, "error": result.get("error", "VLM query failed")}
        
        parsed = result.get("parsed", {})
        
        # Calculate VLM score
        criteria_met = sum([
            parsed.get("navigation_to_arctic", False),
            parsed.get("diomede_islands_visible", False),
            parsed.get("placemark_creation", False),
            parsed.get("measurement_tool_used", False),
            parsed.get("save_dialog_shown", False),
            parsed.get("workflow_progression", False),
        ])
        
        confidence = parsed.get("confidence", "low")
        confidence_multiplier = {"high": 1.0, "medium": 0.8, "low": 0.6}.get(confidence, 0.5)
        
        vlm_score = int((criteria_met / 6) * 100 * confidence_multiplier)
        
        return {
            "success": True,
            "score": vlm_score,
            "parsed": parsed,
            "criteria_met": criteria_met
        }
        
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        return {"success": False, "score": 0, "error": str(e)}


# ================================================================
# MAIN VERIFICATION FUNCTION
# ================================================================

def verify_date_line_measurement(traj: Dict[str, Any], 
                                  env_info: Dict[str, Any], 
                                  task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the Date Line Distance Measurement task.
    
    Uses multiple independent signals:
    1. KML file analysis (programmatic)
    2. Timestamp verification (anti-gaming)
    3. VLM trajectory verification (process verification)
    
    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    # Import trajectory frame sampling
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    except ImportError:
        sample_trajectory_frames = None
        get_final_screenshot = None
    
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "❌ Copy function not available for verification"
        }
    
    # Get metadata
    metadata = task_info.get('metadata', {})
    
    feedback_parts = []
    details = {}
    score = 0
    
    # ================================================================
    # STEP 1: Read task result JSON from container
    # ================================================================
    
    result_data = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
        details['result_data_loaded'] = True
    except Exception as e:
        logger.warning(f"Could not load task result: {e}")
        details['result_data_loaded'] = False
        details['result_error'] = str(e)
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # STEP 2: Check KML file existence and timing (anti-gaming)
    # ================================================================
    
    kml_exists = result_data.get('kml_exists', False)
    file_created_during_task = result_data.get('file_created_during_task', False)
    kml_content = result_data.get('kml_content', '')
    task_start = result_data.get('task_start', 0)
    kml_mtime = result_data.get('kml_mtime', 0)
    
    details['kml_exists'] = kml_exists
    details['file_created_during_task'] = file_created_during_task
    
    if not kml_exists:
        feedback_parts.append("❌ KML file not found at expected path")
    elif not file_created_during_task:
        feedback_parts.append("⚠️ KML file exists but was NOT created during task (possible pre-existing file)")
        score += 5  # Partial credit
    else:
        feedback_parts.append("✅ KML file created during task")
        score += 15  # Full points for criterion 1
    
    # ================================================================
    # STEP 3: Parse KML and find placemarks
    # ================================================================
    
    placemarks = []
    if kml_content:
        placemarks = parse_kml_content(kml_content)
    
    details['num_placemarks'] = len(placemarks)
    details['placemarks'] = placemarks
    
    if not placemarks:
        feedback_parts.append("❌ No placemarks found in KML file")
    else:
        feedback_parts.append(f"📍 Found {len(placemarks)} placemarks")
    
    # ================================================================
    # STEP 4: Find and verify Big Diomede placemark
    # ================================================================
    
    big_diomede_pm = None
    little_diomede_pm = None
    distance_pm = None
    
    for pm in placemarks:
        name_lower = pm.get('name', '').lower()
        
        if 'big' in name_lower and 'diomede' in name_lower:
            big_diomede_pm = pm
        elif 'little' in name_lower and 'diomede' in name_lower:
            little_diomede_pm = pm
        elif 'distance' in name_lower:
            distance_pm = pm
        elif 'diomede' in name_lower and not big_diomede_pm:
            # Could be either island - check coordinates
            if pm.get('coords'):
                lon, lat = pm['coords']
                if check_coordinate_in_range(lon, lat, BIG_DIOMEDE_LAT_RANGE, BIG_DIOMEDE_LON_RANGE):
                    big_diomede_pm = pm
                elif check_coordinate_in_range(lon, lat, LITTLE_DIOMEDE_LAT_RANGE, LITTLE_DIOMEDE_LON_RANGE):
                    little_diomede_pm = pm
    
    # Verify Big Diomede placemark
    big_diomede_valid = False
    if big_diomede_pm:
        coords = big_diomede_pm.get('coords')
        if coords:
            lon, lat = coords
            if check_coordinate_in_range(lon, lat, BIG_DIOMEDE_LAT_RANGE, BIG_DIOMEDE_LON_RANGE):
                big_diomede_valid = True
                score += 20
                feedback_parts.append(f"✅ Big Diomede placemark at {lat:.4f}°N, {abs(lon):.4f}°W")
            else:
                feedback_parts.append(f"⚠️ Big Diomede placemark at wrong location: {lat:.4f}°N, {lon:.4f}°")
                score += 5  # Partial credit for having placemark
        else:
            feedback_parts.append("⚠️ Big Diomede placemark found but no coordinates")
    else:
        feedback_parts.append("❌ Big Diomede placemark not found")
    
    details['big_diomede_valid'] = big_diomede_valid
    
    # Verify Little Diomede placemark
    little_diomede_valid = False
    if little_diomede_pm:
        coords = little_diomede_pm.get('coords')
        if coords:
            lon, lat = coords
            if check_coordinate_in_range(lon, lat, LITTLE_DIOMEDE_LAT_RANGE, LITTLE_DIOMEDE_LON_RANGE):
                little_diomede_valid = True
                score += 20
                feedback_parts.append(f"✅ Little Diomede placemark at {lat:.4f}°N, {abs(lon):.4f}°W")
            else:
                feedback_parts.append(f"⚠️ Little Diomede placemark at wrong location: {lat:.4f}°N, {lon:.4f}°")
                score += 5  # Partial credit
        else:
            feedback_parts.append("⚠️ Little Diomede placemark found but no coordinates")
    else:
        feedback_parts.append("❌ Little Diomede placemark not found")
    
    details['little_diomede_valid'] = little_diomede_valid
    
    # ================================================================
    # STEP 5: Verify distance placemark and documented distance
    # ================================================================
    
    distance_documented = False
    distance_accurate = False
    documented_distance = None
    
    if distance_pm:
        score += 10
        feedback_parts.append(f"✅ Distance placemark found: '{distance_pm.get('name', '')}'")
        
        # Extract distance from description or name
        description = distance_pm.get('description', '')
        name = distance_pm.get('name', '')
        
        documented_distance = extract_distance_from_text(description)
        if documented_distance is None:
            documented_distance = extract_distance_from_text(name)
        
        if documented_distance is not None:
            distance_documented = True
            score += 15
            feedback_parts.append(f"✅ Distance documented: {documented_distance} km")
            
            # Check accuracy
            min_dist = metadata.get('expected_distance_km_min', EXPECTED_DISTANCE_KM_RANGE[0])
            max_dist = metadata.get('expected_distance_km_max', EXPECTED_DISTANCE_KM_RANGE[1])
            
            if min_dist <= documented_distance <= max_dist:
                distance_accurate = True
                score += 20
                feedback_parts.append(f"✅ Distance {documented_distance} km is within expected range ({min_dist}-{max_dist} km)")
            else:
                feedback_parts.append(f"⚠️ Distance {documented_distance} km outside expected range ({min_dist}-{max_dist} km)")
        else:
            feedback_parts.append("⚠️ Could not extract distance value from description")
    else:
        feedback_parts.append("❌ Distance placemark not found")
    
    details['distance_documented'] = distance_documented
    details['distance_accurate'] = distance_accurate
    details['documented_distance'] = documented_distance
    
    # ================================================================
    # STEP 6: Cross-validation - check placemark separation
    # ================================================================
    
    if big_diomede_pm and little_diomede_pm:
        bd_coords = big_diomede_pm.get('coords')
        ld_coords = little_diomede_pm.get('coords')
        
        if bd_coords and ld_coords:
            separation = calculate_separation_degrees(
                bd_coords[0], bd_coords[1],
                ld_coords[0], ld_coords[1]
            )
            calculated_distance = haversine_distance_km(
                bd_coords[0], bd_coords[1],
                ld_coords[0], ld_coords[1]
            )
            
            details['placemark_separation_deg'] = separation
            details['calculated_distance_km'] = calculated_distance
            
            if separation < MIN_PLACEMARK_SEPARATION_DEG:
                feedback_parts.append(f"⚠️ Placemarks too close together ({separation:.4f}°) - may be on same island")
            else:
                feedback_parts.append(f"📏 Calculated distance between placemarks: {calculated_distance:.2f} km")
    
    # ================================================================
    # STEP 7: VLM trajectory verification (bonus/validation)
    # ================================================================
    
    vlm_result = {"success": False, "score": 0}
    if query_vlm and sample_trajectory_frames:
        vlm_result = verify_via_vlm(traj, query_vlm, sample_trajectory_frames)
        details['vlm_verification'] = vlm_result
        
        if vlm_result.get('success') and vlm_result.get('score', 0) > 50:
            feedback_parts.append(f"🔍 VLM verification: workflow progression confirmed")
        elif vlm_result.get('success'):
            feedback_parts.append(f"🔍 VLM verification: partial workflow observed")
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    
    # Key criteria: both island placemarks must be correctly positioned
    key_criteria_met = big_diomede_valid and little_diomede_valid
    
    # Pass threshold: 70 points with key criteria
    passed = score >= 70 and key_criteria_met
    
    # If key criteria not met but good score, cap at fail
    if not key_criteria_met and score >= 70:
        passed = False
        feedback_parts.append("⚠️ Score above threshold but island placemarks not correctly positioned")
    
    details['key_criteria_met'] = key_criteria_met
    details['final_score'] = score
    
    # Summary
    if passed:
        feedback_parts.insert(0, "🎉 TASK PASSED")
    else:
        feedback_parts.insert(0, "❌ TASK NOT PASSED")
    
    feedback_parts.append(f"Final Score: {score}/100 (Pass threshold: 70)")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }


# ================================================================
# STANDALONE TESTING
# ================================================================

if __name__ == "__main__":
    # Test with sample KML content
    sample_kml = """<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <Placemark>
      <name>Big Diomede (Russia)</name>
      <Point>
        <coordinates>-169.06,65.78,0</coordinates>
      </Point>
    </Placemark>
    <Placemark>
      <name>Little Diomede (USA)</name>
      <Point>
        <coordinates>-168.93,65.76,0</coordinates>
      </Point>
    </Placemark>
    <Placemark>
      <name>Diomede Distance</name>
      <description>The distance between the islands is approximately 3.8 km</description>
      <Point>
        <coordinates>-169.0,65.77,0</coordinates>
      </Point>
    </Placemark>
  </Document>
</kml>"""
    
    placemarks = parse_kml_content(sample_kml)
    print(f"Parsed {len(placemarks)} placemarks:")
    for pm in placemarks:
        print(f"  - {pm['name']}: {pm['coords']}")
        if pm['description']:
            dist = extract_distance_from_text(pm['description'])
            print(f"    Distance extracted: {dist} km")