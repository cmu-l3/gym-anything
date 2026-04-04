#!/usr/bin/env python3
"""
Verifier for carrier_length_measurement@1 task.

Hybrid verification (programmatic + VLM trajectory):
1. KML file exists and was created during task (20 points)
2. KML contains LineString/Path element (15 points)
3. Coordinates within Norfolk NS bounds (15 points)
4. Measured distance within acceptable range (25 points)
5. VLM trajectory verification - workflow progression (15 points)
6. VLM final screenshot - shows measurement/Norfolk area (10 points)

Pass threshold: 70 points with KML created AND measurement in range
"""

import json
import tempfile
import os
import math
import base64
import logging
from xml.etree import ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def haversine_distance(lat1, lon1, lat2, lon2):
    """Calculate the great-circle distance between two points in meters."""
    R = 6371000  # Earth's radius in meters
    
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)
    
    a = math.sin(delta_phi/2)**2 + \
        math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    
    return R * c


def parse_kml_coordinates(coord_string):
    """Parse KML coordinate string into list of (lon, lat, alt) tuples."""
    coords = []
    parts = coord_string.strip().split()
    for part in parts:
        values = part.split(',')
        if len(values) >= 2:
            try:
                lon = float(values[0])
                lat = float(values[1])
                alt = float(values[2]) if len(values) > 2 else 0
                coords.append((lon, lat, alt))
            except ValueError:
                continue
    return coords


def parse_kml_content(kml_content):
    """Parse KML content and extract LineString coordinates."""
    try:
        root = ET.fromstring(kml_content)
    except ET.ParseError as e:
        return None, f"KML parse error: {e}"
    
    # Handle KML namespace
    ns = {'kml': 'http://www.opengis.net/kml/2.2'}
    
    # Find LineString elements (try with and without namespace)
    linestrings = root.findall('.//kml:LineString', ns)
    if not linestrings:
        linestrings = root.findall('.//LineString')
    
    if not linestrings:
        # Also check for Path (alternative representation)
        linestrings = root.findall('.//kml:Path', ns)
        if not linestrings:
            linestrings = root.findall('.//Path')
    
    if not linestrings:
        return None, "No LineString/Path element found in KML"
    
    # Get coordinates from first LineString
    linestring = linestrings[0]
    coords_elem = linestring.find('kml:coordinates', ns)
    if coords_elem is None:
        coords_elem = linestring.find('coordinates')
    
    if coords_elem is None or not coords_elem.text:
        return None, "No coordinates found in LineString"
    
    coords = parse_kml_coordinates(coords_elem.text)
    
    if len(coords) < 2:
        return None, f"Need at least 2 coordinates, found {len(coords)}"
    
    return coords, None


# VLM Prompts
TRAJECTORY_VERIFICATION_PROMPT = """You are analyzing a sequence of screenshots from an agent performing a measurement task in Google Earth Pro.

TASK: Navigate to Naval Station Norfolk, find an aircraft carrier, and measure its length using the Ruler tool.

The screenshots are in chronological order (earliest to latest). Look for evidence of these workflow stages:

1. NAVIGATION: Agent searched for or navigated to Norfolk Naval Station area
2. ZOOM: Agent zoomed into the carrier pier area (ships visible from above)
3. RULER TOOL: The ruler/measurement tool dialog appeared
4. MEASUREMENT: Agent drew a line measurement on a ship-shaped object
5. SAVE: Evidence of saving the measurement (Save dialog, KML file)

Analyze what you see across ALL frames:

Respond in JSON format:
{
    "navigation_to_norfolk": true/false,
    "carrier_pier_visible": true/false,
    "ship_shapes_visible": true/false,
    "ruler_tool_used": true/false,
    "measurement_line_visible": true/false,
    "save_dialog_visible": true/false,
    "meaningful_progression": true/false,
    "stages_observed": ["list stages you can identify"],
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see in the workflow"
}
"""

FINAL_SCREENSHOT_PROMPT = """You are verifying a Google Earth Pro screenshot showing the result of an aircraft carrier measurement task.

TASK: Measure the length of an aircraft carrier at Naval Station Norfolk.

Analyze this final screenshot. Look for:
1. Is this Google Earth Pro (satellite imagery application)?
2. Does it show a naval base / port area with large ships?
3. Is there a ruler/measurement line visible on a ship?
4. Is the Ruler dialog or measurement visible with a distance value?
5. Does the area look like Norfolk, Virginia (coastal area with piers)?

Respond in JSON format:
{
    "is_google_earth": true/false,
    "shows_naval_base": true/false,
    "ships_visible": true/false,
    "measurement_visible": true/false,
    "ruler_dialog_visible": true/false,
    "distance_value_shown": true/false,
    "looks_like_norfolk": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""


def verify_carrier_length_measurement(traj, env_info, task_info):
    """
    Verify that the agent measured an aircraft carrier at Norfolk Naval Station.
    
    Uses multiple verification signals:
    1. Programmatic: KML file analysis
    2. VLM: Trajectory frames (proves actual work)
    3. VLM: Final screenshot (confirms end state)
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Get task metadata
    metadata = task_info.get('metadata', {})
    min_length = metadata.get('measurement_range_min_meters', 315)
    max_length = metadata.get('measurement_range_max_meters', 350)
    bounds = metadata.get('location_bounds', {
        'north': 36.95, 'south': 36.94, 'east': -76.32, 'west': -76.34
    })
    
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
        details['export_result'] = result
    except Exception as e:
        logger.error(f"Failed to read result file: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # CRITERION 1: KML file exists and was created during task (20 points)
    # ================================================================
    output_exists = result.get('output_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    
    if not output_exists:
        feedback_parts.append("❌ KML file not found")
        details['kml_exists'] = False
    else:
        details['kml_exists'] = True
        if file_created_during_task:
            score += 20
            feedback_parts.append("✅ KML file created during task")
            details['file_created_during_task'] = True
        else:
            score += 5  # File exists but may predate task
            feedback_parts.append("⚠️ KML file exists but may predate task")
            details['file_created_during_task'] = False
    
    # ================================================================
    # CRITERION 2-4: Parse KML and validate content (55 points total)
    # ================================================================
    kml_content_b64 = result.get('kml_content_base64', '')
    coords = None
    measured_distance = None
    coords_in_bounds = False
    
    if kml_content_b64:
        try:
            kml_content = base64.b64decode(kml_content_b64).decode('utf-8')
            coords, error = parse_kml_content(kml_content)
            
            if coords:
                # CRITERION 2: Has LineString (15 points)
                score += 15
                feedback_parts.append("✅ KML contains path/line element")
                details['has_linestring'] = True
                
                # Get start and end coordinates
                start_lon, start_lat, _ = coords[0]
                end_lon, end_lat, _ = coords[-1]
                details['start_coord'] = {'lat': start_lat, 'lon': start_lon}
                details['end_coord'] = {'lat': end_lat, 'lon': end_lon}
                
                # CRITERION 3: Coordinates in Norfolk NS bounds (15 points)
                start_in_bounds = (bounds['south'] <= start_lat <= bounds['north'] and 
                                   bounds['west'] <= start_lon <= bounds['east'])
                end_in_bounds = (bounds['south'] <= end_lat <= bounds['north'] and 
                                 bounds['west'] <= end_lon <= bounds['east'])
                
                if start_in_bounds and end_in_bounds:
                    coords_in_bounds = True
                    score += 15
                    feedback_parts.append("✅ Coordinates within Norfolk NS bounds")
                elif start_in_bounds or end_in_bounds:
                    score += 7
                    feedback_parts.append("⚠️ Only partial coordinates in bounds")
                else:
                    feedback_parts.append(f"❌ Coordinates outside Norfolk bounds: ({start_lat:.4f}, {start_lon:.4f}) to ({end_lat:.4f}, {end_lon:.4f})")
                
                details['coords_in_bounds'] = coords_in_bounds
                
                # CRITERION 4: Distance in acceptable range (25 points)
                measured_distance = haversine_distance(start_lat, start_lon, end_lat, end_lon)
                details['measured_distance_meters'] = round(measured_distance, 2)
                
                if min_length <= measured_distance <= max_length:
                    score += 25
                    feedback_parts.append(f"✅ Measured distance {measured_distance:.1f}m within range ({min_length}-{max_length}m)")
                    details['distance_in_range'] = True
                elif 250 <= measured_distance <= 400:
                    # Partial credit for close measurements
                    score += 10
                    feedback_parts.append(f"⚠️ Measured distance {measured_distance:.1f}m close but outside range ({min_length}-{max_length}m)")
                    details['distance_in_range'] = False
                else:
                    feedback_parts.append(f"❌ Measured distance {measured_distance:.1f}m outside acceptable range ({min_length}-{max_length}m)")
                    details['distance_in_range'] = False
            else:
                feedback_parts.append(f"❌ KML parsing error: {error}")
                details['has_linestring'] = False
                
        except Exception as e:
            feedback_parts.append(f"❌ Failed to parse KML: {e}")
            details['kml_parse_error'] = str(e)
    else:
        feedback_parts.append("❌ No KML content to parse")
    
    # ================================================================
    # CRITERION 5: VLM Trajectory Verification (15 points)
    # ================================================================
    trajectory_score = 0
    
    if query_vlm and traj:
        try:
            # Import trajectory sampling utility
            from gym_anything.vlm import sample_trajectory_frames
            
            # Sample frames across the trajectory
            frames = sample_trajectory_frames(traj, n=5)
            
            if frames and len(frames) >= 2:
                vlm_result = query_vlm(
                    prompt=TRAJECTORY_VERIFICATION_PROMPT,
                    images=frames
                )
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    details['trajectory_vlm'] = parsed
                    
                    # Count workflow stages observed
                    stages_found = 0
                    if parsed.get('navigation_to_norfolk'):
                        stages_found += 1
                    if parsed.get('carrier_pier_visible') or parsed.get('ship_shapes_visible'):
                        stages_found += 1
                    if parsed.get('ruler_tool_used') or parsed.get('measurement_line_visible'):
                        stages_found += 1
                    if parsed.get('meaningful_progression'):
                        stages_found += 1
                    
                    # Award points based on stages
                    if stages_found >= 3:
                        trajectory_score = 15
                        feedback_parts.append("✅ VLM: Workflow progression confirmed")
                    elif stages_found >= 2:
                        trajectory_score = 10
                        feedback_parts.append("⚠️ VLM: Partial workflow observed")
                    elif stages_found >= 1:
                        trajectory_score = 5
                        feedback_parts.append("⚠️ VLM: Minimal workflow evidence")
                    else:
                        feedback_parts.append("❌ VLM: Workflow not verified")
                    
                    details['trajectory_stages_found'] = stages_found
                else:
                    feedback_parts.append("⚠️ VLM trajectory query failed")
            else:
                feedback_parts.append("⚠️ Insufficient trajectory frames for VLM")
                
        except ImportError:
            # Fallback if trajectory sampling not available
            logger.warning("Could not import trajectory sampling utilities")
            feedback_parts.append("⚠️ Trajectory VLM verification skipped")
        except Exception as e:
            logger.warning(f"Trajectory VLM verification failed: {e}")
            feedback_parts.append(f"⚠️ Trajectory VLM error: {str(e)[:50]}")
    else:
        feedback_parts.append("⚠️ VLM not available for trajectory verification")
    
    score += trajectory_score
    
    # ================================================================
    # CRITERION 6: VLM Final Screenshot (10 points)
    # ================================================================
    final_score = 0
    
    if query_vlm:
        try:
            # Copy final screenshot
            temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            try:
                copy_from_env("/tmp/task_final.png", temp_screenshot.name)
                
                # Check file size to ensure it's valid
                if os.path.getsize(temp_screenshot.name) > 1000:
                    vlm_result = query_vlm(
                        prompt=FINAL_SCREENSHOT_PROMPT,
                        image=temp_screenshot.name
                    )
                    
                    if vlm_result.get('success'):
                        parsed = vlm_result.get('parsed', {})
                        details['final_screenshot_vlm'] = parsed
                        
                        criteria_met = 0
                        if parsed.get('is_google_earth'):
                            criteria_met += 1
                        if parsed.get('shows_naval_base') or parsed.get('ships_visible'):
                            criteria_met += 1
                        if parsed.get('measurement_visible') or parsed.get('ruler_dialog_visible'):
                            criteria_met += 1
                        if parsed.get('looks_like_norfolk'):
                            criteria_met += 1
                        
                        if criteria_met >= 3:
                            final_score = 10
                            feedback_parts.append("✅ VLM: Final screenshot confirms task")
                        elif criteria_met >= 2:
                            final_score = 5
                            feedback_parts.append("⚠️ VLM: Final screenshot partially confirms")
                        else:
                            feedback_parts.append("❌ VLM: Final screenshot does not confirm task")
                        
                        details['final_screenshot_criteria'] = criteria_met
                    else:
                        feedback_parts.append("⚠️ Final screenshot VLM query failed")
                else:
                    feedback_parts.append("⚠️ Final screenshot too small/invalid")
                    
            finally:
                if os.path.exists(temp_screenshot.name):
                    os.unlink(temp_screenshot.name)
                    
        except Exception as e:
            logger.warning(f"Final screenshot VLM failed: {e}")
            feedback_parts.append("⚠️ Could not verify final screenshot")
    
    score += final_score
    
    # ================================================================
    # DETERMINE PASS/FAIL
    # ================================================================
    # Key criteria: KML created during task AND distance in acceptable range
    key_criteria_met = (
        details.get('kml_exists', False) and 
        details.get('file_created_during_task', False) and
        details.get('distance_in_range', False)
    )
    
    # Alternative pass: high score even without perfect distance
    high_score_pass = score >= 75 and details.get('kml_exists', False)
    
    passed = (score >= 70 and key_criteria_met) or (score >= 85)
    
    # Generate final feedback
    feedback = " | ".join(feedback_parts)
    
    if passed:
        feedback = f"✅ PASSED (Score: {score}/100) | " + feedback
    else:
        if not details.get('kml_exists'):
            feedback = f"❌ FAILED: No KML file created (Score: {score}/100) | " + feedback
        elif not details.get('distance_in_range'):
            feedback = f"❌ FAILED: Measurement not in range (Score: {score}/100) | " + feedback
        else:
            feedback = f"❌ FAILED (Score: {score}/100) | " + feedback
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }