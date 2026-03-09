#!/usr/bin/env python3
"""
Verifier for event_capture_and_visualize task.
"""

import json
import logging
import os
import re
import tempfile
from datetime import datetime

logger = logging.getLogger(__name__)

def verify_event_capture_and_visualize(traj, env_info, task_info):
    """
    Verifies that the agent:
    1. Created 2 new events in 'Information Campaign' program.
    2. Entered specific data values ('MALARIA...', 'NUTRITION...').
    3. Recorded geospatial coordinates.
    4. Completed the events.
    5. Created a visualization named 'Bo Campaign Analysis 2024'.
    """
    
    # 1. Setup and load result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    new_events = result.get('new_events', [])
    if new_events is None: new_events = []
    
    viz_data = result.get('visualization_query', {})
    visualizations = viz_data.get('visualizations', [])
    
    score = 0
    feedback = []

    # --- CRITERION 1: Events Created (30 pts) ---
    event_count = len(new_events)
    if event_count >= 2:
        score += 30
        feedback.append(f"✅ Created {event_count} new events.")
    elif event_count == 1:
        score += 15
        feedback.append("⚠️ Created only 1 new event (expected 2).")
    else:
        feedback.append("❌ No new events created in the target program.")

    # --- CRITERION 2: Data Values (20 pts) ---
    # We look for "MALARIA" and "NUTRITION" in the data_values string
    malaria_found = False
    nutrition_found = False
    
    for event in new_events:
        dvals = str(event.get('data_values', '')).upper()
        if 'MALARIA' in dvals:
            malaria_found = True
        if 'NUTRITION' in dvals:
            nutrition_found = True
            
    if malaria_found and nutrition_found:
        score += 20
        feedback.append("✅ Both Malaria and Nutrition topics recorded.")
    elif malaria_found or nutrition_found:
        score += 10
        feedback.append("⚠️ Only one topic (Malaria/Nutrition) found.")
    else:
        feedback.append("❌ Specific campaign topics not found in data values.")

    # --- CRITERION 3: Geometry/Coordinates (15 pts) ---
    # Check if geometry_text is not null and looks like a point
    geo_count = 0
    for event in new_events:
        geo = event.get('geometry_text')
        if geo and 'POINT' in geo:
            geo_count += 1
            
    if geo_count >= 2:
        score += 15
        feedback.append("✅ Coordinates recorded for both events.")
    elif geo_count == 1:
        score += 7
        feedback.append("⚠️ Coordinates recorded for only 1 event.")
    else:
        feedback.append("❌ No geospatial coordinates recorded.")

    # --- CRITERION 4: Events Completed (10 pts) ---
    completed_count = sum(1 for e in new_events if e.get('status') == 'COMPLETED')
    if completed_count >= 2:
        score += 10
        feedback.append("✅ All events marked as COMPLETED.")
    elif completed_count > 0:
        score += 5
        feedback.append("⚠️ Some events not completed.")
    else:
        feedback.append("❌ Events left in ACTIVE state (not completed).")

    # --- CRITERION 5: Visualization Exists (15 pts) ---
    viz_found = False
    correct_viz = None
    
    for v in visualizations:
        # Check name fuzzy match
        if 'Bo Campaign' in v.get('name', '') or 'Campaign Analysis' in v.get('name', ''):
            viz_found = True
            correct_viz = v
            break
            
    if viz_found:
        score += 15
        feedback.append("✅ Visualization 'Bo Campaign Analysis 2024' created.")
    else:
        feedback.append("❌ No visualization found matching 'Bo Campaign Analysis'.")

    # --- CRITERION 6: Visualization Configuration (10 pts) ---
    # Check if it's based on the correct program or EVENT type
    if viz_found and correct_viz:
        # Check type or data items (simplified check)
        # Note: API might simplify type names
        v_type = correct_viz.get('type', '')
        if 'EVENT' in v_type or 'CHART' in v_type: # Broad check as type names vary by DHIS2 version
            score += 10
            feedback.append("✅ Visualization type appears correct.")
        else:
            feedback.append(f"⚠️ Visualization type '{v_type}' might be incorrect.")

    # Final Result
    passed = (score >= 65) and (event_count >= 1) and viz_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }