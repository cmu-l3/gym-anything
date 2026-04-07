#!/usr/bin/env python3
"""
Verifier for Configure IP Punch Restriction task in TimeTrex.

Uses copy_from_env to read pre-exported verification data from the container.
The export script queries the database for records matching the specific IP addresses.
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ip_restrictions(traj, env_info, task_info):
    """
    Verify that two Station records were created with the specified details.

    Criteria (100 total points):
    - HQ Station Exists & Created during task (20 pts)
    - HQ Station Details Match: Station ID 'ANY' & Description 'Headquarters IP Restriction' (30 pts)
    - WH Station Exists & Created during task (20 pts)
    - WH Station Details Match: Station ID 'ANY' & Description 'Warehouse IP Restriction' (30 pts)
    
    Pass threshold: 70 points (Must successfully create both with correct sources, and at least one fully correct).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available. Framework error."}

    # Extract metadata expected values
    metadata = task_info.get('metadata', {})
    expected_hq_desc = metadata.get('expected_hq_desc', 'Headquarters IP Restriction').lower().strip()
    expected_wh_desc = metadata.get('expected_wh_desc', 'Warehouse IP Restriction').lower().strip()
    expected_station_id = metadata.get('expected_station_id', 'ANY').lower().strip()
    # type_id 10 generally maps to PC, we check it softly.

    try:
        # Securely copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_result.close()
        
        try:
            copy_from_env("/tmp/ip_restriction_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found. Export script failed."}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Result JSON is invalid: {e}"}
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Setup/Export error: {result['error']}"}

    score = 0
    feedback_parts = []
    
    task_start = int(result.get("task_start_timestamp", 0))
    hq_station = result.get("hq_station", {})
    wh_station = result.get("wh_station", {})

    # Evaluate Headquarters Station
    if hq_station.get("found"):
        created_date = int(hq_station.get("created_date", 0))
        if created_date >= task_start:
            score += 20
            feedback_parts.append("[HQ] Created during task (20/20)")
            
            # Check HQ details
            hq_details_score = 0
            act_station_id = str(hq_station.get("station_id", "")).lower().strip()
            act_desc = str(hq_station.get("description", "")).lower().strip()
            
            if act_station_id == expected_station_id:
                hq_details_score += 15
                
            if act_desc == expected_hq_desc:
                hq_details_score += 15
                
            score += hq_details_score
            feedback_parts.append(f"[HQ] Details accuracy ({hq_details_score}/30)")
            if hq_details_score < 30:
                feedback_parts.append(f"  > Expected ID:'{expected_station_id}', Desc:'{expected_hq_desc}'. Got ID:'{act_station_id}', Desc:'{act_desc}'")
        else:
            feedback_parts.append("[HQ] Found but existed BEFORE task started (0/50)")
    else:
        feedback_parts.append("[HQ] Not found (0/50)")

    # Evaluate Warehouse Station
    if wh_station.get("found"):
        created_date = int(wh_station.get("created_date", 0))
        if created_date >= task_start:
            score += 20
            feedback_parts.append("[WH] Created during task (20/20)")
            
            # Check WH details
            wh_details_score = 0
            act_station_id = str(wh_station.get("station_id", "")).lower().strip()
            act_desc = str(wh_station.get("description", "")).lower().strip()
            
            if act_station_id == expected_station_id:
                wh_details_score += 15
                
            if act_desc == expected_wh_desc:
                wh_details_score += 15
                
            score += wh_details_score
            feedback_parts.append(f"[WH] Details accuracy ({wh_details_score}/30)")
            if wh_details_score < 30:
                feedback_parts.append(f"  > Expected ID:'{expected_station_id}', Desc:'{expected_wh_desc}'. Got ID:'{act_station_id}', Desc:'{act_desc}'")
        else:
            feedback_parts.append("[WH] Found but existed BEFORE task started (0/50)")
    else:
        feedback_parts.append("[WH] Not found (0/50)")

    # "Do Nothing" Detection / Validation
    initial_count = int(result.get("initial_station_count", 0))
    current_count = int(result.get("current_station_count", 0))
    if current_count <= initial_count and score > 0:
         feedback_parts.append("WARNING: Total station count did not increase. Agent may have modified existing records rather than creating new ones.")

    # Determine passing state
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }