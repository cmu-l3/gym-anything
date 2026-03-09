#!/usr/bin/env python3
"""
Verifier for Center Pivot Irrigation Assessment task.

MULTI-SIGNAL VERIFICATION:
1. KML file exists at expected path (15 points)
2. File was created during task - anti-gaming (15 points)
3. Placemark coordinates within expected area (15 points)
4. Placemark name correct (5 points)
5. Description contains diameter measurement (10 points)
6. Diameter measurement in expected range (20 points)
7. VLM trajectory: shows navigation to Kansas irrigation area (10 points)
8. VLM trajectory: shows measurement and placemark workflow (10 points)

Pass threshold: 70 points with KML file created during task
"""

import json
import tempfile
import os
import re
import xml.etree.ElementTree as ET
import logging
import zipfile
from typing import Dict, Any, Optional, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ================================================================
# KML PARSING UTILITIES
# ================================================================

def parse_kml_content(kml_content: str) -> list:
    """Parse KML content and extract placemark data."""
    if not kml_content or not kml_content.strip():
        return []
    
    try:
        # Remove namespace for easier parsing
        content = re.sub(r'xmlns="[^"]+"', '', kml_content)
        content = re.sub(r'xmlns:[^=]+="[^"]+"', '', content)
        
        root = ET.fromstring(content)
        
        placemarks = []
        # Search for Placemark elements at any depth
        for pm in root.iter('Placemark'):
            name_elem = pm.find('.//name')
            desc_elem = pm.find('.//description')
            coords_elem = pm.find('.//coordinates')
            
            placemark_data = {
                'name': name_elem.text.strip() if name_elem is not None and name_elem.text else None,
                'description': desc_elem.text.strip() if desc_elem is not None and desc_elem.text else None,
                'coordinates': None,
                'latitude': None,
                'longitude': None
            }
            
            if coords_elem is not None and coords_elem.text:
                coords_text = coords_elem.text.strip()
                # KML format: longitude,latitude,altitude
                parts = coords_text.split(',')
                if len(parts) >= 2:
                    try:
                        lon = float(parts[0].strip())
                        lat = float(parts[1].strip())
                        placemark_data['coordinates'] = (lat, lon)
                        placemark_data['latitude'] = lat
                        placemark_data['longitude'] = lon
                    except ValueError:
                        pass
            
            placemarks.append(placemark_data)
        
        return placemarks
    except ET.ParseError as e:
        logger.warning(f"KML parse error: {e}")
        return []
    except Exception as e:
        logger.warning(f"KML parsing exception: {e}")
        return []


def extract_diameter_from_description(description: str) -> Optional[float]:
    """Extract diameter measurement from description text."""
    if not description:
        return None
    
    # Look for patterns like "823 meters", "Diameter: 815m", "diameter 800 m", etc.
    patterns = [
        r'[Dd]iameter[:\s]+(\d+(?:\.\d+)?)\s*(?:meters?|m)\b',
        r'[Dd]iameter[:\s]+(\d+(?:\.\d+)?)\b',
        r'(\d+(?:\.\d+)?)\s*(?:meters?|m)\s*(?:diameter|diam)',
        r'(\d{3,4}(?:\.\d+)?)\s*(?:meters?|m)\b',  # 3-4 digit number followed by 'm' or 'meters'
        r'(\d{3,4}(?:\.\d+)?)\s*m\b',
    ]
    
    for pattern in patterns:
        match = re.search(pattern, description, re.IGNORECASE)
        if match:
            try:
                value = float(match.group(1))
                # Sanity check - diameter should be reasonable (100-2000m for irrigation)
                if 100 <= value <= 2000:
                    return value
            except ValueError:
                continue
    
    return None


def verify_coordinates_in_range(lat: float, lon: float, 
                                expected_lat: float, expected_lon: float, 
                                tolerance: float) -> bool:
    """Check if coordinates are within tolerance of expected location."""
    lat_ok = abs(lat - expected_lat) <= tolerance
    lon_ok = abs(lon - expected_lon) <= tolerance
    return lat_ok and lon_ok


# ================================================================
# VLM VERIFICATION
# ================================================================

TRAJECTORY_VERIFICATION_PROMPT = """You are analyzing screenshots from an agent performing a geographic documentation task in Google Earth Pro.

TASK: Navigate to Kansas (coordinates 37.9583, -100.6425), measure a center-pivot irrigation circle, and create a placemark.

Center-pivot irrigation fields appear as distinctive CIRCULAR GREEN PATTERNS in otherwise tan/brown agricultural land. They are created by rotating sprinkler systems and are very common in Kansas.

Analyze these trajectory screenshots and determine:

1. NAVIGATION_TO_KANSAS: Does any screenshot show the agent navigated to an agricultural region with circular irrigation patterns? Look for:
   - Search bar with coordinates or Kansas location
   - Satellite view of agricultural land with green circles
   - Flat terrain with grid patterns typical of US Midwest

2. IRRIGATION_CIRCLES_VISIBLE: Are circular irrigation fields visible in any screenshot? Look for:
   - Distinctive green circles against tan/brown background
   - Multiple adjacent circular patterns (common in Kansas)
   - Zoomed view showing the circular irrigation detail

3. RULER_TOOL_USED: Is there evidence of measurement being performed? Look for:
   - Ruler/measurement tool active in toolbar
   - Yellow/white measurement line drawn across circular feature
   - Distance readout displayed

4. PLACEMARK_CREATED: Is there evidence of placemark creation? Look for:
   - Placemark dialog/properties window open
   - Yellow pushpin icon visible on map
   - Name field being filled in

5. SAVE_DIALOG: Is there evidence of saving/exporting? Look for:
   - File save dialog
   - KML/KMZ file being saved
   - File browser showing Documents folder

Respond in JSON format:
{
    "navigation_to_kansas": true/false,
    "irrigation_circles_visible": true/false,
    "ruler_tool_used": true/false,
    "placemark_created": true/false,
    "save_dialog_shown": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what workflow steps you observed"
}
"""


def verify_via_vlm(traj: Dict[str, Any], query_vlm) -> Dict[str, Any]:
    """Verify task completion using VLM on trajectory frames."""
    if not query_vlm:
        return {"success": False, "error": "VLM not available"}
    
    try:
        # Import trajectory sampling utilities
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        # Sample frames across the trajectory (not just final)
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        
        if final and final not in frames:
            frames.append(final)
        
        if not frames:
            return {"success": False, "error": "No trajectory frames available"}
        
        # Query VLM with multiple frames
        result = query_vlm(
            prompt=TRAJECTORY_VERIFICATION_PROMPT,
            images=frames
        )
        
        if not result.get("success"):
            return {"success": False, "error": result.get("error", "VLM query failed")}
        
        parsed = result.get("parsed", {})
        return {
            "success": True,
            "parsed": parsed,
            "num_frames_analyzed": len(frames)
        }
        
    except ImportError:
        logger.warning("Could not import VLM utilities, skipping trajectory verification")
        return {"success": False, "error": "VLM utilities not available"}
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        return {"success": False, "error": str(e)}


# ================================================================
# MAIN VERIFICATION FUNCTION
# ================================================================

def verify_pivot_field_analysis(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the Center Pivot Irrigation Assessment task.
    
    Uses multiple verification signals:
    - File existence and timestamps (anti-gaming)
    - KML content parsing (coordinates, name, description)
    - VLM trajectory analysis (workflow verification)
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    expected_lat = metadata.get('target_coordinates', {}).get('latitude', 37.9583)
    expected_lon = metadata.get('target_coordinates', {}).get('longitude', -100.6425)
    coord_tolerance = metadata.get('coordinate_tolerance', 0.01)
    diameter_min = metadata.get('expected_diameter_min', 700)
    diameter_max = metadata.get('expected_diameter_max', 950)
    expected_name = metadata.get('expected_placemark_name', 'Pivot Field KC-2847')
    
    feedback_parts = []
    score = 0
    details = {}
    
    print("=" * 60)
    print("Center Pivot Irrigation Assessment - Verification")
    print("=" * 60)
    
    # ================================================================
    # STEP 1: Copy result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        details['result_json'] = result
    except Exception as e:
        logger.error(f"Failed to read result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # CRITERION 1: KML file exists (15 points)
    # ================================================================
    output_exists = result.get('output_exists', False)
    output_path = result.get('output_path', '')
    
    if output_exists:
        score += 15
        feedback_parts.append(f"✅ KML/KMZ file exists: {os.path.basename(output_path)}")
        details['file_exists'] = True
    else:
        feedback_parts.append("❌ No KML/KMZ file found at expected location")
        details['file_exists'] = False
        # Cannot verify further without file
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: File created during task - anti-gaming (15 points)
    # ================================================================
    file_created_during_task = result.get('file_created_during_task', False)
    task_start = result.get('task_start', 0)
    output_mtime = result.get('output_mtime', 0)
    
    if file_created_during_task:
        score += 15
        feedback_parts.append("✅ File created during task execution")
        details['created_during_task'] = True
    else:
        feedback_parts.append("⚠️ File may have existed before task (timestamp suspicious)")
        details['created_during_task'] = False
        # Partial credit if file exists but timestamp unclear
        score += 5
    
    # ================================================================
    # STEP 2: Parse KML content
    # ================================================================
    kml_content = result.get('kml_content', '')
    
    # Also try to copy the actual KML file for more reliable parsing
    temp_kml = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
    try:
        copy_from_env("/tmp/output_irrigation.kml", temp_kml.name)
        with open(temp_kml.name, 'r', encoding='utf-8') as f:
            kml_content = f.read()
    except Exception as e:
        logger.warning(f"Could not copy KML file directly: {e}")
        # Fall back to content from JSON
    finally:
        if os.path.exists(temp_kml.name):
            os.unlink(temp_kml.name)
    
    placemarks = parse_kml_content(kml_content)
    details['num_placemarks'] = len(placemarks)
    
    if not placemarks:
        feedback_parts.append("❌ No placemarks found in KML file")
        # Still check VLM
    else:
        feedback_parts.append(f"✅ Found {len(placemarks)} placemark(s)")
    
    # Find best matching placemark
    best_placemark = None
    for pm in placemarks:
        if pm.get('latitude') and pm.get('longitude'):
            if verify_coordinates_in_range(
                pm['latitude'], pm['longitude'],
                expected_lat, expected_lon, coord_tolerance
            ):
                best_placemark = pm
                break
    
    if not best_placemark and placemarks:
        best_placemark = placemarks[0]
    
    details['best_placemark'] = best_placemark
    
    if best_placemark:
        # ================================================================
        # CRITERION 3: Coordinates within expected area (15 points)
        # ================================================================
        lat = best_placemark.get('latitude')
        lon = best_placemark.get('longitude')
        
        if lat and lon:
            if verify_coordinates_in_range(lat, lon, expected_lat, expected_lon, coord_tolerance):
                score += 15
                feedback_parts.append(f"✅ Coordinates valid: {lat:.4f}, {lon:.4f}")
                details['coordinates_valid'] = True
            else:
                feedback_parts.append(f"⚠️ Coordinates outside expected area: {lat:.4f}, {lon:.4f}")
                details['coordinates_valid'] = False
                # Partial credit for having coordinates
                score += 5
        else:
            feedback_parts.append("❌ No coordinates in placemark")
            details['coordinates_valid'] = False
        
        # ================================================================
        # CRITERION 4: Placemark name correct (5 points)
        # ================================================================
        pm_name = best_placemark.get('name', '')
        if pm_name and expected_name.lower() in pm_name.lower():
            score += 5
            feedback_parts.append(f"✅ Placemark name correct: {pm_name}")
            details['name_correct'] = True
        elif pm_name:
            feedback_parts.append(f"⚠️ Placemark name: {pm_name} (expected: {expected_name})")
            details['name_correct'] = False
            score += 2  # Partial credit for having a name
        else:
            feedback_parts.append("❌ No placemark name")
            details['name_correct'] = False
        
        # ================================================================
        # CRITERION 5: Description contains diameter (10 points)
        # ================================================================
        description = best_placemark.get('description', '')
        diameter = extract_diameter_from_description(description)
        
        if diameter:
            score += 10
            feedback_parts.append(f"✅ Diameter measurement found: {diameter}m")
            details['diameter_found'] = True
            details['diameter_value'] = diameter
            
            # ================================================================
            # CRITERION 6: Diameter in expected range (20 points)
            # ================================================================
            if diameter_min <= diameter <= diameter_max:
                score += 20
                feedback_parts.append(f"✅ Diameter within expected range ({diameter_min}-{diameter_max}m)")
                details['diameter_accurate'] = True
            else:
                feedback_parts.append(f"⚠️ Diameter {diameter}m outside expected range")
                details['diameter_accurate'] = False
                # Partial credit for having a measurement
                score += 8
        else:
            feedback_parts.append("❌ Could not extract diameter from description")
            details['diameter_found'] = False
            if description:
                feedback_parts.append(f"   Description: {description[:100]}...")
    
    # ================================================================
    # CRITERIA 7-8: VLM Trajectory Verification (20 points total)
    # ================================================================
    if query_vlm:
        vlm_result = verify_via_vlm(traj, query_vlm)
        details['vlm_result'] = vlm_result
        
        if vlm_result.get('success'):
            parsed = vlm_result.get('parsed', {})
            
            # Navigation verified (10 points)
            nav_ok = parsed.get('navigation_to_kansas', False)
            circles_ok = parsed.get('irrigation_circles_visible', False)
            
            if nav_ok or circles_ok:
                score += 10
                feedback_parts.append("✅ VLM: Navigation to Kansas irrigation area verified")
                details['vlm_navigation'] = True
            else:
                feedback_parts.append("⚠️ VLM: Could not confirm navigation to target area")
                details['vlm_navigation'] = False
            
            # Workflow verified (10 points)
            ruler_ok = parsed.get('ruler_tool_used', False)
            placemark_ok = parsed.get('placemark_created', False)
            save_ok = parsed.get('save_dialog_shown', False)
            
            workflow_steps = sum([ruler_ok, placemark_ok, save_ok])
            if workflow_steps >= 2:
                score += 10
                feedback_parts.append(f"✅ VLM: Workflow steps verified ({workflow_steps}/3)")
                details['vlm_workflow'] = True
            elif workflow_steps >= 1:
                score += 5
                feedback_parts.append(f"⚠️ VLM: Partial workflow verified ({workflow_steps}/3)")
                details['vlm_workflow'] = False
            else:
                feedback_parts.append("⚠️ VLM: Could not verify workflow steps")
                details['vlm_workflow'] = False
            
            confidence = parsed.get('confidence', 'low')
            observations = parsed.get('observations', '')
            if observations:
                feedback_parts.append(f"   VLM observations ({confidence}): {observations[:150]}")
        else:
            feedback_parts.append(f"⚠️ VLM verification unavailable: {vlm_result.get('error', 'unknown')}")
    else:
        feedback_parts.append("⚠️ VLM not available for trajectory verification")
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    print("\n" + "=" * 60)
    print("VERIFICATION SUMMARY")
    print("=" * 60)
    
    for fb in feedback_parts:
        print(f"  {fb}")
    
    print(f"\nFinal Score: {score}/100")
    
    # Pass criteria: 70+ points AND file was created during task
    key_criteria_met = details.get('file_exists', False) and details.get('created_during_task', False)
    passed = score >= 70 and key_criteria_met
    
    if passed:
        print("RESULT: PASS ✅")
    else:
        print("RESULT: FAIL ❌")
        if not key_criteria_met:
            print("  (Key criteria not met: file must be created during task)")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }