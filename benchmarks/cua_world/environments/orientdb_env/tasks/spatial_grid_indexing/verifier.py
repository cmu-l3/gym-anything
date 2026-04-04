#!/usr/bin/env python3
"""
Verifier for spatial_grid_indexing task in OrientDB.
"""

import json
import os
import tempfile
import base64
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_spatial_grid_indexing(traj, env_info, task_info):
    """
    Verifies that the agent correctly created the GeographicZone class,
    linked hotels to zones, and generated a report.
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

    score = 0
    feedback_parts = []
    
    db_state = result.get('db_state', {})
    
    # 1. Schema Verification (30 pts)
    # ----------------------------
    if db_state.get('has_zone_class') and db_state.get('zone_extends_v'):
        score += 10
        feedback_parts.append("GeographicZone class created")
    else:
        feedback_parts.append("GeographicZone class missing or invalid")

    if db_state.get('has_inzone_class') and db_state.get('inzone_extends_e'):
        score += 10
        feedback_parts.append("InZone edge class created")
    else:
        feedback_parts.append("InZone edge class missing")

    if db_state.get('has_unique_index'):
        score += 10
        feedback_parts.append("Unique index on ZoneID verified")
    else:
        feedback_parts.append("Unique index on ZoneID missing")

    # 2. Data Population Verification (40 pts)
    # ----------------------------
    hotel_count = db_state.get('hotel_count', 0)
    edge_count = db_state.get('edge_count', 0)
    zone_count = db_state.get('zone_count', 0)

    # Check edge coverage (should ideally match hotel count)
    if hotel_count > 0 and edge_count >= hotel_count * 0.95:  # Allow slight tolerance
        score += 20
        feedback_parts.append(f"Hotels linked to zones ({edge_count}/{hotel_count})")
    elif edge_count > 0:
        score += 10
        feedback_parts.append(f"Partial linking ({edge_count}/{hotel_count})")
    else:
        feedback_parts.append("No hotels linked to zones")

    # Check specific accuracy
    # Hotel Artemide (41, 12) -> "41_12"
    actual_artemide = db_state.get('artemide_zone')
    expected_artemide = "41_12"
    
    if actual_artemide == expected_artemide:
        score += 10
        feedback_parts.append(f"Correct zone for Hotel Artemide ({actual_artemide})")
    else:
        feedback_parts.append(f"Incorrect zone for Artemide: expected {expected_artemide}, got {actual_artemide}")

    # Four Seasons Sydney (-33, 151) -> "-33_151"
    actual_sydney = db_state.get('sydney_zone')
    expected_sydney = "-33_151"
    
    if actual_sydney == expected_sydney:
        score += 10
        feedback_parts.append(f"Correct zone for Four Seasons Sydney ({actual_sydney})")
    else:
        feedback_parts.append(f"Incorrect zone for Sydney: expected {expected_sydney}, got {actual_sydney}")

    # 3. Report Verification (30 pts)
    # ----------------------------
    report_exists = result.get('report_exists', False)
    report_fresh = result.get('report_created_during_task', False)
    
    if report_exists and report_fresh:
        try:
            content_b64 = result.get('report_content_b64', "")
            content = base64.b64decode(content_b64).decode('utf-8')
            
            # Simple check for content format "ZoneID: ..., Count: ..."
            if "ZoneID" in content and "Count" in content:
                score += 30
                feedback_parts.append("Report created with valid format")
            else:
                score += 15
                feedback_parts.append("Report created but content format unclear")
        except Exception:
             score += 15
             feedback_parts.append("Report exists but could not verify content")
    elif report_exists:
        feedback_parts.append("Report file exists but is old (not created during task)")
    else:
        feedback_parts.append("Report file missing")

    passed = score >= 70 and db_state.get('has_zone_class') and db_state.get('has_inzone_class')

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }