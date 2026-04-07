#!/usr/bin/env python3
"""
Verifier for configure_scolv_event_filter task.

Verification Strategy:
1. Programmatic Check (60 points): Parse exported `scolv.cfg` to verify:
   - A new tab is added to `eventlist.tabs`
   - The label of the new tab is exactly "Significant"
   - The filter expression for the new tab enforces Magnitude >= 5.0
2. Anti-Gaming Check (10 points): Ensure config was actually modified during task.
3. VLM Verification (30 points): Analyze trajectory and final screenshot to confirm:
   - `scolv` is open.
   - The "Significant" tab is visible.
   - The event list is filtered (M7.5 visible, M3.5 hidden).

Pass Threshold: 60 points + core logic correctly configured.
"""

import os
import json
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating a SeisComP Origin Locator View (scolv) configuration task.
The user was asked to create a 'Significant' tab in the Event List to filter events with Magnitude >= 5.0.

Look at the final screenshot.
1. Is 'scolv' open on the screen?
2. Do you see 'Significant' as a tab or filter button in the Event List panel?
3. Is the 'Significant' tab currently selected/active?
4. Look at the events listed in the panel: 
   - Is the M7.5 Noto earthquake visible?
   - Is there ANY event smaller than M5.0 visible (e.g., a M3.5 event)?

Respond strictly in JSON format:
{
    "scolv_visible": true/false,
    "significant_tab_visible": true/false,
    "significant_tab_active": true/false,
    "m75_event_visible": true/false,
    "m35_event_hidden": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of what you see"
}
"""

def parse_seiscomp_config(config_text):
    """Parses a SeisComP .cfg file into a dictionary of key-value pairs."""
    config = {}
    for line in config_text.split('\n'):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if '=' in line:
            key, val = line.split('=', 1)
            config[key.strip()] = val.strip()
    return config

def verify_configure_scolv_event_filter(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    
    # 1. Read JSON result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Read exported config
    temp_cfg = tempfile.NamedTemporaryFile(delete=False, suffix='.cfg')
    config_text = ""
    try:
        copy_from_env("/tmp/exported_scolv.cfg", temp_cfg.name)
        with open(temp_cfg.name, 'r') as f:
            config_text = f.read()
    except Exception as e:
        logger.warning(f"Failed to read config file: {e}")
    finally:
        if os.path.exists(temp_cfg.name):
            os.unlink(temp_cfg.name)

    # Evaluate Anti-gaming
    if result.get("config_modified_during_task", False):
        score += 10
        feedback.append("Config was modified during task.")
    else:
        feedback.append("Warning: Config file does not appear to be modified during task.")

    # Evaluate Configuration Logic
    cfg_dict = parse_seiscomp_config(config_text)
    
    tab_ids = []
    tabs_entry = cfg_dict.get("eventlist.tabs", "")
    if tabs_entry:
        tab_ids = [t.strip() for t in tabs_entry.split(',')]
    
    found_tab = False
    correct_label = False
    correct_filter = False
    
    for tid in tab_ids:
        label_key = f"eventlist.tab.{tid}.label"
        filter_key = f"eventlist.tab.{tid}.filter"
        
        tab_label = cfg_dict.get(label_key, "").strip('"\'')
        tab_filter = cfg_dict.get(filter_key, "").strip('"\'').lower()
        
        if tab_label.lower() == "significant":
            found_tab = True
            correct_label = True
            
            # Check filter logic (e.g. "magnitude >= 5.0", "magnitude.value>=5")
            if 'magnitude' in tab_filter and ('>= 5' in tab_filter or '>=5' in tab_filter or '> 4.9' in tab_filter):
                correct_filter = True
                break

    if found_tab:
        score += 15
        feedback.append("Tab added to eventlist.tabs.")
    else:
        feedback.append("No 'Significant' tab profile found in eventlist.tabs.")

    if correct_label:
        score += 15
        feedback.append("Tab label correctly set to 'Significant'.")
        
    if correct_filter:
        score += 20
        feedback.append("Filter expression correctly checks for Magnitude >= 5.")
    elif found_tab:
        feedback.append("Filter expression incorrect or missing.")

    # Evaluate VLM (Trajectory + Final Screenshot)
    vlm_score = 0
    from gym_anything.vlm import get_final_screenshot
    
    try:
        final_screenshot = get_final_screenshot(traj)
        query_vlm = env_info.get("query_vlm")
        
        if query_vlm and final_screenshot:
            vlm_response = query_vlm(prompt=VLM_PROMPT, image=final_screenshot)
            if vlm_response.get("success"):
                vlm_parsed = vlm_response.get("parsed", {})
                
                scolv_vis = vlm_parsed.get("scolv_visible", False)
                tab_vis = vlm_parsed.get("significant_tab_visible", False)
                tab_act = vlm_parsed.get("significant_tab_active", False)
                m75_vis = vlm_parsed.get("m75_event_visible", False)
                m35_hid = vlm_parsed.get("m35_event_hidden", False)
                
                if scolv_vis and tab_vis:
                    vlm_score += 15
                    feedback.append("VLM: Significant tab is visible in scolv.")
                if tab_act and m75_vis and m35_hid:
                    vlm_score += 25
                    feedback.append("VLM: UI correctly filtered (M7.5 visible, noise hidden).")
                elif m75_vis and m35_hid:
                    vlm_score += 15
                    feedback.append("VLM: Event list appears filtered correctly.")
            else:
                feedback.append("VLM query failed.")
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        feedback.append("VLM verification skipped/errored.")

    score += vlm_score

    # Check passing criteria
    core_logic_passed = found_tab and correct_label and correct_filter
    ui_interaction_passed = vlm_score >= 15
    
    # Cap score at 100
    score = min(score, 100)
    
    # Needs logic + some form of evidence
    passed = score >= 60 and core_logic_passed
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "config_modified": result.get("config_modified_during_task", False),
            "core_logic_passed": core_logic_passed,
            "vlm_score": vlm_score
        }
    }