#!/usr/bin/env python3
"""
Verifier for multisite_research_network task.

Verifies:
1. 3 new ground stations created with accurate coordinates (anti-gaming: mtime checks)
2. 3 new modules created with correct satellites
3. Per-module QTH assignments mapping the modules to the newly created ground stations
4. Trajectory validation ensuring GPredict UI was actively used (via VLM)
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def parse_gpredict_file(content):
    """Parse GPredict's flat INI-like structure robustly without configparser exceptions."""
    props = {}
    for line in content.split('\n'):
        line = line.strip()
        if line and '=' in line and not line.startswith('['):
            k, v = line.split('=', 1)
            props[k.strip().upper()] = v.strip()
    return props

def is_within_tolerance(val_str, expected, tolerance):
    try:
        val = float(val_str)
        return abs(val - expected) <= tolerance
    except (ValueError, TypeError):
        return False

def check_qth_assignment(assigned_qth, expected_qth_name):
    """Normalize and compare the QTH file assignment strings."""
    assigned = assigned_qth.strip().lower()
    expected = expected_qth_name.strip().lower()
    
    # Strip extensions for safe comparison (e.g., 'mit_haystack.qth' -> 'mit_haystack')
    if assigned.endswith('.qth'):
        assigned = assigned[:-4]
    if expected.endswith('.qth'):
        expected = expected[:-4]
        
    return assigned == expected

def verify_multisite_research_network(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_qth = metadata.get('ground_stations', {})
    expected_mods = metadata.get('modules', {})

    # 1. Retrieve the exported JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_path = temp_file.name
    temp_file.close()

    try:
        copy_from_env("/tmp/multisite_research_network_result.json", temp_path)
        with open(temp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)

    score = 0
    feedback_parts = []
    task_start = result.get('task_start_timestamp', 0)
    
    # Pre-parse file contents into dictionaries
    qth_data = {}
    for name, data in result.get('qth_files', {}).items():
        if "content" in data:
            qth_data[name] = {
                "props": parse_gpredict_file(data["content"]),
                "mtime": data.get("mtime", 0)
            }
            
    mod_data = {}
    for name, data in result.get('mod_files', {}).items():
        if "content" in data:
            mod_data[name] = {
                "props": parse_gpredict_file(data["content"]),
                "mtime": data.get("mtime", 0)
            }

    # =======================================================
    # CRITERION 1: Ground Stations (3 x 8 = 24 points)
    # =======================================================
    # We find stations either by exact expected filename or by close coordinate match
    found_qth_names = {}
    
    for expected_name, coords in expected_qth.items():
        matched_file = None
        exact_file = f"{expected_name}.qth"
        
        # Look for exact filename match first
        for qth_file, data in qth_data.items():
            if qth_file.lower() == exact_file.lower():
                matched_file = qth_file
                break
                
        # Fallback: search by coordinates
        if not matched_file:
            for qth_file, data in qth_data.items():
                props = data["props"]
                if (is_within_tolerance(props.get("LAT"), coords["lat"], 0.1) and 
                    is_within_tolerance(props.get("LON"), coords["lon"], 0.1)):
                    matched_file = qth_file
                    break
        
        if matched_file:
            data = qth_data[matched_file]
            props = data["props"]
            # Verify coordinates and creation time
            lat_ok = is_within_tolerance(props.get("LAT"), coords["lat"], 0.1)
            lon_ok = is_within_tolerance(props.get("LON"), coords["lon"], 0.1)
            alt_ok = is_within_tolerance(props.get("ALT"), coords["alt"], 50)
            mtime_ok = data["mtime"] >= task_start
            
            if lat_ok and lon_ok and alt_ok and mtime_ok:
                score += 8
                feedback_parts.append(f"QTH {expected_name} correct ({matched_file})")
                found_qth_names[expected_name] = matched_file  # Save mapping for module checks
            else:
                feedback_parts.append(f"QTH {expected_name} found but imperfect: lat={lat_ok}, lon={lon_ok}, alt={alt_ok}, new={mtime_ok}")
        else:
            feedback_parts.append(f"QTH {expected_name} NOT FOUND")

    # =======================================================
    # CRITERION 2 & 3: Modules and QTH Mapping 
    # Existence (2 pts), Satellites (10 pts total), QTH Assignment (6 pts) = 54 pts
    # =======================================================
    for mod_name, requirements in expected_mods.items():
        matched_mod = None
        exact_mod = f"{mod_name}.mod"
        
        for mf, data in mod_data.items():
            if mf.lower() == exact_mod.lower():
                matched_mod = mf
                break
                
        if matched_mod:
            data = mod_data[matched_mod]
            props = data["props"]
            mtime_ok = data["mtime"] >= task_start
            
            if mtime_ok:
                score += 2  # Module newly created
            
            # Extract satellites as a set of integers
            sat_str = props.get("SATELLITES", "")
            actual_sats = set()
            for s in sat_str.replace(',', ';').split(';'):
                s = s.strip()
                if s.isdigit():
                    actual_sats.add(int(s))
                    
            # Check required satellites
            req_sats = set(requirements["satellites"])
            sats_found = req_sats.intersection(actual_sats)
            
            # Score proportionally based on how many required sats are present
            sat_ratio = len(sats_found) / len(req_sats) if req_sats else 0
            sat_score = int(10 * sat_ratio)
            score += sat_score
            
            if sat_ratio == 1.0:
                feedback_parts.append(f"Module {mod_name}: all sats correct")
            else:
                feedback_parts.append(f"Module {mod_name}: {len(sats_found)}/{len(req_sats)} sats found")
                
            # Check per-module QTH assignment (the core unique feature of this task)
            assigned_qth = props.get("QTHFILE", "")
            target_qth_logical = requirements["qth"]
            
            # The agent might have named it exactly 'MIT_Haystack' OR whatever the actual filename was
            actual_qth_filename = found_qth_names.get(target_qth_logical, target_qth_logical)
            
            if check_qth_assignment(assigned_qth, actual_qth_filename) or check_qth_assignment(assigned_qth, target_qth_logical):
                score += 6
                feedback_parts.append(f"Module {mod_name}: QTH assigned correctly ({assigned_qth})")
            else:
                feedback_parts.append(f"Module {mod_name}: QTH assignment missing/wrong (got '{assigned_qth}', expected '{target_qth_logical}')")
                
        else:
            feedback_parts.append(f"Module {mod_name} NOT FOUND")

    # =======================================================
    # CRITERION 4: Visual/VLM Verification (22 points)
    # =======================================================
    vlm_score = 0
    if result.get("gpredict_running", False):
        vlm_score += 5  # Base points just for keeping app open
        feedback_parts.append("App was running at end.")
        
        # Query VLM using trajectory frames to ensure workflow was executed
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                prompt = """You are verifying a user configuring satellite tracking software (GPredict).
                Look at these frames over time.
                1. Is the GPredict application visible?
                2. Can you see tracking module windows/lists with satellites inside them?
                3. Is there evidence the user navigated dialogs (like creating a ground station or module)?
                
                Respond in JSON:
                {
                  "app_visible": true/false,
                  "modules_visible": true/false,
                  "dialog_activity": true/false
                }"""
                
                vlm_resp = query_vlm(images=images, prompt=prompt)
                parsed = vlm_resp.get("parsed", {})
                
                if parsed.get("app_visible"): vlm_score += 5
                if parsed.get("modules_visible"): vlm_score += 6
                if parsed.get("dialog_activity"): vlm_score += 6
                
                feedback_parts.append(f"VLM Verification: {parsed}")
            else:
                feedback_parts.append("No trajectory images available for VLM.")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback_parts.append("VLM verification skipped/failed.")
    else:
        feedback_parts.append("GPredict was NOT running at end (0 VLM points).")
        
    score += vlm_score

    # Final tally
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }