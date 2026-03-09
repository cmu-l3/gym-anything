#!/usr/bin/env python3
"""
Verifier for BPMN Incident Management Task
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bpmn_incident_management(traj, env_info, task_info):
    """
    Verifies the BPMN diagram based on the exported JSON analysis.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring config
    score = 0
    feedback_parts = []
    
    # 1. File Existence & Freshness (Critical) - 10 pts
    if result.get("file_exists") and result.get("file_modified_during_task"):
        score += 10
    else:
        return {"passed": False, "score": 0, "feedback": "File not saved or not modified."}

    # 2. Structure: Pools and Lanes (15 pts)
    # Expecting at least 1 Pool (Service Desk) + Lanes, or 2 Pools.
    # The count logic in export script is heuristic, so we accept >= 2 total containers (pools+lanes)
    containers = result.get("pool_count", 0) + result.get("lane_count", 0)
    if containers >= 3: # Service Desk + 3 lanes + End User pool approx
        score += 15
        feedback_parts.append(f"Structure good ({containers} pools/lanes)")
    elif containers >= 1:
        score += 7
        feedback_parts.append(f"Structure partial ({containers} pools/lanes)")
    else:
        feedback_parts.append("Missing pools/lanes")

    # 3. Tasks (15 pts)
    # Expecting ~7 tasks
    tasks = result.get("task_count", 0)
    if tasks >= 6:
        score += 15
        feedback_parts.append(f"Tasks: {tasks}")
    elif tasks >= 3:
        score += 7
        feedback_parts.append(f"Tasks: {tasks} (partial)")
    else:
        feedback_parts.append(f"Insufficient tasks ({tasks})")

    # 4. Gateways (15 pts)
    # Expecting 3-4 gateways
    gateways = result.get("gateway_count", 0)
    if gateways >= 3:
        score += 15
        feedback_parts.append(f"Gateways: {gateways}")
    elif gateways >= 1:
        score += 5
        feedback_parts.append(f"Gateways: {gateways} (partial)")
    else:
        feedback_parts.append("Missing gateways")

    # 5. Events (10 pts)
    # Start, End, Timer
    events = result.get("event_count", 0)
    if events >= 2:
        score += 10
        feedback_parts.append(f"Events: {events}")
    else:
        feedback_parts.append("Missing events")

    # 6. Connections (10 pts)
    edges = result.get("edge_count", 0)
    if edges >= 8:
        score += 10
        feedback_parts.append(f"Connections: {edges}")
    elif edges >= 4:
        score += 5
    else:
        feedback_parts.append("Diagram disconnected")

    # 7. Keywords (Content Verification) (15 pts)
    keywords = result.get("keywords_found", [])
    unique_kw = len(set(keywords))
    if unique_kw >= 6:
        score += 15
        feedback_parts.append("Content accurate")
    elif unique_kw >= 3:
        score += 7
        feedback_parts.append("Content partially accurate")
    else:
        feedback_parts.append("Missing specific process terms")

    # 8. PNG Export (10 pts)
    if result.get("png_exists") and result.get("png_size", 0) > 2000:
        score += 10
        feedback_parts.append("PNG exported")
    else:
        feedback_parts.append("PNG missing/empty")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }