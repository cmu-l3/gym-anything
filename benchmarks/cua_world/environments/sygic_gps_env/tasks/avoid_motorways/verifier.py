#!/usr/bin/env python3
"""
Verifier for avoid_motorways task.

Strategy:
1. Configuration Check: Compare initial vs final Shared Preferences files to detect changes in routing settings.
   - Look for keys containing "highway", "motorway", "avoid".
   - Verify values changed (e.g., true -> false or false -> true).
2. Visual Check (VLM): Analyze trajectory to verify the agent navigated the settings menu correctly.
"""

import os
import json
import tempfile
import logging
import xml.etree.ElementTree as ET
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_avoid_motorways(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    
    # Setup temporary directory for analysis
    with tempfile.TemporaryDirectory() as temp_dir:
        # =========================================================
        # 1. Retrieve Data from Environment
        # =========================================================
        try:
            # Copy result manifest
            copy_from_env("/sdcard/task_data/result_manifest.json", f"{temp_dir}/manifest.json")
            
            # Copy prefs directories
            # Note: copy_from_env might copy single files or dirs. 
            # We assume recursive copy for dirs or we copy known likely files.
            # Sygic prefs are usually in com.sygic.aura_preferences.xml or similar.
            os.makedirs(f"{temp_dir}/initial", exist_ok=True)
            os.makedirs(f"{temp_dir}/final", exist_ok=True)
            
            # Attempt to copy entire directory content if supported, otherwise specific patterns
            # Since we don't know the exact file list, we'll try to copy the most common ones
            pref_files = [
                "com.sygic.aura_preferences.xml",
                "settings.xml",
                "routing.xml", 
                "WorldSettings.xml"
            ]
            
            # Helper to copy files
            copied_files = []
            for p_file in pref_files:
                try:
                    copy_from_env(f"/sdcard/task_data/initial_prefs/{p_file}", f"{temp_dir}/initial/{p_file}")
                    copy_from_env(f"/sdcard/task_data/final_prefs/{p_file}", f"{temp_dir}/final/{p_file}")
                    copied_files.append(p_file)
                except Exception:
                    pass # File might not exist
                    
        except Exception as e:
            logger.warning(f"Data retrieval partial failure: {e}")

        # =========================================================
        # 2. Analyze Configuration Changes (Prefs Diff)
        # =========================================================
        config_changed_correctly = False
        relevant_keys_found = []
        
        for filename in copied_files:
            init_tree = parse_xml_safely(f"{temp_dir}/initial/{filename}")
            final_tree = parse_xml_safely(f"{temp_dir}/final/{filename}")
            
            if not init_tree or not final_tree:
                continue
                
            changes = diff_xml_prefs(init_tree, final_tree)
            
            # Check for relevant keywords in changes
            keywords = ["highway", "motorway", "avoid", "route", "toll"]
            for key, (old_val, new_val) in changes.items():
                key_lower = key.lower()
                if any(kw in key_lower for kw in keywords):
                    relevant_keys_found.append(f"{key}: {old_val} -> {new_val}")
                    
                    # Logic: "avoid" keys should likely become true
                    # "use" keys should likely become false
                    if "avoid" in key_lower and is_truthy(new_val) and not is_truthy(old_val):
                        config_changed_correctly = True
                        feedback.append(f"Setting '{key}' enabled.")
                    elif ("use" in key_lower or "allow" in key_lower) and not is_truthy(new_val) and is_truthy(old_val):
                        config_changed_correctly = True
                        feedback.append(f"Setting '{key}' disabled.")

        if config_changed_correctly:
            score += 50
            feedback.append("Configuration file change detected confirming avoidance.")
        elif len(relevant_keys_found) > 0:
            score += 20
            feedback.append(f"Relevant settings changed but direction unclear: {relevant_keys_found}")
        else:
            feedback.append("No relevant configuration changes detected in shared preferences.")

        # =========================================================
        # 3. VLM Verification (Trajectory Analysis)
        # =========================================================
        # Even if config check passes, we want to verify the UI interaction
        # If config check fails (maybe file didn't flush), VLM is fallback
        
        frames = sample_trajectory_frames(traj, n=5)
        final_screen = get_final_screenshot(traj)
        
        if final_screen:
            all_images = frames + [final_screen]
            
            prompt = """
            You are verifying a GPS navigation configuration task.
            The user wants to 'Avoid Motorways' (or Highways).
            
            Look at the image sequence. Determine:
            1. Did the user navigate to Settings?
            2. Did they find 'Route Planning', 'Route Settings', or 'Toll roads & avoidances'?
            3. Did they toggle an option related to 'Motorways' or 'Highways'?
            4. Does the final state show the setting is configured to AVOID motorways (e.g. toggle ON for 'Avoid Motorways' or toggle OFF for 'Use Motorways')?
            
            Output JSON:
            {
                "settings_opened": boolean,
                "routing_menu_found": boolean,
                "motorway_option_interacted": boolean,
                "final_state_correct": boolean,
                "confidence": "low|medium|high"
            }
            """
            
            try:
                vlm_res = query_vlm(images=all_images, prompt=prompt)
                parsed = vlm_res.get("parsed", {})
                
                vlm_score = 0
                if parsed.get("settings_opened"): vlm_score += 10
                if parsed.get("routing_menu_found"): vlm_score += 15
                if parsed.get("motorway_option_interacted"): vlm_score += 15
                if parsed.get("final_state_correct"): vlm_score += 10
                
                # Boost confidence
                if parsed.get("confidence") == "high":
                    score += vlm_score
                else:
                    score += int(vlm_score * 0.8)
                
                if vlm_score > 0:
                    feedback.append(f"Visual verification: Settings={parsed.get('settings_opened')}, Interaction={parsed.get('motorway_option_interacted')}")
                    
            except Exception as e:
                logger.error(f"VLM error: {e}")
                feedback.append("Visual verification failed to run.")

    # Final scoring logic
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }

def parse_xml_safely(path):
    """Parses Android SharedPrefs XML."""
    try:
        if not os.path.exists(path): return None
        return ET.parse(path)
    except Exception:
        return None

def diff_xml_prefs(tree1, tree2):
    """Returns dict of changed keys {key: (old_val, new_val)}."""
    def get_map(tree):
        m = {}
        root = tree.getroot()
        for child in root:
            # key is in 'name' attribute
            k = child.get('name')
            if not k: continue
            # value is text content or 'value' attr for some types
            v = child.text if child.text else child.get('value', 'true' if child.tag=='boolean' else '')
            m[k] = v
        return m

    m1 = get_map(tree1)
    m2 = get_map(tree2)
    changes = {}
    
    # Check modified or new
    for k, v2 in m2.items():
        v1 = m1.get(k)
        if v1 != v2:
            changes[k] = (v1, v2)
            
    return changes

def is_truthy(val):
    if val is None: return False
    return str(val).lower() in ['true', '1', 'on', 'yes']