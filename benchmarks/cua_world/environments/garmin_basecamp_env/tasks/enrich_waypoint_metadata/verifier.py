#!/usr/bin/env python3
"""
Verifier for enrich_waypoint_metadata task.

Verification Strategy (100 pts max):
1. Output file exists and created during task (10 pts)
2. Waypoint named correctly (20 pts)
3. Coordinates match exactly (15 pts)
4. Web link embedded correctly (15 pts)
5. Category assigned correctly (20 pts)
6. VLM Verification: Agent actually used UI dialogs/tabs (20 pts)
"""

import json
import os
import tempfile
import re
import xml.etree.ElementTree as ET

try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    HAS_VLM = True
except ImportError:
    HAS_VLM = False

def check_gpx_content(content):
    """
    Parses the GPX content for the required attributes.
    Uses robust regex fallbacks in case XML namespaces cause parsing failures.
    """
    found_name = False
    found_coords = False
    found_link = False
    found_category = False

    # Standard XML Parsing First
    try:
        root = ET.fromstring(content)
        # Strip namespaces dynamically for easier searching
        for elem in root.iter():
            if '}' in elem.tag:
                elem.tag = elem.tag.split('}', 1)[1]

        for wpt in root.findall('.//wpt'):
            name_el = wpt.find('name')
            if name_el is not None and name_el.text and 'Damaged Bridge B-42' in name_el.text:
                found_name = True

                # Check coords (Tolerance of ~50 meters / 0.0005 deg)
                lat = float(wpt.get('lat', 0))
                lon = float(wpt.get('lon', 0))
                if abs(lat - 42.45100) < 0.0005 and abs(lon - (-71.09800)) < 0.0005:
                    found_coords = True

                # Check Link
                for link_el in wpt.findall('link'):
                    if 'city.gov/engineering/reports/b42.pdf' in link_el.get('href', ''):
                        text_el = link_el.find('text')
                        if text_el is not None and 'Structural Assessment B-42' in text_el.text:
                            found_link = True

                # Check Category
                for cat in wpt.findall('.//Category'):
                    if cat.text and 'Maintenance_Priority_1' in cat.text:
                        found_category = True
    except Exception:
        pass

    # Regex fallback if XML is malformed or namespace issues occurred
    if not found_name:
        found_name = bool(re.search(r'<name>\s*Damaged Bridge B-42\s*</name>', content, re.IGNORECASE))
    
    if found_name and not found_coords:
        lat_m = re.search(r'lat="([-\d\.]+)"', content)
        lon_m = re.search(r'lon="([-\d\.]+)"', content)
        if lat_m and lon_m:
            try:
                if abs(float(lat_m.group(1)) - 42.45100) < 0.0005 and abs(float(lon_m.group(1)) - (-71.09800)) < 0.0005:
                    found_coords = True
            except:
                pass

    if found_name and not found_link:
        if 'city.gov/engineering/reports/b42.pdf' in content and 'Structural Assessment B-42' in content:
            found_link = True

    if found_name and not found_category:
        if 'Maintenance_Priority_1' in content:
            found_category = True

    return found_name, found_coords, found_link, found_category

def verify_enrich_waypoint_metadata(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Fetch Task Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env("C:\\workspace\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result data: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    output_exists = result_data.get('output_exists', False)
    file_created_during_task = result_data.get('file_created_during_task', False)

    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "GPX output file was not found."}
    
    if file_created_during_task:
        score += 10
        feedback_parts.append("File created during task (+10)")
    else:
        feedback_parts.append("Warning: File existed before task (possible gaming)")

    # 2. Fetch and Check GPX Content
    temp_gpx = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    found_name, found_coords, found_link, found_category = False, False, False, False
    
    try:
        copy_from_env("C:\\workspace\\output\\maintenance_export.gpx", temp_gpx.name)
        with open(temp_gpx.name, 'r', encoding='utf-8', errors='replace') as f:
            gpx_content = f.read()
            found_name, found_coords, found_link, found_category = check_gpx_content(gpx_content)
    except Exception as e:
        feedback_parts.append(f"Error parsing GPX: {e}")
    finally:
        if os.path.exists(temp_gpx.name):
            os.unlink(temp_gpx.name)

    if found_name:
        score += 20
        feedback_parts.append("Waypoint Name Correct (+20)")
    else:
        feedback_parts.append("Waypoint 'Damaged Bridge B-42' missing from GPX")

    if found_coords:
        score += 15
        feedback_parts.append("Coordinates Correct (+15)")
    else:
        feedback_parts.append("Coordinates incorrect or missing")

    if found_link:
        score += 15
        feedback_parts.append("Link embedded correctly (+15)")
    else:
        feedback_parts.append("Link incorrect or missing")

    if found_category:
        score += 20
        feedback_parts.append("Category embedded correctly (+20)")
    else:
        feedback_parts.append("Category incorrect or missing")

    # 3. Trajectory VLM Verification
    if HAS_VLM and 'query_vlm' in globals():
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames

            prompt = """Analyze this sequence of screenshots from Garmin BaseCamp.
            Did the agent open the Waypoint Properties dialog and interact with the metadata tabs?
            Look for a properties window with tabs like 'Properties', 'Notes', or 'Categories'.
            Respond in JSON format:
            {
                "properties_dialog_used": true/false
            }"""
            
            vlm_res = query_vlm(images=images, prompt=prompt)
            if vlm_res.get('success') and vlm_res.get('parsed', {}).get('properties_dialog_used', False):
                score += 20
                feedback_parts.append("VLM: Properties dialog interaction verified (+20)")
            else:
                feedback_parts.append("VLM: Could not confirm properties dialog usage")
        except Exception as e:
            feedback_parts.append(f"VLM verification skipped/failed: {e}")
    else:
        # Give free points if VLM module is not active, assuming programmatic checks passed
        score += 20
        feedback_parts.append("VLM offline. Assigned default (+20)")

    # 4. Final Evaluation
    passed = score >= 75 and output_exists and found_name and file_created_during_task
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }