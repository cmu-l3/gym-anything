#!/usr/bin/env python3
"""
Verifier for custom_placemark_style task.

TASK: Create a custom-styled placemark at the Chrysler Building in NYC with:
- Name: "NYC Regional Office"
- Icon: Office/building icon
- Color: Blue
- Description containing "Regional headquarters" and "Eastern Division"
- View altitude between 500-2000 meters

VERIFICATION STRATEGY:
1. PRIMARY: Parse myplaces.kml file for placemark data (60 points)
   - Placemark exists with correct name (15 pts)
   - Correct location near Chrysler Building (15 pts)
   - Blue icon color (15 pts)
   - Correct description text (15 pts)

2. SECONDARY: File modification timestamp check (10 points)
   - KML file was modified during task (anti-gaming)

3. TERTIARY: VLM trajectory verification (20 points)
   - Verify agent performed placemark creation workflow
   - Check for placemark dialog, icon selection, etc.

4. BONUS: View altitude and icon type (10 points)
   - LookAt range in acceptable range (5 pts)
   - Icon is building/office type (5 pts)

Pass threshold: 60 points with placemark found and location correct as mandatory
"""

import json
import tempfile
import os
import logging
import xml.etree.ElementTree as ET
from typing import Dict, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def is_blue_color(color_str: str) -> bool:
    """
    Check if a KML color string represents blue.
    KML colors are in AABBGGRR format (Alpha, Blue, Green, Red).
    For blue: the BB component should be high relative to RR.
    """
    if not color_str:
        return False
    
    color_str = color_str.strip().lower().replace('#', '')
    
    # KML uses AABBGGRR format
    if len(color_str) == 8:
        try:
            # aa = alpha, bb = blue, gg = green, rr = red
            bb = int(color_str[2:4], 16)  # Blue channel
            gg = int(color_str[4:6], 16)  # Green channel
            rr = int(color_str[6:8], 16)  # Red channel
            
            # For blue color: blue should be dominant
            # Allow various shades of blue
            is_blue = bb > 100 and bb > rr and (bb > gg or abs(bb - gg) < 50)
            
            logger.info(f"Color analysis: BB={bb}, GG={gg}, RR={rr}, is_blue={is_blue}")
            return is_blue
        except ValueError:
            return False
    
    return False


def check_coordinates(lat: float, lon: float, 
                     target_lat: float = 40.7516, 
                     target_lon: float = -73.9755, 
                     tolerance: float = 0.005) -> bool:
    """Check if coordinates are within tolerance of Chrysler Building."""
    lat_ok = abs(lat - target_lat) <= tolerance
    lon_ok = abs(lon - target_lon) <= tolerance
    return lat_ok and lon_ok


def parse_kml_for_placemark(kml_content: str, placemark_name: str = "NYC Regional Office") -> Dict[str, Any]:
    """Parse KML content to find and analyze the target placemark."""
    result = {
        "found": False,
        "name": "",
        "latitude": 0.0,
        "longitude": 0.0,
        "icon_color": "",
        "description": "",
        "lookat_range": 0.0,
        "icon_href": "",
        "parse_error": None
    }
    
    try:
        root = ET.fromstring(kml_content)
    except ET.ParseError as e:
        result["parse_error"] = str(e)
        return result
    
    # Try both with and without namespace
    namespaces = [
        '{http://www.opengis.net/kml/2.2}',
        '{http://earth.google.com/kml/2.2}',
        '{http://earth.google.com/kml/2.1}',
        ''
    ]
    
    for ns in namespaces:
        placemarks = root.findall(f'.//{ns}Placemark')
        if placemarks:
            break
    
    if not placemarks:
        logger.warning("No placemarks found in KML")
        return result
    
    for pm in placemarks:
        # Find name element
        name_elem = None
        for ns in namespaces:
            name_elem = pm.find(f'{ns}name')
            if name_elem is not None:
                break
        
        if name_elem is None or not name_elem.text:
            continue
        
        pm_name = name_elem.text.strip()
        
        # Check if this is our target placemark
        if placemark_name.lower() in pm_name.lower():
            result["found"] = True
            result["name"] = pm_name
            
            # Get coordinates
            for ns in namespaces:
                coords_elem = pm.find(f'.//{ns}coordinates')
                if coords_elem is not None and coords_elem.text:
                    coords = coords_elem.text.strip().split(',')
                    if len(coords) >= 2:
                        try:
                            result["longitude"] = float(coords[0])
                            result["latitude"] = float(coords[1])
                        except ValueError:
                            pass
                    break
            
            # Get icon color
            for ns in namespaces:
                icon_style = pm.find(f'.//{ns}IconStyle')
                if icon_style is not None:
                    color_elem = icon_style.find(f'{ns}color')
                    if color_elem is not None and color_elem.text:
                        result["icon_color"] = color_elem.text.strip()
                    break
            
            # Get icon href
            for ns in namespaces:
                icon = pm.find(f'.//{ns}Icon')
                if icon is not None:
                    href = icon.find(f'{ns}href')
                    if href is not None and href.text:
                        result["icon_href"] = href.text.strip()
                    break
            
            # Get description
            for ns in namespaces:
                desc_elem = pm.find(f'{ns}description')
                if desc_elem is not None and desc_elem.text:
                    result["description"] = desc_elem.text.strip()
                    break
            
            # Get LookAt range
            for ns in namespaces:
                lookat = pm.find(f'.//{ns}LookAt')
                if lookat is not None:
                    range_elem = lookat.find(f'{ns}range')
                    if range_elem is not None and range_elem.text:
                        try:
                            result["lookat_range"] = float(range_elem.text)
                        except ValueError:
                            pass
                    break
            
            break  # Found our placemark, stop searching
    
    return result


def verify_via_vlm(traj: Dict[str, Any], query_vlm) -> Dict[str, Any]:
    """Use VLM to verify agent workflow via trajectory frames."""
    
    # Import trajectory sampling helper
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    except ImportError:
        logger.warning("Could not import VLM helpers")
        return {"success": False, "score": 0, "error": "VLM helpers not available"}
    
    # Sample frames across the trajectory
    frames = sample_trajectory_frames(traj, n=5)
    final = get_final_screenshot(traj)
    
    if not frames and not final:
        return {"success": False, "score": 0, "error": "No screenshots available"}
    
    all_images = frames + ([final] if final else [])
    
    prompt = """You are verifying if an agent created a custom placemark in Google Earth Pro.

The task was to:
1. Navigate to the Chrysler Building in New York City
2. Create a placemark named "NYC Regional Office"
3. Set a blue icon color
4. Add a description about "Regional headquarters - Eastern Division"

Look at these screenshots (in chronological order) and determine:

1. Did the agent open Google Earth Pro?
2. Did the agent navigate to New York City area?
3. Did the agent open the Add Placemark dialog (a dialog box with name, description, icon options)?
4. Did the agent appear to configure placemark settings (icon style, color, description)?
5. Is there evidence of a placemark being created (pin/marker visible on map)?

Respond in JSON format:
{
    "google_earth_visible": true/false,
    "nyc_navigation": true/false,
    "placemark_dialog_opened": true/false,
    "settings_configured": true/false,
    "placemark_created": true/false,
    "workflow_score": 0-100,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you observed"
}
"""
    
    try:
        vlm_result = query_vlm(prompt=prompt, images=all_images)
        
        if not vlm_result.get("success"):
            return {"success": False, "score": 0, "error": vlm_result.get("error", "VLM query failed")}
        
        parsed = vlm_result.get("parsed", {})
        
        # Calculate VLM score based on workflow steps observed
        vlm_score = 0
        if parsed.get("google_earth_visible"):
            vlm_score += 4
        if parsed.get("nyc_navigation"):
            vlm_score += 4
        if parsed.get("placemark_dialog_opened"):
            vlm_score += 4
        if parsed.get("settings_configured"):
            vlm_score += 4
        if parsed.get("placemark_created"):
            vlm_score += 4
        
        # Adjust by confidence
        confidence = parsed.get("confidence", "low")
        if confidence == "high":
            vlm_score = vlm_score
        elif confidence == "medium":
            vlm_score = int(vlm_score * 0.9)
        else:
            vlm_score = int(vlm_score * 0.7)
        
        return {
            "success": True,
            "score": vlm_score,
            "details": parsed
        }
        
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        return {"success": False, "score": 0, "error": str(e)}


def verify_custom_placemark_style(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Main verification function for custom_placemark_style task.
    
    Uses multiple independent signals:
    1. KML file parsing for placemark data
    2. Timestamp checks for anti-gaming
    3. VLM trajectory verification for workflow
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
    target_lat = metadata.get('target_latitude', 40.7516)
    target_lon = metadata.get('target_longitude', -73.9755)
    coord_tolerance = metadata.get('coordinate_tolerance', 0.005)
    required_terms = metadata.get('required_description_terms', ['Regional headquarters', 'Eastern Division'])
    min_altitude = metadata.get('min_altitude', 500)
    max_altitude = metadata.get('max_altitude', 2000)
    
    feedback_parts = []
    details = {}
    score = 0
    max_score = 100
    
    # ================================================================
    # STEP 1: Get task result JSON from container
    # ================================================================
    result_data = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
        details["result_data"] = result_data
    except Exception as e:
        logger.warning(f"Could not read task result: {e}")
        details["result_error"] = str(e)
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # STEP 2: Get and parse myplaces.kml
    # ================================================================
    kml_content = None
    placemark_data = {"found": False}
    
    temp_kml = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
    try:
        copy_from_env("/tmp/myplaces_final.kml", temp_kml.name)
        with open(temp_kml.name, 'r', encoding='utf-8', errors='ignore') as f:
            kml_content = f.read()
        details["kml_retrieved"] = True
    except Exception as e:
        logger.warning(f"Could not retrieve KML: {e}")
        details["kml_retrieved"] = False
        details["kml_error"] = str(e)
    finally:
        if os.path.exists(temp_kml.name):
            os.unlink(temp_kml.name)
    
    if kml_content:
        placemark_data = parse_kml_for_placemark(kml_content, "NYC Regional Office")
        details["placemark_data"] = placemark_data
    
    # ================================================================
    # CRITERION 1: Placemark exists with correct name (15 points)
    # ================================================================
    if placemark_data.get("found"):
        score += 15
        feedback_parts.append("✅ Placemark 'NYC Regional Office' found")
        details["placemark_found"] = True
    else:
        feedback_parts.append("❌ Placemark 'NYC Regional Office' NOT found")
        details["placemark_found"] = False
        # If placemark not found, check result data for info
        if result_data.get("placemark_found"):
            score += 10  # Partial credit if export script found it
            feedback_parts[-1] = "⚠️ Placemark found by export script but not in parsed KML"
    
    # ================================================================
    # CRITERION 2: Correct location near Chrysler Building (15 points)
    # ================================================================
    lat = placemark_data.get("latitude", 0)
    lon = placemark_data.get("longitude", 0)
    
    if lat != 0 and lon != 0:
        if check_coordinates(lat, lon, target_lat, target_lon, coord_tolerance):
            score += 15
            feedback_parts.append(f"✅ Location correct ({lat:.4f}, {lon:.4f})")
            details["location_correct"] = True
        else:
            # Check if it's at least in NYC area (larger tolerance)
            if check_coordinates(lat, lon, target_lat, target_lon, 0.1):
                score += 8
                feedback_parts.append(f"⚠️ Location in NYC but not at Chrysler Building ({lat:.4f}, {lon:.4f})")
            else:
                feedback_parts.append(f"❌ Location incorrect ({lat:.4f}, {lon:.4f})")
            details["location_correct"] = False
    else:
        feedback_parts.append("❌ No coordinates found for placemark")
        details["location_correct"] = False
    
    # ================================================================
    # CRITERION 3: Blue icon color (15 points)
    # ================================================================
    icon_color = placemark_data.get("icon_color", "")
    if icon_color:
        if is_blue_color(icon_color):
            score += 15
            feedback_parts.append(f"✅ Icon color is blue ({icon_color})")
            details["color_correct"] = True
        else:
            score += 5  # Partial credit for having a custom color
            feedback_parts.append(f"⚠️ Icon color set but not blue ({icon_color})")
            details["color_correct"] = False
    else:
        feedback_parts.append("❌ No icon color found (default used)")
        details["color_correct"] = False
    
    # ================================================================
    # CRITERION 4: Correct description text (15 points)
    # ================================================================
    description = placemark_data.get("description", "").lower()
    terms_found = []
    for term in required_terms:
        if term.lower() in description:
            terms_found.append(term)
    
    if len(terms_found) == len(required_terms):
        score += 15
        feedback_parts.append("✅ Description contains all required terms")
        details["description_complete"] = True
    elif len(terms_found) > 0:
        partial_score = int(15 * len(terms_found) / len(required_terms))
        score += partial_score
        feedback_parts.append(f"⚠️ Description has {len(terms_found)}/{len(required_terms)} required terms")
        details["description_complete"] = "partial"
        details["terms_found"] = terms_found
    else:
        if description:
            score += 3  # Small credit for having any description
            feedback_parts.append("⚠️ Description present but missing required terms")
        else:
            feedback_parts.append("❌ No description found")
        details["description_complete"] = False
    
    # ================================================================
    # CRITERION 5: File modified during task - anti-gaming (10 points)
    # ================================================================
    task_start = result_data.get("task_start", 0)
    myplaces_mtime = result_data.get("myplaces_mtime", 0)
    myplaces_modified = result_data.get("myplaces_modified_during_task", False)
    
    if myplaces_modified or (myplaces_mtime > task_start > 0):
        score += 10
        feedback_parts.append("✅ KML file modified during task")
        details["file_modified_during_task"] = True
    else:
        feedback_parts.append("⚠️ Could not verify file was modified during task")
        details["file_modified_during_task"] = False
    
    # ================================================================
    # CRITERION 6: VLM trajectory verification (20 points)
    # ================================================================
    if query_vlm:
        vlm_result = verify_via_vlm(traj, query_vlm)
        details["vlm_verification"] = vlm_result
        
        if vlm_result.get("success"):
            vlm_score = vlm_result.get("score", 0)
            score += vlm_score
            
            vlm_details = vlm_result.get("details", {})
            if vlm_score >= 15:
                feedback_parts.append(f"✅ VLM verified workflow ({vlm_score}/20 pts)")
            elif vlm_score >= 8:
                feedback_parts.append(f"⚠️ VLM partial workflow verification ({vlm_score}/20 pts)")
            else:
                feedback_parts.append(f"❌ VLM workflow verification weak ({vlm_score}/20 pts)")
        else:
            feedback_parts.append("⚠️ VLM verification unavailable")
    else:
        feedback_parts.append("⚠️ VLM not available for trajectory verification")
        details["vlm_verification"] = {"available": False}
    
    # ================================================================
    # CRITERION 7: View altitude (5 points - bonus)
    # ================================================================
    lookat_range = placemark_data.get("lookat_range", 0)
    if lookat_range > 0:
        if min_altitude <= lookat_range <= max_altitude:
            score += 5
            feedback_parts.append(f"✅ View altitude correct ({lookat_range:.0f}m)")
            details["altitude_correct"] = True
        else:
            feedback_parts.append(f"⚠️ View altitude outside range ({lookat_range:.0f}m, expected {min_altitude}-{max_altitude}m)")
            details["altitude_correct"] = False
    else:
        details["altitude_correct"] = None
    
    # ================================================================
    # CRITERION 8: Icon type (5 points - bonus)
    # ================================================================
    icon_href = placemark_data.get("icon_href", "").lower()
    building_indicators = ['office', 'building', 'business', 'pal4', 'pal3', 'pushpin']
    if any(ind in icon_href for ind in building_indicators):
        score += 5
        feedback_parts.append("✅ Building/office icon type detected")
        details["icon_type_correct"] = True
    elif icon_href:
        feedback_parts.append(f"⚠️ Custom icon used: {icon_href[:50]}...")
        details["icon_type_correct"] = False
    
    # ================================================================
    # Final scoring and pass/fail determination
    # ================================================================
    
    # Key criteria that MUST be met for passing
    key_criteria_met = (
        details.get("placemark_found", False) and
        details.get("location_correct", False)
    )
    
    # Cap score at 100
    score = min(score, max_score)
    
    # Determine pass/fail
    # Need 60+ points AND key criteria (placemark exists at correct location)
    passed = score >= 60 and key_criteria_met
    
    # Build final feedback
    feedback = " | ".join(feedback_parts)
    feedback += f" | Final Score: {score}/{max_score}"
    
    if passed:
        feedback = f"✅ PASSED: {feedback}"
    else:
        if not key_criteria_met:
            feedback = f"❌ FAILED (missing key criteria): {feedback}"
        else:
            feedback = f"❌ FAILED (score too low): {feedback}"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }