#!/usr/bin/env python3
"""
Verifier for zero_track_elevation_bulk task.

Programmatic Verification Strategy:
1. Verify the exported file exists and was modified during the task execution.
2. Verify structural integrity of the GPX (prevent deletion gaming).
3. Validate Native Garmin Namespaces (prevent pure python file generation).
4. Parse every `<ele>` tag to ensure bulk operation successfully zeroed the elevations.
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET

def verify_zero_track_elevation_bulk(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', 'Zeroed_Survey').lower()
    min_track_points = metadata.get('min_track_points', 1100)

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_gpx = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')

    try:
        # Load and verify JSON output details
        copy_from_env("C:\\workspace\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)

        output_exists = result.get('output_exists', False)
        created_during_task = result.get('file_created_during_task', False)
        
        if not output_exists:
            return {"passed": False, "score": 0, "feedback": "GPX output file not found at expected path."}
        
        if not created_during_task:
            return {"passed": False, "score": 0, "feedback": "Output file exists, but wasn't created/modified during this task."}

        # Copy the agent's GPX export
        copy_from_env("C:\\workspace\\output\\zeroed_survey.gpx", temp_gpx.name)

        try:
            tree = ET.parse(temp_gpx.name)
            root = tree.getroot()
        except ET.ParseError:
            return {"passed": False, "score": 0, "feedback": "GPX file is not valid XML."}

        # Define GPX standard namespace
        ns = {'gpx': 'http://www.topografix.com/GPX/1/1'}
        namespaces = dict([node for _, node in ET.iterparse(temp_gpx.name, events=['start-ns'])])

        score = 10
        feedback = ["XML Format Valid (10/10)"]

        # Criterion 1: Native Garmin Export Check (Anti-Python Gaming)
        if 'gpxx' in namespaces or 'http://www.garmin.com/xmlschemas/GpxExtensions/v3' in namespaces.values():
            score += 10
            feedback.append("Native Garmin Export Detected (10/10)")
        else:
            feedback.append("Missing Native Garmin Extensions (0/10)")

        # Locate Track Element
        trk = root.find('.//gpx:trk', ns)
        if trk is None:
            trk = root.find('.//trk') # Fallback if namespaces were stripped

        if trk is None:
            return {"passed": False, "score": score, "feedback": " | ".join(feedback) + " | No <trk> found in GPX"}

        # Criterion 2: Track Renamed
        name_elem = trk.find('gpx:name', ns)
        if name_elem is None:
            name_elem = trk.find('name')

        if name_elem is not None and name_elem.text and name_elem.text.strip().lower() == expected_name:
            score += 10
            feedback.append("Track Renamed (10/10)")
        else:
            got_name = name_elem.text if name_elem is not None else "None"
            feedback.append(f"Track Not Renamed properly. Got '{got_name}' (0/10)")

        # Criterion 3: Ensure data wasn't deleted 
        trkpts = trk.findall('.//gpx:trkpt', ns)
        if not trkpts:
            trkpts = trk.findall('.//trkpt')

        if len(trkpts) >= min_track_points:
            score += 30
            feedback.append(f"Original Point Count Preserved [{len(trkpts)}] (30/30)")
        else:
            feedback.append(f"Data Corrupted/Missing [{len(trkpts)} < {min_track_points}] (0/30)")

        # Criterion 4: Validate Bulk Elevation Edits
        all_zero = True
        ele_count = 0
        
        for pt in trkpts:
            ele = pt.find('gpx:ele', ns)
            if ele is None:
                ele = pt.find('ele')

            if ele is not None and ele.text:
                ele_count += 1
                try:
                    if abs(float(ele.text)) > 0.001:  # Check distance from zero
                        all_zero = False
                except ValueError:
                    all_zero = False

        if ele_count > 0 and ele_count == len(trkpts) and all_zero:
            score += 40
            feedback.append("All Track Point Elevations Zeroed (40/40)")
        else:
            feedback.append(f"Elevations Not Fully Zeroed [zero={all_zero}, evaluated={ele_count}/{len(trkpts)}] (0/40)")

        # Evaluate overall pass
        passed = (score >= 70) and all_zero and (len(trkpts) >= min_track_points)

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verifier runtime error: {e}"}
    finally:
        # Cleanup
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
        if os.path.exists(temp_gpx.name):
            os.unlink(temp_gpx.name)