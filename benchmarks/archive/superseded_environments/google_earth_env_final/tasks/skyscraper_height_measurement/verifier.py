#!/usr/bin/env python3
"""
Verifier for skyscraper_height_measurement task.

TASK: Measure the Empire State Building's height using Google Earth Pro's
3D view and ruler tool, then document the measurement in a placemark.

VERIFICATION STRATEGY (Multi-Signal):
1. Placemark file analysis - check if placemark was created with height data (30 pts)
2. Location verification - placemark near Empire State Building coords (25 pts)
3. Height documentation - measurement value in description (25 pts)
4. Height accuracy - measurement within acceptable range (10 pts)
5. VLM trajectory verification - evidence of 3D view and measurement (10 pts)

Anti-gaming:
- Check file modification timestamps
- Compare placemark counts before/after
- Use trajectory frames (not just final screenshot)
"""

import json
import tempfile
import os
import re
import logging
import xml.etree.ElementTree as ET
from math import radians, sin, cos, sqrt, atan2
from typing import Dict, Any, Optional, List, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ================================================================
# HELPER FUNCTIONS
# ================================================================

def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate distance between two points in kilometers."""
    R = 6371  # Earth radius in km
    dlat = radians(lat2 - lat1)
    dlon = radians(lon2 - lon1)
    a = sin(dlat/2)**2 + cos(radians(lat1)) * cos(radians(lat2)) * sin(dlon/2)**2
    c = 2 * atan2(sqrt(a), sqrt(1-a))
    return R * c


def parse_height_from_text(text: str) -> Optional[float]:
    """Extract height measurement from text. Returns height in meters or None."""
    if not text:
        return None
    
    text_lower = text.lower()
    
    # Patterns to match height measurements
    patterns = [
        # "Measured height: 400 meters"
        r'(?:measured\s+)?height[:\s]+(\d+(?:\.\d+)?)\s*(?:m|meters?|metres?)\b',
        # "400 meters" or "400m"
        r'(\d+(?:\.\d+)?)\s*(?:m|meters?|metres?)\b',
        # "height: 400"
        r'height[:\s]+(\d+(?:\.\d+)?)',
        # "400 m tall/high"
        r'(\d+(?:\.\d+)?)\s*(?:m|meters?)\s*(?:tall|high)',
    ]
    
    for pattern in patterns:
        match = re.search(pattern, text_lower)
        if match:
            try:
                height = float(match.group(1))
                # Sanity check - building heights are typically 10-1000m
                if 10 <= height <= 1000:
                    return height
            except (ValueError, IndexError):
                continue
    
    return None


def parse_kml_placemarks(kml_content: str) -> List[Dict[str, Any]]:
    """Parse KML content and extract placemark information."""
    placemarks = []
    
    try:
        root = ET.fromstring(kml_content)
        
        # Handle KML namespace
        namespaces = {
            'kml': 'http://www.opengis.net/kml/2.2',
            '': 'http://www.opengis.net/kml/2.2'
        }
        
        # Try with namespace first
        pm_elements = root.findall('.//{http://www.opengis.net/kml/2.2}Placemark')
        
        # Fallback without namespace
        if not pm_elements:
            pm_elements = root.findall('.//Placemark')
        
        for pm in pm_elements:
            placemark = {}
            
            # Get name
            name_elem = pm.find('{http://www.opengis.net/kml/2.2}name')
            if name_elem is None:
                name_elem = pm.find('name')
            placemark['name'] = name_elem.text if name_elem is not None and name_elem.text else ""
            
            # Get description
            desc_elem = pm.find('{http://www.opengis.net/kml/2.2}description')
            if desc_elem is None:
                desc_elem = pm.find('description')
            placemark['description'] = desc_elem.text if desc_elem is not None and desc_elem.text else ""
            
            # Get coordinates
            coord_elem = pm.find('.//{http://www.opengis.net/kml/2.2}coordinates')
            if coord_elem is None:
                coord_elem = pm.find('.//coordinates')
            
            if coord_elem is not None and coord_elem.text:
                coords_text = coord_elem.text.strip()
                # Format: lon,lat,alt or lon,lat
                parts = coords_text.split(',')
                if len(parts) >= 2:
                    try:
                        placemark['longitude'] = float(parts[0])
                        placemark['latitude'] = float(parts[1])
                        placemark['altitude'] = float(parts[2]) if len(parts) > 2 else 0
                    except ValueError:
                        pass
            
            placemarks.append(placemark)
            
    except ET.ParseError as e:
        logger.warning(f"KML parse error: {e}")
    except Exception as e:
        logger.warning(f"Error parsing KML: {e}")
    
    return placemarks


def find_empire_state_placemark(placemarks: List[Dict], target_lat: float, target_lon: float, 
                                 tolerance_km: float, name_keywords: List[str]) -> Tuple[Optional[Dict], List[str]]:
    """Find placemark that matches Empire State Building criteria."""
    details = []
    
    for pm in placemarks:
        name = pm.get('name', '').lower()
        desc = pm.get('description', '').lower()
        
        # Check if name contains relevant keywords
        name_match = any(kw in name for kw in name_keywords)
        
        if name_match:
            details.append(f"Found placemark with matching name: '{pm.get('name', '')}'")
            
            # Check location
            if 'latitude' in pm and 'longitude' in pm:
                distance = haversine_distance(
                    pm['latitude'], pm['longitude'],
                    target_lat, target_lon
                )
                pm['distance_km'] = distance
                
                if distance <= tolerance_km:
                    details.append(f"Location verified: {distance:.3f}km from target")
                    return pm, details
                else:
                    details.append(f"Location too far: {distance:.2f}km from target (max {tolerance_km}km)")
            else:
                details.append("Placemark has no coordinates")
                # Still return it if name matches (partial credit)
                return pm, details
    
    return None, details


# ================================================================
# VLM VERIFICATION
# ================================================================

TRAJECTORY_VERIFICATION_PROMPT = """You are analyzing screenshots from an agent performing a building height measurement task in Google Earth Pro.

TASK: Navigate to Empire State Building, enable 3D buildings, use ruler tool to measure height, create placemark with measurement.

Examine these trajectory screenshots (chronological order, earliest to latest) and assess:

1. GOOGLE_EARTH_VISIBLE: Is Google Earth Pro visible (satellite imagery, globe view)?
2. NYC_AREA_SHOWN: Does any frame show New York City / Manhattan area?
3. BUILDING_3D_VIEW: Is there a 3D tilted view showing buildings with height?
4. RULER_TOOL_USED: Is there evidence of the ruler/measurement tool being used?
5. PLACEMARK_CREATION: Is there a placemark creation dialog or placemark visible?
6. MEANINGFUL_WORKFLOW: Do frames show progression through the task steps?

Respond in JSON format:
{
    "google_earth_visible": true/false,
    "nyc_area_shown": true/false,
    "building_3d_view": true/false,
    "ruler_tool_used": true/false,
    "placemark_creation": true/false,
    "meaningful_workflow": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see in the trajectory"
}
"""


def verify_via_vlm(traj: Dict[str, Any], query_vlm) -> Tuple[int, List[str]]:
    """Verify task completion using VLM on trajectory frames."""
    score = 0
    details = []
    
    if not query_vlm:
        details.append("VLM not available")
        return 0, details
    
    # Import trajectory sampling utilities
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    except ImportError:
        # Fallback: try to get frames from traj directly
        details.append("Could not import VLM utilities")
        return 0, details
    
    # Sample trajectory frames (not just final screenshot!)
    try:
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        
        if final and final not in frames:
            frames.append(final)
        
        if not frames:
            details.append("No trajectory frames available")
            return 0, details
        
        details.append(f"Analyzing {len(frames)} trajectory frames")
        
    except Exception as e:
        details.append(f"Error getting trajectory frames: {e}")
        return 0, details
    
    # Query VLM with trajectory frames
    try:
        vlm_result = query_vlm(
            prompt=TRAJECTORY_VERIFICATION_PROMPT,
            images=frames
        )
        
        if not vlm_result.get("success"):
            details.append(f"VLM query failed: {vlm_result.get('error', 'unknown')}")
            return 0, details
        
        parsed = vlm_result.get("parsed", {})
        
        # Score based on VLM findings
        if parsed.get("google_earth_visible"):
            score += 2
            details.append("✓ VLM: Google Earth visible")
        
        if parsed.get("nyc_area_shown"):
            score += 2
            details.append("✓ VLM: NYC area shown")
        
        if parsed.get("building_3d_view"):
            score += 2
            details.append("✓ VLM: 3D building view detected")
        
        if parsed.get("ruler_tool_used"):
            score += 2
            details.append("✓ VLM: Ruler tool usage detected")
        
        if parsed.get("placemark_creation"):
            score += 1
            details.append("✓ VLM: Placemark creation detected")
        
        if parsed.get("meaningful_workflow"):
            score += 1
            details.append("✓ VLM: Meaningful workflow progression")
        
        confidence = parsed.get("confidence", "low")
        details.append(f"VLM confidence: {confidence}")
        
        if parsed.get("observations"):
            details.append(f"VLM observations: {parsed['observations'][:200]}")
            
    except Exception as e:
        details.append(f"VLM verification error: {e}")
    
    return score, details


# ================================================================
# MAIN VERIFICATION FUNCTION
# ================================================================

def verify_skyscraper_height_measurement(traj: Dict[str, Any], env_info: Dict[str, Any], 
                                          task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that the agent measured the Empire State Building height and created a placemark.
    
    Uses multiple independent signals for robust verification.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }
    
    # Get task metadata
    metadata = task_info.get('metadata', {})
    target_lat = metadata.get('target_latitude', 40.7484)
    target_lon = metadata.get('target_longitude', -73.9857)
    tolerance_km = metadata.get('location_tolerance_km', 1.0)
    height_min = metadata.get('height_range_min_meters', 320)
    height_max = metadata.get('height_range_max_meters', 480)
    name_keywords = metadata.get('expected_placemark_name_keywords', ['empire', 'state', 'height'])
    
    score = 0
    feedback_parts = []
    result_details = {}
    
    # ================================================================
    # STEP 1: Copy and parse task result JSON
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
        result_details['task_result'] = task_result
    except Exception as e:
        logger.warning(f"Could not read task result: {e}")
        task_result = {}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # STEP 2: Anti-gaming checks
    # ================================================================
    myplaces_modified = task_result.get('myplaces_modified', False)
    new_placemarks_created = task_result.get('new_placemarks_created', False)
    task_start = task_result.get('task_start', 0)
    task_end = task_result.get('task_end', 0)
    
    if not myplaces_modified and not new_placemarks_created:
        feedback_parts.append("⚠ No placemark file changes detected during task")
    else:
        feedback_parts.append("✓ Placemark file modified during task")
    
    # ================================================================
    # STEP 3: Copy and analyze myplaces.kml
    # ================================================================
    placemark_found = False
    correct_location = False
    height_documented = False
    height_accurate = False
    measured_height = None
    distance_km = None
    
    temp_kml = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
    try:
        copy_from_env("/tmp/myplaces_export.kml", temp_kml.name)
        
        with open(temp_kml.name, 'r', encoding='utf-8', errors='ignore') as f:
            kml_content = f.read()
        
        if kml_content:
            placemarks = parse_kml_placemarks(kml_content)
            result_details['total_placemarks'] = len(placemarks)
            
            # Find the Empire State Building placemark
            matching_pm, pm_details = find_empire_state_placemark(
                placemarks, target_lat, target_lon, tolerance_km, name_keywords
            )
            feedback_parts.extend(pm_details)
            
            if matching_pm:
                placemark_found = True
                result_details['matching_placemark'] = matching_pm
                
                # Check location
                if 'distance_km' in matching_pm:
                    distance_km = matching_pm['distance_km']
                    if distance_km <= tolerance_km:
                        correct_location = True
                
                # Check for height in name or description
                name_text = matching_pm.get('name', '')
                desc_text = matching_pm.get('description', '')
                combined_text = f"{name_text} {desc_text}"
                
                measured_height = parse_height_from_text(combined_text)
                
                if measured_height:
                    height_documented = True
                    result_details['measured_height'] = measured_height
                    feedback_parts.append(f"Height documented: {measured_height}m")
                    
                    if height_min <= measured_height <= height_max:
                        height_accurate = True
                        feedback_parts.append(f"✓ Height within acceptable range ({height_min}-{height_max}m)")
                    else:
                        feedback_parts.append(f"⚠ Height outside acceptable range")
                else:
                    feedback_parts.append("⚠ No height measurement found in placemark")
            else:
                feedback_parts.append("✗ No matching placemark found")
        else:
            feedback_parts.append("✗ Empty or missing myplaces.kml")
            
    except FileNotFoundError:
        feedback_parts.append("✗ Myplaces file not found - no placemark created")
    except Exception as e:
        feedback_parts.append(f"⚠ Error reading placemark file: {e}")
    finally:
        if os.path.exists(temp_kml.name):
            os.unlink(temp_kml.name)
    
    # ================================================================
    # STEP 4: Calculate programmatic score
    # ================================================================
    
    # Criterion 1: Placemark exists with relevant name (30 pts)
    if placemark_found:
        score += 30
        feedback_parts.append("✓ Placemark created (+30)")
    else:
        feedback_parts.append("✗ No placemark created")
    
    # Criterion 2: Correct location (25 pts)
    if correct_location:
        score += 25
        feedback_parts.append("✓ Location correct (+25)")
    elif placemark_found:
        # Partial credit if placemark exists but location is wrong/missing
        score += 5
        feedback_parts.append("⚠ Placemark exists but location not verified (+5)")
    
    # Criterion 3: Height documented (25 pts)
    if height_documented:
        score += 25
        feedback_parts.append(f"✓ Height documented: {measured_height}m (+25)")
    
    # Criterion 4: Height accuracy (10 pts)
    if height_accurate:
        score += 10
        feedback_parts.append("✓ Height measurement accurate (+10)")
    
    # ================================================================
    # STEP 5: VLM trajectory verification (10 pts max)
    # ================================================================
    if query_vlm:
        vlm_score, vlm_details = verify_via_vlm(traj, query_vlm)
        score += vlm_score
        feedback_parts.extend(vlm_details)
        if vlm_score > 0:
            feedback_parts.append(f"VLM verification: +{vlm_score}")
    else:
        feedback_parts.append("VLM verification skipped (not available)")
    
    # ================================================================
    # STEP 6: Determine pass/fail
    # ================================================================
    # Pass requires: score >= 55 AND placemark created
    passed = score >= 55 and placemark_found
    
    result_details['distance_from_target_km'] = distance_km
    result_details['measured_height'] = measured_height
    result_details['placemark_found'] = placemark_found
    result_details['correct_location'] = correct_location
    result_details['height_documented'] = height_documented
    result_details['height_accurate'] = height_accurate
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "details": result_details
    }