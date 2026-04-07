#!/usr/bin/env python3
"""
Verifier for attach_waypoint_document_link task.

Verification Strategy:
1. Programmatic: Check if 'linked_waypoint.gpx' exists and was created during the task.
2. XML Parsing: Verify that a waypoint named 'Test Site A' exists in the exported GPX.
3. XML Parsing: Verify that this waypoint contains a <link> child with an href to the PDF.
4. VLM (Anti-gaming): Verify trajectory screenshots show the user utilizing the Waypoint Properties UI (Links tab).
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import VLM utilities safely
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    logger.warning("VLM utilities not available.")
    VLM_AVAILABLE = False


def get_tag_name(elem):
    """Helper to safely get XML tag name ignoring namespaces."""
    return elem.tag.split('}')[-1] if '}' in elem.tag else elem.tag


def verify_attach_waypoint_document_link(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env function not available"}

    metadata = task_info.get('metadata', {})
    expected_waypoint_name = metadata.get('expected_waypoint_name', 'Test Site A')
    expected_link_substring = metadata.get('expected_link_substring', 'water_quality_report.pdf')

    score = 0
    feedback = []

    # 1. Fetch and read the task result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    output_exists = result.get('output_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)

    if not output_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Exported GPX file (C:\\workspace\\output\\linked_waypoint.gpx) not found."
        }

    if not file_created_during_task:
        feedback.append("Warning: File was not created/modified during the task timeframe.")

    score += 20
    feedback.append("File export successful (+20).")

    # 2. Fetch and parse the exported GPX file
    temp_gpx = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    try:
        copy_from_env("C:\\workspace\\output\\linked_waypoint.gpx", temp_gpx.name)
        tree = ET.parse(temp_gpx.name)
        root = tree.getroot()
    except ET.ParseError as e:
        return {"passed": False, "score": score, "feedback": f"Failed to parse GPX as valid XML: {e}"}
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Error loading GPX file: {e}"}
    finally:
        if os.path.exists(temp_gpx.name):
            os.unlink(temp_gpx.name)

    # 3. Analyze XML content
    waypoints = []
    for elem in root.iter():
        if get_tag_name(elem) == 'wpt':
            waypoints.append(elem)

    if not waypoints:
        return {"passed": False, "score": score, "feedback": f"GPX parsed, but no waypoints (<wpt>) found. {feedback[0]}"}

    renamed_correctly = False
    link_attached = False
    target_wpt = None

    for wpt in waypoints:
        name_text = ""
        wpt_link_href = ""
        
        for child in wpt.iter():
            tag = get_tag_name(child)
            if tag == 'name' and child.text:
                name_text = child.text.strip()
            elif tag == 'link':
                href = child.get('href', '')
                if href:
                    wpt_link_href = href
                
        if name_text == expected_waypoint_name:
            renamed_correctly = True
            target_wpt = wpt
            if expected_link_substring in wpt_link_href:
                link_attached = True
            break

    if renamed_correctly:
        score += 30
        feedback.append(f"Waypoint renamed to '{expected_waypoint_name}' (+30).")
    else:
        feedback.append(f"FAIL: No waypoint named '{expected_waypoint_name}' found in export.")

    if link_attached:
        score += 40
        feedback.append(f"Document link successfully attached to the waypoint (+40).")
    elif target_wpt is not None:
        feedback.append("FAIL: Target waypoint found, but document link pointing to the PDF is missing.")

    # 4. VLM Verification (Anti-gaming: Did they use the UI?)
    if VLM_AVAILABLE:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        images = frames + [final_img] if final_img else frames
        
        if images:
            prompt = """Look at these screenshots of a user interacting with Garmin BaseCamp.
Did the user open a 'Waypoint Properties' dialog window and access the 'Links' or 'References' tab to attach a file?
Respond with JSON strictly following this format:
{
    "used_links_tab": true/false
}"""
            try:
                vlm_res = query_vlm(images=images, prompt=prompt)
                if vlm_res and vlm_res.get("parsed", {}).get("used_links_tab", False):
                    score += 10
                    feedback.append("VLM confirmed use of Waypoint Properties UI (+10).")
                else:
                    feedback.append("VLM could not visually confirm the use of Waypoint Properties dialog.")
            except Exception as e:
                logger.warning(f"VLM query failed: {e}")
                feedback.append("VLM verification skipped due to error.")

    # Final Evaluation
    # Requirements: Export (20) + Renamed (30) + Link Attached (40) = 90
    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }