#!/usr/bin/env python3
"""
Verifier for refine_magnitude_outliers_scolv task.

Uses `copy_from_env` to read the JSON result and the SeisComP XML dump of the event.
Checks if the event was adopted, if a new mb magnitude was created, and if station SANI was excluded.
"""

import json
import tempfile
import os
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_magnitude_refinement(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_station = metadata.get('target_station', 'SANI')
    target_mag_type = metadata.get('target_magnitude_type', 'mb')
    expected_agency = metadata.get('expected_agency', 'GYM')

    score = 0
    feedback_parts = []
    
    # 1. Retrieve the task result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result.get('xml_dump_exists'):
        return {"passed": False, "score": 0, "feedback": "Event XML dump failed or no event found."}

    initial_mag_id = result.get('initial_mag_id', '')

    # 2. Retrieve the XML dump
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    try:
        copy_from_env("/tmp/event_dump.xml", temp_xml.name)
        
        # Parse XML and strip namespaces for easier querying
        tree = ET.parse(temp_xml.name)
        root = tree.getroot()
        for elem in root.iter():
            if '}' in elem.tag:
                elem.tag = elem.tag.split('}', 1)[1]
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse Event XML: {e}"}
    finally:
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)

    # 3. Analyze Event XML Data
    event = root.find('.//event')
    if event is None:
        return {"passed": False, "score": 0, "feedback": "No event found in XML dump."}

    agency_id = event.findtext('.//creationInfo/agencyID')
    pref_mag_id = event.findtext('preferredMagnitudeID')

    # Criterion A: Event Adopted (Agency Changed) - 20 pts
    if agency_id == expected_agency:
        score += 20
        feedback_parts.append("Event adopted successfully (Agency=GYM)")
    else:
        feedback_parts.append(f"Event not adopted (Agency={agency_id}, expected {expected_agency})")

    # Locate the preferred magnitude object
    mags = root.findall('.//magnitude')
    pref_mag = None
    for m in mags:
        if m.get('publicID') == pref_mag_id:
            pref_mag = m
            break

    if pref_mag is None:
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback_parts) + " | Preferred magnitude object not found."
        }

    # Criterion B: New Magnitude Created - 15 pts
    if pref_mag_id != initial_mag_id and pref_mag_id is not None:
        score += 15
        feedback_parts.append("New magnitude created and set as preferred")
    else:
        feedback_parts.append("Preferred magnitude ID unchanged (no new commit detected)")

    # Criterion C: Magnitude Type is correct (mb) - 15 pts
    mag_type = pref_mag.findtext('type')
    if mag_type == target_mag_type:
        score += 15
        feedback_parts.append(f"Magnitude type is correct ({mag_type})")
    else:
        feedback_parts.append(f"Magnitude type incorrect ({mag_type}, expected {target_mag_type})")

    # Map stationMagnitudeIDs to Station Codes
    sm_map = {}
    for sm in root.findall('.//stationMagnitude'):
        sm_id = sm.get('publicID')
        wv = sm.find('waveformID')
        if wv is not None:
            sta_code = wv.get('stationCode')
            sm_map[sm_id] = sta_code

    # Check contributions to the preferred magnitude
    target_station_weight = 0.0
    target_station_present = False
    other_stations_included = False

    for contrib in pref_mag.findall('.//stationMagnitudeContribution'):
        sm_id = contrib.findtext('stationMagnitudeID')
        weight_text = contrib.findtext('weight')
        weight = float(weight_text) if weight_text is not None else 1.0
        
        sta_code = sm_map.get(sm_id)
        if sta_code == target_station:
            target_station_present = True
            target_station_weight = weight
        elif sta_code is not None and weight > 0:
            other_stations_included = True

    # Criterion D: Target station excluded - 35 pts
    # Either it's not in the contributions at all, or its weight is 0
    if not target_station_present or target_station_weight == 0:
        score += 35
        feedback_parts.append(f"Station {target_station} successfully excluded")
    else:
        feedback_parts.append(f"Station {target_station} still included (weight {target_station_weight})")

    # Criterion E: Other stations included - 15 pts
    if other_stations_included:
        score += 15
        feedback_parts.append("Other stations correctly retained in calculation")
    else:
        feedback_parts.append("No other stations contributing to magnitude")

    # Ensure all primary goals were achieved to pass
    passed = (score >= 80) and agency_id == expected_agency and (not target_station_present or target_station_weight == 0)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }