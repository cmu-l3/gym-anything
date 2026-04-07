#!/usr/bin/env python3
"""
Verifier for transcribe_transect_route task.

VERIFICATION CRITERIA:
1. File exists and was created during the task (Anti-gaming)
2. GPX parses as valid XML and contains exactly 1 Route (<rte>)
3. The Route contains exactly 5 waypoints (<rtept>)
4. The coordinates match the spec within a ±0.0005 tolerance
5. The sequence is exactly TP1 -> TP2 -> TP3 -> TP4 -> TP5
6. Route Profile is 'Direct' (No intermediate trail-snapping <gpxx:rpt> elements)
"""

import os
import json
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_transcribe_transect_route(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available in environment."}

    metadata = task_info.get('metadata', {})
    expected_wpts = metadata.get('expected_waypoints', [])
    tolerance = metadata.get('coordinate_tolerance', 0.0005)

    score = 0
    feedback_parts = []
    
    # 1. Retrieve the Task Execution Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task_result.json: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    output_exists = result.get('output_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)

    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Failure: GPX export file not found."}
    if not file_created_during_task:
        return {"passed": False, "score": 0, "feedback": "Failure: GPX file existed before task (Anti-gaming check failed)."}
        
    score += 15
    feedback_parts.append("GPX file successfully exported")

    # 2. Retrieve the Exported GPX File
    gpx_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    try:
        copy_from_env("C:\\workspace\\output\\botanical_transect.gpx", gpx_temp.name)
        
        # Parse XML
        tree = ET.parse(gpx_temp.name)
        root = tree.getroot()
        
        # Strip namespaces from tags for robust searching
        for elem in root.iter():
            if '}' in elem.tag:
                elem.tag = elem.tag.split('}', 1)[1]
                
        # 3. Check for Route Element
        routes = root.findall('.//rte')
        if len(routes) == 0:
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts) + " | Failure: No route found in GPX."}
        elif len(routes) > 1:
            feedback_parts.append("Warning: Multiple routes found. Validating the first one.")
            
        score += 15
        route = routes[0]
        route_pts = route.findall('.//rtept')
        
        if len(route_pts) == 5:
            score += 10
            feedback_parts.append("Route contains exactly 5 points")
        else:
            feedback_parts.append(f"Failure: Route contains {len(route_pts)} points instead of 5")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
            
        # 4. & 5. Check Sequence and Coordinates
        seq_correct = True
        coords_correct = True
        
        for i, expected in enumerate(expected_wpts):
            pt = route_pts[i]
            
            # Check Name
            name_node = pt.find('name')
            actual_name = name_node.text.strip() if name_node is not None and name_node.text else ""
            if actual_name.upper() != expected["name"].upper():
                seq_correct = False
                
            # Check Coordinates
            lat = float(pt.attrib.get('lat', 0))
            lon = float(pt.attrib.get('lon', 0))
            if abs(lat - expected["lat"]) > tolerance or abs(lon - expected["lon"]) > tolerance:
                coords_correct = False

        if seq_correct:
            score += 20
            feedback_parts.append("Waypoint naming and sequence correct (TP1 -> TP5)")
        else:
            feedback_parts.append("Failure: Incorrect sequence or naming. Route must follow TP1 through TP5 in order.")
            
        if coords_correct:
            score += 20
            feedback_parts.append("Coordinate transcription accurate")
        else:
            feedback_parts.append("Failure: One or more coordinates fall outside the accepted precision tolerance.")

        # 6. Check 'Direct' Routing Config
        # BaseCamp adds route points (<gpxx:rpt>) between the main waypoints (<rtept>) if routing is set to Hiking/Driving. 
        # For 'Direct' mode, there are strictly no injected route points, or RouteMode explicitly states 'Direct'.
        route_mode_node = route.find('.//RouteMode')
        is_direct = False
        
        if route_mode_node is not None and route_mode_node.text == 'Direct':
            is_direct = True
        else:
            # Fallback check: ensure no hidden route trajectory points are injected
            rpt_nodes = route.findall('.//rpt')
            if len(rpt_nodes) == 0:
                is_direct = True
                
        if is_direct:
            score += 20
            feedback_parts.append("Direct Routing applied successfully (No trail-snapping nodes)")
        else:
            feedback_parts.append("Failure: Route mapped to trails instead of Direct Point-to-Point. Must set routing profile to 'Direct'.")
            
    except ET.ParseError:
        return {"passed": False, "score": score, "feedback": "Failure: Exported file is not valid XML/GPX."}
    except Exception as e:
        logger.error(f"Verification encountered error: {e}")
        return {"passed": False, "score": score, "feedback": f"Error during verification: {str(e)}"}
    finally:
        if os.path.exists(gpx_temp.name):
            os.unlink(gpx_temp.name)

    # Calculate Pass/Fail
    passed = (score >= 80 and seq_correct and coords_correct)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }