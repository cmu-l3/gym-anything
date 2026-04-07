#!/usr/bin/env python3
"""
Verifier for search_and_route_poi_database task.

Ensures the agent successfully interrogated the large dataset, isolated the 
two specific targets, created a route between them, and exported the specific list.
"""

import json
import os
import tempfile
import re
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_search_and_route(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: Copy function not available"}

    feedback = []
    score = 0
    
    # 1. Fetch and Parse Task Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # File Existence & Anti-Gaming Checks
    if not result.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "GPX output file was not found."}
    
    if not result.get('file_created_during_task'):
        feedback.append("Warning: File timestamp predates task. Possible gaming.")
    else:
        score += 10
        feedback.append("File created successfully during task.")

    # 2. Fetch and Parse Output GPX File
    temp_gpx = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    try:
        copy_from_env("C:\\workspace\\output\\sar_mission.gpx", temp_gpx.name)
        with open(temp_gpx.name, 'r', encoding='utf-8', errors='ignore') as f:
            gpx_raw = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to retrieve GPX file: {e}"}
    finally:
        if os.path.exists(temp_gpx.name):
            os.unlink(temp_gpx.name)

    # Provenance Check - ensure it was exported from BaseCamp (not written manually by agent)
    if "grmx:" in gpx_raw or "Garmin" in gpx_raw:
        score += 10
        feedback.append("BaseCamp provenance verified.")
    else:
        feedback.append("Missing Garmin extensions (did the agent manually write the file?).")

    # Remove XML namespaces to make parsing trivial
    clean_xml = re.sub(r'\sxmlns="[^"]+"', '', gpx_raw, count=1)
    clean_xml = re.sub(r'\sxmlns:\w+="[^"]+"', '', clean_xml)
    
    try:
        root = ET.fromstring(clean_xml)
    except ET.ParseError as e:
        return {"passed": False, "score": score, "feedback": f"Invalid XML in GPX file: {e}"}

    # 3. Data Isolation Check (Exactly 2 Waypoints)
    wpts = root.findall('.//wpt')
    if len(wpts) == 2:
        score += 20
        feedback.append("Successfully isolated EXACTLY 2 waypoints.")
    elif len(wpts) > 2:
        feedback.append(f"Failed isolation: Found {len(wpts)} waypoints. Agent likely exported the whole database.")
    else:
        feedback.append(f"Failed isolation: Found only {len(wpts)} waypoints.")

    # 4. Target Acquisition Check (Specific Names)
    wpt_names = [w.find('name').text for w in wpts if w.find('name') is not None]
    found_zealand = any("Zealand Falls Hut" in n for n in wpt_names)
    found_guyot = any("Guyot Shelter" in n for n in wpt_names)
    
    if found_zealand and found_guyot:
        score += 40
        feedback.append("Both target waypoints successfully found and extracted.")
    else:
        feedback.append(f"Missing targets. Extracted names: {wpt_names}")

    # 5. Route Generation Check
    rtes = root.findall('.//rte')
    if len(rtes) >= 1:
        route = rtes[0]
        rtepts = route.findall('.//rtept')
        rtept_names = [r.find('name').text for r in rtepts if r.find('name') is not None]
        
        route_has_zealand = any("Zealand Falls Hut" in n for n in rtept_names)
        route_has_guyot = any("Guyot Shelter" in n for n in rtept_names)
        
        if route_has_zealand and route_has_guyot:
            score += 20
            feedback.append("Route generated successfully between the two targets.")
        else:
            feedback.append("Route exists but does not connect the correct targets.")
    else:
        feedback.append("No route found in the export.")

    # Final pass logic
    key_criteria_met = (len(wpts) == 2) and found_zealand and found_guyot
    passed = (score >= 80) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }