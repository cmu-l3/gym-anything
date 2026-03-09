#!/usr/bin/env python3
"""
Verifier for earthquake_network_link task.

Task: Add a Network Link to Google Earth Pro that displays real-time earthquake
data from the USGS earthquake feed.

Verification Strategy (Multi-Signal):
1. PRIMARY: Check myplaces.kml for NetworkLink with correct USGS URL (programmatic)
2. SECONDARY: VLM verification on trajectory frames to confirm workflow
3. ANTI-GAMING: Timestamp verification to ensure file was modified during task

Scoring:
- Network Link exists in myplaces.kml: 20 points
- Correct USGS URL configured: 25 points
- Descriptive name with keywords: 10 points
- File modified after task start: 10 points
- VLM: Earthquake markers visible on globe: 25 points
- VLM: Workflow progression (menu navigation, dialog): 10 points

Pass threshold: 70 points with URL correctly configured
"""

import json
import tempfile
import os
import logging
from pathlib import Path
from typing import Dict, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

EXPECTED_URL = "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/2.5_day.kml"
EXPECTED_KEYWORDS = ["usgs", "earthquake", "quake", "seismic", "2.5"]


# ============================================================
# VLM Prompts
# ============================================================

TRAJECTORY_VERIFICATION_PROMPT = """You are analyzing a sequence of screenshots showing an agent adding a Network Link in Google Earth Pro.

The task was to add a Network Link for USGS earthquake data (URL: https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/2.5_day.kml).

Look at these chronological screenshots and assess:

1. WORKFLOW_PROGRESSION: Did the agent navigate through the expected workflow?
   - Opening Add menu or Network Link dialog
   - Entering link name and URL
   - Confirming/saving the link

2. DIALOG_VISIBLE: At any point, is a "Network Link" or "Add" dialog visible?

3. PLACES_PANEL_VISIBLE: Is the Places panel (left sidebar) visible showing network links?

4. STATE_CHANGED: Do the frames show meaningful state changes (not the same screen repeated)?

Respond in JSON format:
{
    "workflow_progression": true/false,
    "dialog_visible": true/false,
    "places_panel_visible": true/false,
    "state_changed": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see across the frames"
}
"""

FINAL_STATE_PROMPT = """You are verifying the final state of a Google Earth Pro task.

The task was to add a Network Link displaying USGS earthquake data.

Look at this final screenshot and assess:

1. EARTHQUAKE_MARKERS_VISIBLE: Are there colored circular markers (typically red, orange, yellow, or colored circles) scattered on the globe representing earthquake locations?
   - These appear as small colored dots/circles on seismically active regions
   - Common locations: Pacific Ring of Fire, fault lines, tectonic boundaries

2. NETWORK_LINK_IN_PLACES: Is there a Network Link entry visible in the Places panel (left sidebar)?
   - Look for a folder-like icon with network indicator
   - Look for text containing "earthquake", "USGS", or similar

3. GOOGLE_EARTH_ACTIVE: Is this clearly Google Earth Pro showing satellite/terrain imagery?

4. DATA_LOADED: Does the application appear to have loaded external data (markers, overlays)?

Respond in JSON format:
{
    "earthquake_markers_visible": true/false,
    "network_link_in_places": true/false,
    "google_earth_active": true/false,
    "data_loaded": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}
"""


def verify_earthquake_network_link(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that USGS earthquake Network Link was properly configured.
    
    Uses MULTIPLE INDEPENDENT SIGNALS to prevent gaming:
    1. Programmatic: Check myplaces.kml for NetworkLink configuration
    2. Timestamp: Verify file was modified during task window
    3. VLM Trajectory: Verify workflow progression through frames
    4. VLM Final: Verify earthquake markers are displayed
    
    Args:
        traj: Trajectory data with frames, steps, episode_dir
        env_info: Environment info with copy_from_env and query_vlm
        task_info: Task info with metadata
        
    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available for verification"
        }
    
    metadata = task_info.get('metadata', {})
    expected_url = metadata.get('expected_url', EXPECTED_URL)
    
    feedback_parts = []
    score = 0
    details = {}
    
    # ============================================================
    # STEP 1: Copy and parse task result JSON from container
    # ============================================================
    result_data = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
        details['result_data'] = result_data
    except Exception as e:
        logger.warning(f"Could not read task result: {e}")
        details['result_error'] = str(e)
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ============================================================
    # STEP 2: Copy and parse myplaces.kml directly for verification
    # ============================================================
    myplaces_paths = metadata.get('myplaces_paths', [
        "/home/ga/.googleearth/myplaces.kml",
        "/home/ga/.config/Google/GoogleEarthPro/myplaces.kml"
    ])
    
    kml_content = None
    kml_path_found = None
    
    for kml_path in myplaces_paths:
        temp_kml = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
        try:
            copy_from_env(kml_path, temp_kml.name)
            with open(temp_kml.name, 'r') as f:
                kml_content = f.read()
            kml_path_found = kml_path
            break
        except Exception as e:
            logger.debug(f"Could not copy {kml_path}: {e}")
        finally:
            if os.path.exists(temp_kml.name):
                os.unlink(temp_kml.name)
    
    details['kml_path_found'] = kml_path_found
    details['kml_content_length'] = len(kml_content) if kml_content else 0
    
    # ============================================================
    # CRITERION 1: Network Link exists in myplaces.kml (20 points)
    # ============================================================
    network_link_exists = False
    usgs_link_details = None
    
    if kml_content:
        try:
            import xml.etree.ElementTree as ET
            root = ET.fromstring(kml_content)
            
            for elem in root.iter():
                if 'NetworkLink' in elem.tag:
                    link_info = {"name": None, "href": None}
                    
                    for child in elem.iter():
                        tag = child.tag.split('}')[-1]
                        if tag == 'name' and child.text:
                            link_info["name"] = child.text.strip()
                        elif tag == 'href' and child.text:
                            link_info["href"] = child.text.strip()
                    
                    if link_info["href"]:
                        network_link_exists = True
                        if "earthquake.usgs.gov" in link_info["href"]:
                            usgs_link_details = link_info
                            
        except Exception as e:
            logger.warning(f"Error parsing KML: {e}")
            details['kml_parse_error'] = str(e)
    
    details['network_link_exists'] = network_link_exists
    details['usgs_link_details'] = usgs_link_details
    
    if usgs_link_details:
        score += 20
        feedback_parts.append("✅ USGS Network Link found in Places")
    elif network_link_exists:
        score += 10
        feedback_parts.append("⚠️ Network Link exists but not USGS earthquake feed")
    else:
        feedback_parts.append("❌ No Network Link found in myplaces.kml")
    
    # ============================================================
    # CRITERION 2: Correct USGS URL configured (25 points)
    # ============================================================
    url_correct = False
    url_partial = False
    
    if usgs_link_details and usgs_link_details.get("href"):
        href = usgs_link_details["href"]
        url_correct = expected_url in href or href == expected_url
        url_partial = "earthquake.usgs.gov" in href
    
    details['url_correct'] = url_correct
    details['url_partial'] = url_partial
    
    if url_correct:
        score += 25
        feedback_parts.append("✅ Correct USGS earthquake feed URL")
    elif url_partial:
        score += 15
        feedback_parts.append("⚠️ USGS URL present but may not be exact match")
    else:
        feedback_parts.append("❌ USGS earthquake URL not found")
    
    # ============================================================
    # CRITERION 3: Descriptive name with keywords (10 points)
    # ============================================================
    name_good = False
    link_name = usgs_link_details.get("name", "") if usgs_link_details else ""
    
    if link_name:
        name_lower = link_name.lower()
        name_good = any(kw in name_lower for kw in EXPECTED_KEYWORDS)
    
    details['link_name'] = link_name
    details['name_has_keywords'] = name_good
    
    if name_good:
        score += 10
        feedback_parts.append(f"✅ Descriptive name: '{link_name}'")
    elif link_name:
        score += 5
        feedback_parts.append(f"⚠️ Name '{link_name}' lacks descriptive keywords")
    else:
        feedback_parts.append("❌ Network Link has no name")
    
    # ============================================================
    # CRITERION 4: File modified after task start (10 points)
    # Anti-gaming: ensure work was done during the task window
    # ============================================================
    file_modified = result_data.get('file_modified_during_task', False)
    task_start = result_data.get('task_start', 0)
    task_end = result_data.get('task_end', 0)
    
    details['task_start'] = task_start
    details['task_end'] = task_end
    details['file_modified_during_task'] = file_modified
    
    if file_modified:
        score += 10
        feedback_parts.append("✅ Configuration saved during task")
    else:
        feedback_parts.append("⚠️ Could not verify file was modified during task")
    
    # ============================================================
    # CRITERION 5 & 6: VLM Verification (35 points total)
    # ============================================================
    vlm_trajectory_score = 0
    vlm_final_score = 0
    
    if query_vlm:
        # Get trajectory frames for workflow verification
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            trajectory_frames = sample_trajectory_frames(traj, n=5)
            final_screenshot = get_final_screenshot(traj)
            
            details['trajectory_frames_count'] = len(trajectory_frames) if trajectory_frames else 0
            details['final_screenshot_available'] = final_screenshot is not None
            
            # VLM Check 1: Trajectory workflow (10 points)
            if trajectory_frames and len(trajectory_frames) >= 2:
                try:
                    traj_result = query_vlm(
                        prompt=TRAJECTORY_VERIFICATION_PROMPT,
                        images=trajectory_frames
                    )
                    
                    if traj_result.get("success"):
                        parsed = traj_result.get("parsed", {})
                        details['vlm_trajectory_result'] = parsed
                        
                        workflow_ok = parsed.get("workflow_progression", False)
                        state_changed = parsed.get("state_changed", False)
                        confidence = parsed.get("confidence", "low")
                        
                        if workflow_ok and state_changed:
                            vlm_trajectory_score = 10
                            feedback_parts.append("✅ VLM: Workflow progression verified")
                        elif workflow_ok or state_changed:
                            vlm_trajectory_score = 5
                            feedback_parts.append("⚠️ VLM: Partial workflow evidence")
                        else:
                            feedback_parts.append("❌ VLM: No clear workflow progression")
                    else:
                        details['vlm_trajectory_error'] = traj_result.get('error', 'Unknown')
                        
                except Exception as e:
                    logger.warning(f"VLM trajectory check failed: {e}")
                    details['vlm_trajectory_exception'] = str(e)
            
            # VLM Check 2: Final state - earthquake markers (25 points)
            if final_screenshot:
                try:
                    final_result = query_vlm(
                        prompt=FINAL_STATE_PROMPT,
                        image=final_screenshot
                    )
                    
                    if final_result.get("success"):
                        parsed = final_result.get("parsed", {})
                        details['vlm_final_result'] = parsed
                        
                        markers_visible = parsed.get("earthquake_markers_visible", False)
                        link_in_places = parsed.get("network_link_in_places", False)
                        data_loaded = parsed.get("data_loaded", False)
                        confidence = parsed.get("confidence", "low")
                        
                        # Score based on visual evidence
                        if markers_visible:
                            vlm_final_score += 15
                            feedback_parts.append("✅ VLM: Earthquake markers visible on globe")
                        
                        if link_in_places:
                            vlm_final_score += 5
                            feedback_parts.append("✅ VLM: Network Link visible in Places panel")
                        
                        if data_loaded and not markers_visible:
                            vlm_final_score += 5
                            feedback_parts.append("⚠️ VLM: Data appears loaded (markers may be loading)")
                        
                        if vlm_final_score == 0:
                            feedback_parts.append("❌ VLM: No visual evidence of earthquake data")
                    else:
                        details['vlm_final_error'] = final_result.get('error', 'Unknown')
                        
                except Exception as e:
                    logger.warning(f"VLM final check failed: {e}")
                    details['vlm_final_exception'] = str(e)
                    
        except ImportError as e:
            logger.warning(f"Could not import VLM utilities: {e}")
            details['vlm_import_error'] = str(e)
    else:
        feedback_parts.append("⚠️ VLM verification not available")
    
    score += vlm_trajectory_score + vlm_final_score
    details['vlm_trajectory_score'] = vlm_trajectory_score
    details['vlm_final_score'] = vlm_final_score
    
    # ============================================================
    # Final scoring and pass/fail determination
    # ============================================================
    
    # Key criteria: URL must be at least partially correct
    key_criteria_met = url_correct or url_partial
    
    # Pass threshold: 70 points with key criteria
    passed = score >= 70 and key_criteria_met
    
    # Alternative pass: Strong programmatic evidence even without VLM
    if not passed and score >= 55 and url_correct and file_modified:
        passed = True
        feedback_parts.append("✓ Passed via strong programmatic evidence")
    
    details['score_breakdown'] = {
        'network_link_exists': 20 if usgs_link_details else (10 if network_link_exists else 0),
        'url_correct': 25 if url_correct else (15 if url_partial else 0),
        'name_keywords': 10 if name_good else (5 if link_name else 0),
        'file_modified': 10 if file_modified else 0,
        'vlm_trajectory': vlm_trajectory_score,
        'vlm_final': vlm_final_score
    }
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": min(score, 100),  # Cap at 100
        "feedback": feedback,
        "details": details
    }


if __name__ == "__main__":
    # Test mode
    print("Verifier module loaded successfully")
    print(f"Expected URL: {EXPECTED_URL}")
    print(f"Expected keywords: {EXPECTED_KEYWORDS}")