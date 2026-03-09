#!/usr/bin/env python3
"""
Verifier for Line-of-Sight Microwave Link Analysis task.

VERIFICATION STRATEGY:
1. File existence and timestamp checks (anti-gaming)
2. KML content validation (placemarks at correct coordinates)
3. Report content validation (distance, elevation, obstruction assessment)
4. Screenshot validation (exists, reasonable size)
5. VLM trajectory verification (shows workflow progression)

SCORING:
- KML file valid with Tower A placemark: 15 points
- KML file valid with Tower B placemark: 15 points  
- KML contains path/linestring: 10 points
- Screenshot exists and valid: 15 points
- Report exists with distance: 10 points
- Report has obstruction assessment: 10 points
- Report has elevation values: 10 points
- VLM trajectory verification: 15 points

Pass threshold: 60 points with at least one placemark created during task
"""

import json
import tempfile
import os
import re
import base64
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_los_microwave_link(traj, env_info, task_info):
    """
    Verify the line-of-sight microwave link analysis task.
    
    Args:
        traj: Trajectory data with frames
        env_info: Environment info with copy_from_env function
        task_info: Task metadata
        
    Returns:
        dict with 'passed', 'score', 'feedback'
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available"
        }
    
    # Get metadata
    metadata = task_info.get('metadata', {})
    tower_a_coords = metadata.get('tower_a_coords', [40.0258, -105.4286])
    tower_b_coords = metadata.get('tower_b_coords', [39.9878, -105.2931])
    coord_tolerance = metadata.get('coordinate_tolerance_degrees', 0.02)
    expected_dist_min = metadata.get('expected_distance_km_min', 14)
    expected_dist_max = metadata.get('expected_distance_km_max', 18)
    expected_elev_min = metadata.get('expected_elevation_min_m', 1800)
    expected_elev_max = metadata.get('expected_elevation_max_m', 3200)
    
    feedback_parts = []
    score = 0
    details = {}
    
    # ================================================================
    # Copy result file from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result file: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Failed to read task result: {e}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    details['result'] = result
    task_start = result.get('task_start', 0)
    
    # ================================================================
    # CRITERION 1-3: KML File Verification (40 points total)
    # ================================================================
    kml_info = result.get('kml', {})
    kml_exists = kml_info.get('exists', False)
    kml_created = kml_info.get('created_during_task', False)
    kml_content_b64 = kml_info.get('content_base64', '')
    
    tower_a_found = False
    tower_b_found = False
    path_found = False
    
    if not kml_exists:
        feedback_parts.append("❌ KML file not found")
    elif not kml_created:
        feedback_parts.append("⚠️ KML file exists but was not created during task (potential gaming)")
        score += 5  # Partial credit
    else:
        # Parse KML content
        try:
            kml_content = base64.b64decode(kml_content_b64).decode('utf-8', errors='ignore')
            
            # Parse as XML
            root = ET.fromstring(kml_content)
            
            # Handle KML namespace
            ns = {'kml': 'http://www.opengis.net/kml/2.2'}
            
            # Find all placemarks
            placemarks = root.findall('.//{http://www.opengis.net/kml/2.2}Placemark')
            if not placemarks:
                placemarks = root.findall('.//Placemark')
            
            for pm in placemarks:
                # Get name
                name_elem = pm.find('{http://www.opengis.net/kml/2.2}name')
                if name_elem is None:
                    name_elem = pm.find('name')
                name = name_elem.text.lower() if name_elem is not None and name_elem.text else ""
                
                # Get coordinates
                coord_elem = pm.find('.//{http://www.opengis.net/kml/2.2}coordinates')
                if coord_elem is None:
                    coord_elem = pm.find('.//coordinates')
                
                if coord_elem is not None and coord_elem.text:
                    coords_text = coord_elem.text.strip()
                    # Parse lon,lat,alt format
                    coord_matches = re.findall(r'([-\d.]+),([-\d.]+)', coords_text)
                    
                    for lon_str, lat_str in coord_matches:
                        try:
                            lon, lat = float(lon_str), float(lat_str)
                            
                            # Check Tower A (looking for tower_a, sugarloaf in name)
                            if ('tower' in name and 'a' in name) or 'sugarloaf' in name:
                                if (abs(lat - tower_a_coords[0]) < coord_tolerance and 
                                    abs(lon - tower_a_coords[1]) < coord_tolerance):
                                    tower_a_found = True
                            
                            # Check Tower B (looking for tower_b, flagstaff in name)
                            if ('tower' in name and 'b' in name) or 'flagstaff' in name:
                                if (abs(lat - tower_b_coords[0]) < coord_tolerance and 
                                    abs(lon - tower_b_coords[1]) < coord_tolerance):
                                    tower_b_found = True
                        except ValueError:
                            continue
                
                # Check for LineString (path)
                if pm.find('.//{http://www.opengis.net/kml/2.2}LineString') is not None:
                    path_found = True
                if pm.find('.//LineString') is not None:
                    path_found = True
            
            # Also check for paths outside placemarks
            if root.find('.//{http://www.opengis.net/kml/2.2}LineString') is not None:
                path_found = True
            if root.find('.//LineString') is not None:
                path_found = True
                
        except ET.ParseError as e:
            feedback_parts.append(f"⚠️ KML parse error: {e}")
        except Exception as e:
            feedback_parts.append(f"⚠️ KML verification error: {e}")
    
    # Score KML components
    if tower_a_found:
        score += 15
        feedback_parts.append("✅ Tower A placemark found at correct location")
    else:
        feedback_parts.append("❌ Tower A placemark not found or wrong location")
    
    if tower_b_found:
        score += 15
        feedback_parts.append("✅ Tower B placemark found at correct location")
    else:
        feedback_parts.append("❌ Tower B placemark not found or wrong location")
    
    if path_found:
        score += 10
        feedback_parts.append("✅ Path/LineString found in KML")
    else:
        feedback_parts.append("❌ No path connecting towers in KML")
    
    details['kml_verification'] = {
        'tower_a_found': tower_a_found,
        'tower_b_found': tower_b_found,
        'path_found': path_found
    }
    
    # ================================================================
    # CRITERION 4: Screenshot Verification (15 points)
    # ================================================================
    screenshot_info = result.get('screenshot', {})
    screenshot_exists = screenshot_info.get('exists', False)
    screenshot_created = screenshot_info.get('created_during_task', False)
    screenshot_size = screenshot_info.get('size_bytes', 0)
    screenshot_width = screenshot_info.get('width', 0)
    screenshot_height = screenshot_info.get('height', 0)
    
    if not screenshot_exists:
        feedback_parts.append("❌ Elevation profile screenshot not found")
    elif not screenshot_created:
        feedback_parts.append("⚠️ Screenshot exists but was not created during task")
        score += 3
    elif screenshot_size < 5000:
        feedback_parts.append(f"⚠️ Screenshot file suspiciously small ({screenshot_size} bytes)")
        score += 5
    elif screenshot_width > 200 and screenshot_height > 100:
        score += 15
        feedback_parts.append(f"✅ Screenshot valid ({screenshot_width}x{screenshot_height}, {screenshot_size} bytes)")
    else:
        score += 8
        feedback_parts.append(f"⚠️ Screenshot dimensions unusual ({screenshot_width}x{screenshot_height})")
    
    details['screenshot_verification'] = {
        'exists': screenshot_exists,
        'created_during_task': screenshot_created,
        'size': screenshot_size,
        'dimensions': f"{screenshot_width}x{screenshot_height}"
    }
    
    # ================================================================
    # CRITERION 5-7: Report Verification (30 points)
    # ================================================================
    report_info = result.get('report', {})
    report_exists = report_info.get('exists', False)
    report_created = report_info.get('created_during_task', False)
    report_content_b64 = report_info.get('content_base64', '')
    
    distance_found = False
    distance_value = None
    obstruction_found = False
    obstruction_value = None
    elevation_found = False
    elevation_value = None
    
    if not report_exists:
        feedback_parts.append("❌ Report file not found")
    elif not report_created:
        feedback_parts.append("⚠️ Report exists but was not created during task")
        score += 3
    else:
        try:
            report_content = base64.b64decode(report_content_b64).decode('utf-8', errors='ignore').lower()
            
            # Check for distance measurement
            dist_match = re.search(r'(\d+\.?\d*)\s*(km|kilometer)', report_content)
            if dist_match:
                distance_value = float(dist_match.group(1))
                if expected_dist_min <= distance_value <= expected_dist_max:
                    distance_found = True
                    score += 10
                    feedback_parts.append(f"✅ Distance measurement correct: {distance_value} km")
                else:
                    score += 4
                    feedback_parts.append(f"⚠️ Distance found but outside expected range: {distance_value} km")
            else:
                feedback_parts.append("❌ No distance measurement found in report")
            
            # Check for obstruction assessment
            if 'obstruction' in report_content or 'blocked' in report_content or 'clear' in report_content:
                obstruction_found = True
                if 'yes' in report_content or 'obstruction' in report_content:
                    obstruction_value = 'yes'
                    score += 10
                    feedback_parts.append("✅ Obstruction assessment found (indicates obstruction)")
                elif 'no' in report_content or 'clear' in report_content:
                    obstruction_value = 'no'
                    score += 5
                    feedback_parts.append("⚠️ Obstruction assessment found but may be incorrect")
            else:
                feedback_parts.append("❌ No obstruction assessment in report")
            
            # Check for elevation values
            elev_match = re.search(r'(\d{4})\s*(m|meter|metres)', report_content)
            if elev_match:
                elevation_value = float(elev_match.group(1))
                if expected_elev_min <= elevation_value <= expected_elev_max:
                    elevation_found = True
                    score += 10
                    feedback_parts.append(f"✅ Elevation value reasonable: {elevation_value}m")
                else:
                    score += 4
                    feedback_parts.append(f"⚠️ Elevation found but unusual: {elevation_value}m")
            else:
                feedback_parts.append("❌ No elevation values found in report")
                
        except Exception as e:
            feedback_parts.append(f"⚠️ Report parsing error: {e}")
    
    details['report_verification'] = {
        'distance_found': distance_found,
        'distance_value': distance_value,
        'obstruction_found': obstruction_found,
        'obstruction_value': obstruction_value,
        'elevation_found': elevation_found,
        'elevation_value': elevation_value
    }
    
    # ================================================================
    # CRITERION 8: VLM Trajectory Verification (15 points)
    # ================================================================
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm:
        try:
            # Import trajectory utilities
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Sample frames across the trajectory
            frames = sample_trajectory_frames(traj, n=5)
            final_frame = get_final_screenshot(traj)
            
            if frames or final_frame:
                all_frames = (frames or []) + ([final_frame] if final_frame else [])
                
                vlm_prompt = """You are verifying a Google Earth task where the agent should have:
1. Navigated to Colorado (Boulder County area)
2. Created placemarks at two tower locations
3. Used the Ruler tool to draw a path between them
4. Displayed an elevation profile
5. Saved files (KML, screenshot, report)

Looking at these screenshots from the agent's work session, assess:
1. Is Google Earth visible in any frames?
2. Is the Colorado/Boulder mountain area visible?
3. Are there any placemarks visible?
4. Is the Ruler tool or elevation profile visible in any frame?
5. Does this show genuine work progression (not just idle screens)?

Respond in JSON format:
{
    "google_earth_visible": true/false,
    "colorado_area_visible": true/false,
    "placemarks_visible": true/false,
    "ruler_or_profile_visible": true/false,
    "genuine_progression": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description"
}"""
                
                vlm_result = query_vlm(prompt=vlm_prompt, images=all_frames)
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    
                    vlm_criteria = 0
                    if parsed.get('google_earth_visible'):
                        vlm_criteria += 1
                    if parsed.get('colorado_area_visible'):
                        vlm_criteria += 1
                    if parsed.get('placemarks_visible'):
                        vlm_criteria += 1
                    if parsed.get('ruler_or_profile_visible'):
                        vlm_criteria += 1
                    if parsed.get('genuine_progression'):
                        vlm_criteria += 1
                    
                    confidence = parsed.get('confidence', 'low')
                    confidence_mult = {'high': 1.0, 'medium': 0.8, 'low': 0.6}.get(confidence, 0.6)
                    
                    vlm_score = int((vlm_criteria / 5) * 15 * confidence_mult)
                    score += vlm_score
                    
                    if vlm_criteria >= 3:
                        feedback_parts.append(f"✅ VLM trajectory verification passed ({vlm_criteria}/5 criteria, {confidence} confidence)")
                    else:
                        feedback_parts.append(f"⚠️ VLM trajectory verification partial ({vlm_criteria}/5 criteria)")
                    
                    details['vlm_verification'] = {
                        'criteria_met': vlm_criteria,
                        'confidence': confidence,
                        'score': vlm_score,
                        'observations': parsed.get('observations', '')
                    }
                else:
                    feedback_parts.append("⚠️ VLM verification failed")
            else:
                feedback_parts.append("⚠️ No trajectory frames available for VLM verification")
                
        except ImportError:
            feedback_parts.append("⚠️ VLM utilities not available")
        except Exception as e:
            feedback_parts.append(f"⚠️ VLM verification error: {e}")
    else:
        feedback_parts.append("⚠️ VLM not available for trajectory verification")
    
    # ================================================================
    # Final scoring and pass/fail determination
    # ================================================================
    
    # Key criteria: At least one placemark must have been properly created
    key_criteria_met = (tower_a_found or tower_b_found) and (kml_created or screenshot_created or report_created)
    
    # Pass threshold: 60 points AND key criteria
    passed = score >= 60 and key_criteria_met
    
    details['score_breakdown'] = {
        'kml_tower_a': 15 if tower_a_found else 0,
        'kml_tower_b': 15 if tower_b_found else 0,
        'kml_path': 10 if path_found else 0,
        'screenshot': 15 if (screenshot_exists and screenshot_created and screenshot_size >= 5000) else 0,
        'report_distance': 10 if distance_found else 0,
        'report_obstruction': 10 if obstruction_found else 0,
        'report_elevation': 10 if elevation_found else 0,
        'vlm_trajectory': vlm_score
    }
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "max_score": 100,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }