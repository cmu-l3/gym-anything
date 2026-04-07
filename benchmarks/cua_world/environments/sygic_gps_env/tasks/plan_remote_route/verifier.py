#!/usr/bin/env python3
"""
Verifier for plan_remote_route task (Sygic GPS).

Task: Plan a route from Kabul to Kandahar.
Verifies:
1. App is running.
2. Final screenshot visually confirms route from Kabul to Kandahar.
3. UI dump XML contains text "Kabul" and "Kandahar" (and NOT "Current Location" in start field).
"""

import json
import os
import tempfile
import logging
import xml.etree.ElementTree as ET
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_plan_remote_route(traj, env_info, task_info):
    """
    Verify the agent planned a route from Kabul to Kandahar.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check App Running (10 pts)
    if result_data.get("app_running", False):
        score += 10
        feedback_parts.append("App is running")
    else:
        feedback_parts.append("App not running")

    # 3. Retrieve and Parse UI Dump (XML) (30 pts)
    # We look for "Kabul" and "Kandahar" text in the UI
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    has_xml_evidence = False
    found_kabul = False
    found_kandahar = False
    
    try:
        copy_from_env("/sdcard/ui_dump.xml", temp_xml.name)
        tree = ET.parse(temp_xml.name)
        root = tree.getroot()
        
        # Search all nodes for text attributes
        # We are lenient with case and whitespace
        for node in root.iter():
            text = (node.get("text") or "").lower()
            content_desc = (node.get("content-desc") or "").lower()
            full_text = text + " " + content_desc
            
            if "kabul" in full_text:
                found_kabul = True
            if "kandahar" in full_text or "qandahar" in full_text:
                found_kandahar = True
        
        has_xml_evidence = True
    except Exception as e:
        logger.warning(f"XML parsing failed: {e}")
        feedback_parts.append("UI dump analysis failed")
    finally:
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)

    if found_kabul:
        score += 15
        feedback_parts.append("Found 'Kabul' in UI")
    else:
        feedback_parts.append("Start point 'Kabul' NOT found in UI text")

    if found_kandahar:
        score += 15
        feedback_parts.append("Found 'Kandahar' in UI")
    else:
        feedback_parts.append("Destination 'Kandahar' NOT found in UI text")

    # 4. VLM Verification (60 pts)
    # This is the most reliable check for the "From/To" relationship
    final_screenshot = get_final_screenshot(traj)
    
    if final_screenshot:
        prompt = """
        Analyze this screenshot from a GPS navigation app.
        The user should have planned a route.
        
        1. Is a route preview visible (map with a highlighted path)?
        2. Is the Start Point set to "Kabul" (or similar spelling)? It MUST NOT be "Current Location" or "My Position".
        3. Is the Destination set to "Kandahar" (or similar spelling)?
        
        Return JSON:
        {
            "route_preview_visible": boolean,
            "start_is_kabul": boolean,
            "destination_is_kandahar": boolean,
            "current_location_is_start": boolean
        }
        """
        
        vlm_res = query_vlm(prompt=prompt, image=final_screenshot)
        
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            
            # Criterion: Route Preview Visible
            if parsed.get("route_preview_visible"):
                score += 10
                feedback_parts.append("Route preview visible")
            
            # Criterion: Start is Kabul
            if parsed.get("start_is_kabul") and not parsed.get("current_location_is_start"):
                score += 25
                feedback_parts.append("VLM confirms Start: Kabul")
            elif parsed.get("current_location_is_start"):
                feedback_parts.append("VLM indicates Start is still Current Location (FAIL)")
                # Penalize score significantly if they didn't change start
                score = min(score, 40) 
            else:
                feedback_parts.append("VLM could not confirm Start: Kabul")

            # Criterion: Destination is Kandahar
            if parsed.get("destination_is_kandahar"):
                score += 25
                feedback_parts.append("VLM confirms Dest: Kandahar")
            else:
                feedback_parts.append("VLM could not confirm Dest: Kandahar")
        else:
            feedback_parts.append("VLM analysis failed")
    else:
        feedback_parts.append("No final screenshot available")

    # 5. Final Pass Logic
    # Must have reasonable score AND explicitly found the cities
    # (XML or VLM confirmation is acceptable for the cities)
    cities_confirmed = (found_kabul or (vlm_res.get("parsed", {}).get("start_is_kabul"))) and \
                       (found_kandahar or (vlm_res.get("parsed", {}).get("destination_is_kandahar")))

    passed = (score >= 80) and cities_confirmed
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }