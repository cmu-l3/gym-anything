#!/usr/bin/env python3
"""
Verifier for configure_sensor_node_api@1 task.
Verifies Emoncms API usage by checking database state and agent's output file.
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_sensor_node_api(traj, env_info, task_info):
    """
    Verify the sensor node configuration task.
    
    Rubric (100 pts total):
    - [15] 3 Inputs exist under 'office_env' with correct names
    - [15] 3 Feeds exist with tag 'office_env' with correct names
    - [10] Feed engines (PHPFina=5) and intervals are correct (checked indirectly via engine)
    - [5]  Feed units are correct (°C, %, ppm)
    - [15] Input processes configured (Log to Feed)
    - [10] Feeds have received data (non-null values)
    - [10] Config file exists and is valid JSON
    - [10] Config file feed_ids match database (prevents guessing)
    - [5]  Config file last_values are plausible
    - [5]  Anti-gaming: timestamps post-date task start
    
    Pass Threshold: 70 pts AND mandatory criteria (inputs exist, feeds exist, processes set).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Parse data
    task_start = result.get("task_start", 0)
    db_inputs = result.get("database", {}).get("inputs", [])
    db_feeds = result.get("database", {}).get("feeds", [])
    fs_config = result.get("file_system", {})
    
    # ----------------------------------------------------------------
    # 1. Verify Inputs (15 pts)
    # ----------------------------------------------------------------
    expected_inputs = {'temperature', 'humidity', 'co2'}
    found_inputs = {i['name'] for i in db_inputs}
    
    if expected_inputs.issubset(found_inputs):
        score += 15
        feedback.append("All 3 inputs created correctly.")
    elif len(found_inputs) == 3:
        score += 8
        feedback.append(f"3 inputs created but names incorrect: {found_inputs}")
    elif len(found_inputs) > 0:
        score += 5
        feedback.append(f"Found {len(found_inputs)} inputs (expected 3).")
    else:
        feedback.append("No inputs found for office_env.")

    # ----------------------------------------------------------------
    # 2. Verify Feeds Existence & Naming (15 pts)
    # ----------------------------------------------------------------
    expected_feeds = {'office_env_temperature', 'office_env_humidity', 'office_env_co2'}
    found_feeds_map = {f['name']: f for f in db_feeds}
    found_feed_names = set(found_feeds_map.keys())
    
    if expected_feeds.issubset(found_feed_names):
        score += 15
        feedback.append("All 3 feeds created correctly.")
    elif len(found_feed_names) == 3:
        score += 8
        feedback.append(f"3 feeds created but names incorrect: {found_feed_names}")
    elif len(found_feed_names) > 0:
        score += 5
        feedback.append(f"Found {len(found_feed_names)} feeds (expected 3).")
    else:
        feedback.append("No feeds found for office_env.")

    # ----------------------------------------------------------------
    # 3. Verify Feed Engines (10 pts)
    # ----------------------------------------------------------------
    # Engine 5 is PHPFina
    engines_ok = all(str(f['engine']) == '5' for f in db_feeds)
    if engines_ok and len(db_feeds) >= 3:
        score += 10
        feedback.append("Feed engines correct (PHPFina).")
    elif len(db_feeds) > 0:
        feedback.append("Some feed engines incorrect (should be PHPFina/5).")

    # ----------------------------------------------------------------
    # 4. Verify Feed Units (5 pts)
    # ----------------------------------------------------------------
    # Check simplified mapping
    units_ok = 0
    for f in db_feeds:
        name = f['name']
        unit = f['unit'].lower() if f['unit'] else ""
        if 'temperature' in name and ('c' in unit or 'deg' in unit):
            units_ok += 1
        elif 'humidity' in name and ('%' in unit or 'percent' in unit):
            units_ok += 1
        elif 'co2' in name and 'ppm' in unit:
            units_ok += 1
            
    if units_ok >= 3:
        score += 5
        feedback.append("Feed units correct.")
    elif units_ok > 0:
        score += 2
        feedback.append(f"Partial unit correctness ({units_ok}/3).")

    # ----------------------------------------------------------------
    # 5. Verify Input Processes (15 pts)
    # ----------------------------------------------------------------
    # Look for "1:<feed_id>" pattern in processList
    processes_ok = 0
    for inp in db_inputs:
        plist = inp.get('processList', '')
        # Pattern: Process ID 1 (Log to feed) followed by a feed ID
        if re.search(r'\b1:\d+', plist):
            processes_ok += 1
            
    if processes_ok >= 3:
        score += 15
        feedback.append("Input processes configured correctly (Log to feed).")
    elif processes_ok > 0:
        score += 5 * processes_ok
        feedback.append(f"Partial process configuration ({processes_ok}/3).")
    else:
        feedback.append("No valid input processes found.")

    # ----------------------------------------------------------------
    # 6. Verify Feeds Have Data (10 pts)
    # ----------------------------------------------------------------
    data_ok = 0
    for f in db_feeds:
        if f.get('value') is not None:
            data_ok += 1
            
    if data_ok >= 3:
        score += 10
        feedback.append("All feeds receiving data.")
    elif data_ok > 0:
        score += 3 * data_ok
        feedback.append(f"Partial data reception ({data_ok}/3 feeds have data).")
    else:
        feedback.append("No data received by feeds.")

    # ----------------------------------------------------------------
    # 7. Verify Config File Structure (10 pts)
    # ----------------------------------------------------------------
    config_content = fs_config.get('config_content', {})
    valid_json = fs_config.get('config_exists', False) and isinstance(config_content, dict)
    
    if valid_json:
        if config_content.get('node') == 'office_env' and len(config_content.get('channels', [])) == 3:
            score += 10
            feedback.append("Config file structure correct.")
        else:
            score += 5
            feedback.append("Config file exists but structure incomplete.")
    else:
        feedback.append("Config file missing or invalid JSON.")

    # ----------------------------------------------------------------
    # 8. Verify Config File Feed IDs (10 pts)
    # ----------------------------------------------------------------
    # Cross-reference IDs in JSON with actual DB IDs
    ids_matched = 0
    if valid_json:
        channels = config_content.get('channels', [])
        for ch in channels:
            fname = ch.get('feed_name')
            fid = str(ch.get('feed_id', ''))
            
            # Find actual ID in DB
            actual = found_feeds_map.get(fname)
            if actual and str(actual['id']) == fid:
                ids_matched += 1
                
    if ids_matched >= 3:
        score += 10
        feedback.append("Config file Feed IDs match database.")
    elif ids_matched > 0:
        score += 3 * ids_matched
        feedback.append(f"Partial Feed ID match ({ids_matched}/3).")

    # ----------------------------------------------------------------
    # 9. Verify Plausible Values (5 pts)
    # ----------------------------------------------------------------
    values_plausible = 0
    if valid_json:
        for ch in config_content.get('channels', []):
            val = ch.get('last_value')
            if isinstance(val, (int, float)) and val != 0:
                values_plausible += 1
                
    if values_plausible >= 3:
        score += 5
        feedback.append("Config file values plausible.")

    # ----------------------------------------------------------------
    # 10. Anti-Gaming (5 pts)
    # ----------------------------------------------------------------
    # Check file mtime and feed update time against task start
    anti_game_ok = False
    
    # Check config file time
    config_time = int(fs_config.get('config_mtime', 0))
    file_fresh = config_time > task_start
    
    # Check feed data time
    feed_fresh = any(
        f.get('timestamp') is not None and int(f.get('timestamp', 0)) > task_start 
        for f in db_feeds
    )
    
    if file_fresh and feed_fresh:
        score += 5
        feedback.append("Anti-gaming check passed (timestamps valid).")
    else:
        feedback.append("Anti-gaming warning: Artifacts may be stale.")

    # ----------------------------------------------------------------
    # Final Result
    # ----------------------------------------------------------------
    # Mandatory criteria for passing: Inputs, Feeds, Processes
    mandatory_met = (
        expected_inputs.issubset(found_inputs) and 
        expected_feeds.issubset(found_feed_names) and 
        processes_ok >= 3
    )
    
    passed = (score >= 70) and mandatory_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }