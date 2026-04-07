#!/usr/bin/env python3
"""
Verifier for Stadium Field Dimension Measurement task.

VERIFICATION STRATEGY:
1. KML file exists and was created during task (15 points)
2. KML contains valid XML with placemarks (15 points)
3. Placemarks have correct corner names (10 points)
4. Placemark coordinates within Camp Nou bounds (10 points)
5. Text file exists and was created during task (10 points)
6. Length measurement recorded and accurate (15 points)
7. Width measurement recorded and accurate (15 points)
8. FIFA compliance noted (5 points)
9. VLM trajectory verification - shows measurement workflow (5 points)

ANTI-GAMING:
- File timestamps must be after task start
- Coordinates must be within Camp Nou stadium bounds
- Measurements must be within tolerance of known values

Pass threshold: 70 points with at least one measurement AND KML export
"""

import json
import tempfile
import os
import logging
import base64
import xml.etree.ElementTree as ET
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_kml_content(kml_base64):
    """Parse KML content from base64 and extract placemark data."""
    result = {
        "valid_xml": False,
        "has_folder": False,
        "folder_name": "",
        "placemarks": [],
        "placemark_count": 0,
        "coordinates_in_bounds": 0
    }
    
    if not kml_base64:
        return result
    
    try:
        kml_content = base64.b64decode(kml_base64).decode('utf-8')
    except Exception as e:
        logger.warning(f"Failed to decode KML base64: {e}")
        return result
    
    try:
        # Remove any BOM or whitespace
        kml_content = kml_content.strip()
        if kml_content.startswith('\ufeff'):
            kml_content = kml_content[1:]
        
        root = ET.fromstring(kml_content)
        result["valid_xml"] = True
    except ET.ParseError as e:
        logger.warning(f"KML XML parse error: {e}")
        return result
    
    # Handle KML namespace
    ns = {'kml': 'http://www.opengis.net/kml/2.2'}
    
    # Find folders
    folders = root.findall('.//kml:Folder', ns)
    if not folders:
        folders = root.findall('.//Folder')
    
    for folder in folders:
        name_elem = folder.find('kml:name', ns) or folder.find('name')
        if name_elem is not None:
            folder_name = name_elem.text or ""
            if 'camp nou' in folder_name.lower():
                result["has_folder"] = True
                result["folder_name"] = folder_name
                break
    
    # Find all placemarks
    placemarks = root.findall('.//kml:Placemark', ns)
    if not placemarks:
        placemarks = root.findall('.//Placemark')
    
    # Camp Nou bounds (approximate stadium area)
    bounds = {
        "lat_min": 41.378,
        "lat_max": 41.384,
        "lon_min": 2.119,
        "lon_max": 2.127
    }
    
    for pm in placemarks:
        pm_data = {"name": "", "lat": None, "lon": None, "in_bounds": False}
        
        name_elem = pm.find('kml:name', ns) or pm.find('name')
        if name_elem is not None:
            pm_data["name"] = name_elem.text or ""
        
        # Find coordinates
        point = pm.find('.//kml:Point', ns) or pm.find('.//Point')
        if point is not None:
            coord_elem = point.find('kml:coordinates', ns) or point.find('coordinates')
            if coord_elem is not None and coord_elem.text:
                parts = coord_elem.text.strip().split(',')
                if len(parts) >= 2:
                    try:
                        pm_data["lon"] = float(parts[0])
                        pm_data["lat"] = float(parts[1])
                        
                        # Check bounds
                        if (bounds["lat_min"] <= pm_data["lat"] <= bounds["lat_max"] and
                            bounds["lon_min"] <= pm_data["lon"] <= bounds["lon_max"]):
                            pm_data["in_bounds"] = True
                            result["coordinates_in_bounds"] += 1
                    except ValueError:
                        pass
        
        result["placemarks"].append(pm_data)
    
    result["placemark_count"] = len(result["placemarks"])
    return result


def check_corner_names(placemarks):
    """Check if placemarks have expected corner names."""
    expected = ["nw corner", "ne corner", "sw corner", "se corner"]
    found = []
    
    for pm in placemarks:
        name_lower = pm.get("name", "").lower()
        for exp in expected:
            if exp in name_lower and exp not in found:
                found.append(exp)
    
    return len(found)


def verify_stadium_field_measurement(traj, env_info, task_info):
    """
    Verify the stadium field measurement task.
    
    Uses multi-criteria scoring with anti-gaming checks.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    expected_length = metadata.get('expected_length_m', 105)
    expected_width = metadata.get('expected_width_m', 68)
    tolerance = metadata.get('tolerance_m', 5)
    
    feedback_parts = []
    score = 0
    details = {}
    
    # ================================================================
    # Copy result file from container
    # ================================================================
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read task result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
    
    details["raw_result"] = result
    
    # ================================================================
    # CRITERION 1: KML file exists and was created during task (15 pts)
    # ================================================================
    kml_info = result.get("kml_file", {})
    kml_exists = kml_info.get("exists", False)
    kml_created_during_task = kml_info.get("created_during_task", False)
    
    if kml_exists and kml_created_during_task:
        score += 15
        feedback_parts.append("✅ KML file created during task")
    elif kml_exists:
        score += 5
        feedback_parts.append("⚠️ KML exists but may predate task")
    else:
        feedback_parts.append("❌ KML file not found")
    
    # ================================================================
    # CRITERION 2: KML contains valid XML with placemarks (15 pts)
    # ================================================================
    kml_content = kml_info.get("content_base64", "")
    kml_parsed = parse_kml_content(kml_content)
    details["kml_parsed"] = kml_parsed
    
    if kml_parsed["valid_xml"]:
        score += 5
        feedback_parts.append("✅ Valid KML XML structure")
        
        if kml_parsed["placemark_count"] >= 4:
            score += 10
            feedback_parts.append(f"✅ {kml_parsed['placemark_count']} placemarks found")
        elif kml_parsed["placemark_count"] > 0:
            score += 5
            feedback_parts.append(f"⚠️ Only {kml_parsed['placemark_count']} placemarks (expected 4)")
        else:
            feedback_parts.append("❌ No placemarks in KML")
    else:
        if kml_exists:
            feedback_parts.append("❌ KML has invalid XML")
        
    # ================================================================
    # CRITERION 3: Placemarks have correct corner names (10 pts)
    # ================================================================
    corners_found = check_corner_names(kml_parsed["placemarks"])
    details["corners_found"] = corners_found
    
    if corners_found >= 4:
        score += 10
        feedback_parts.append("✅ All 4 corner placemarks named correctly")
    elif corners_found >= 2:
        score += 5
        feedback_parts.append(f"⚠️ Only {corners_found}/4 corners named correctly")
    elif corners_found > 0:
        score += 2
        feedback_parts.append(f"⚠️ Only {corners_found}/4 corners found")
    else:
        if kml_parsed["placemark_count"] > 0:
            feedback_parts.append("❌ Corner naming not correct")
    
    # ================================================================
    # CRITERION 4: Placemark coordinates within Camp Nou bounds (10 pts)
    # ================================================================
    coords_in_bounds = kml_parsed["coordinates_in_bounds"]
    details["coords_in_bounds"] = coords_in_bounds
    
    if coords_in_bounds >= 4:
        score += 10
        feedback_parts.append("✅ All placemarks within Camp Nou bounds")
    elif coords_in_bounds >= 2:
        score += 5
        feedback_parts.append(f"⚠️ Only {coords_in_bounds}/4 placemarks in correct location")
    elif coords_in_bounds > 0:
        score += 2
        feedback_parts.append(f"⚠️ Only {coords_in_bounds} placemark(s) in correct location")
    else:
        if kml_parsed["placemark_count"] > 0:
            feedback_parts.append("❌ Placemarks not at Camp Nou location")
    
    # ================================================================
    # CRITERION 5: Text file exists and was created during task (10 pts)
    # ================================================================
    txt_info = result.get("text_file", {})
    txt_exists = txt_info.get("exists", False)
    txt_created_during_task = txt_info.get("created_during_task", False)
    
    if txt_exists and txt_created_during_task:
        score += 10
        feedback_parts.append("✅ Measurement text file created during task")
    elif txt_exists:
        score += 3
        feedback_parts.append("⚠️ Text file exists but may predate task")
    else:
        feedback_parts.append("❌ Measurement text file not found")
    
    # ================================================================
    # CRITERION 6: Length measurement recorded and accurate (15 pts)
    # ================================================================
    measured_length_str = txt_info.get("measured_length", "")
    length_recorded = False
    length_accurate = False
    measured_length = None
    
    if measured_length_str:
        try:
            measured_length = float(measured_length_str)
            length_recorded = True
            details["measured_length"] = measured_length
            
            if abs(measured_length - expected_length) <= tolerance:
                length_accurate = True
                score += 15
                feedback_parts.append(f"✅ Length: {measured_length}m (expected ~{expected_length}m)")
            else:
                score += 7
                feedback_parts.append(f"⚠️ Length: {measured_length}m (outside tolerance of {expected_length}±{tolerance}m)")
        except ValueError:
            feedback_parts.append(f"❌ Could not parse length value: {measured_length_str}")
    else:
        feedback_parts.append("❌ Length measurement not found")
    
    # ================================================================
    # CRITERION 7: Width measurement recorded and accurate (15 pts)
    # ================================================================
    measured_width_str = txt_info.get("measured_width", "")
    width_recorded = False
    width_accurate = False
    measured_width = None
    
    if measured_width_str:
        try:
            measured_width = float(measured_width_str)
            width_recorded = True
            details["measured_width"] = measured_width
            
            if abs(measured_width - expected_width) <= tolerance:
                width_accurate = True
                score += 15
                feedback_parts.append(f"✅ Width: {measured_width}m (expected ~{expected_width}m)")
            else:
                score += 7
                feedback_parts.append(f"⚠️ Width: {measured_width}m (outside tolerance of {expected_width}±{tolerance}m)")
        except ValueError:
            feedback_parts.append(f"❌ Could not parse width value: {measured_width_str}")
    else:
        feedback_parts.append("❌ Width measurement not found")
    
    # ================================================================
    # CRITERION 8: FIFA compliance noted (5 pts)
    # ================================================================
    fifa_compliant = txt_info.get("fifa_compliant", "").lower()
    details["fifa_compliant_stated"] = fifa_compliant
    
    if fifa_compliant in ["yes", "no"]:
        score += 5
        feedback_parts.append(f"✅ FIFA compliance noted: {fifa_compliant.upper()}")
    else:
        feedback_parts.append("❌ FIFA compliance not documented")
    
    # ================================================================
    # CRITERION 9: VLM trajectory verification (5 pts)
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    vlm_score = 0
    
    if query_vlm and traj:
        try:
            # Import trajectory sampling helper
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Sample frames from trajectory to verify workflow
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            
            if frames or final:
                all_frames = (frames or []) + ([final] if final else [])
                
                vlm_prompt = """You are verifying a Google Earth task where the agent should:
1. Navigate to Camp Nou stadium in Barcelona
2. Measure the football field dimensions using the ruler tool
3. Create placemarks at field corners
4. Save a KML file

Looking at these sequential screenshots from the agent's work, assess:
1. Is Google Earth visible and showing Barcelona/Camp Nou area?
2. Is there evidence of measurement activity (ruler tool, measurement dialog)?
3. Are there placemarks or markers visible on the football pitch?
4. Does it show a football stadium (Camp Nou has a distinctive oval shape)?

Respond in JSON format:
{
    "google_earth_visible": true/false,
    "barcelona_or_stadium_visible": true/false,
    "measurement_evidence": true/false,
    "placemarks_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}"""
                
                vlm_result = query_vlm(prompt=vlm_prompt, images=all_frames)
                
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    details["vlm_result"] = parsed
                    
                    vlm_criteria = sum([
                        parsed.get("google_earth_visible", False),
                        parsed.get("barcelona_or_stadium_visible", False),
                        parsed.get("measurement_evidence", False),
                        parsed.get("placemarks_visible", False)
                    ])
                    
                    if vlm_criteria >= 3:
                        vlm_score = 5
                        feedback_parts.append("✅ VLM confirms measurement workflow")
                    elif vlm_criteria >= 2:
                        vlm_score = 3
                        feedback_parts.append("⚠️ VLM partial workflow confirmation")
                    elif vlm_criteria >= 1:
                        vlm_score = 1
                        feedback_parts.append("⚠️ VLM limited workflow evidence")
                    else:
                        feedback_parts.append("❌ VLM could not confirm workflow")
                else:
                    feedback_parts.append("⚠️ VLM verification inconclusive")
            else:
                feedback_parts.append("⚠️ No trajectory frames for VLM verification")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback_parts.append(f"⚠️ VLM verification error")
    else:
        feedback_parts.append("⚠️ VLM not available for trajectory verification")
    
    score += vlm_score
    
    # ================================================================
    # FINAL SCORING AND PASS DETERMINATION
    # ================================================================
    details["score_breakdown"] = {
        "kml_created": 15 if (kml_exists and kml_created_during_task) else (5 if kml_exists else 0),
        "kml_valid": kml_parsed["valid_xml"],
        "placemark_count": kml_parsed["placemark_count"],
        "corners_correct": corners_found,
        "coords_valid": coords_in_bounds,
        "txt_created": txt_exists and txt_created_during_task,
        "length_recorded": length_recorded,
        "length_accurate": length_accurate,
        "width_recorded": width_recorded,
        "width_accurate": width_accurate,
        "fifa_noted": fifa_compliant in ["yes", "no"],
        "vlm_score": vlm_score
    }
    
    # Pass criteria: 70+ points AND (at least one measurement OR KML with placemarks)
    has_measurements = length_recorded or width_recorded
    has_kml_output = kml_exists and kml_parsed["placemark_count"] > 0
    
    key_criteria_met = has_measurements or has_kml_output
    passed = score >= 70 and key_criteria_met
    
    # Build final feedback
    feedback = " | ".join(feedback_parts)
    feedback += f" | Total: {score}/100"
    
    logger.info(f"Verification complete: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }