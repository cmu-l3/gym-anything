#!/usr/bin/env python3
"""
Verifier for airline_passenger_journey_map task.

Scoring (100 points total):
1. File Creation & Modification (10 pts)
2. Diagram Structure (Phases & Lanes) (30 pts)
3. Content & Complexity (35 pts)
4. Multi-page & Export (25 pts)

Pass Threshold: 60 points
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_airline_passenger_journey_map(traj, env_info, task_info):
    """Verify the Customer Journey Map creation."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    analysis = result.get('analysis', {})
    
    # --- Criterion 1: File Existence (10 pts) ---
    if result.get('file_exists') and result.get('file_modified'):
        score += 10
        feedback_parts.append("Draw.io file saved")
    else:
        feedback_parts.append("Draw.io file missing or not modified")
        return {"passed": False, "score": 0, "feedback": "No work saved"}

    # --- Criterion 2: Diagram Structure (30 pts) ---
    # Phases (Cols)
    phases_found = len(analysis.get('phases_found', []))
    if phases_found >= 5:
        score += 15
        feedback_parts.append(f"Phases: {phases_found}/6 found")
    elif phases_found >= 3:
        score += 8
        feedback_parts.append(f"Phases: {phases_found}/6 found (partial)")
    else:
        feedback_parts.append(f"Phases: only {phases_found} found")

    # Lanes (Rows)
    lanes_found = len(analysis.get('lanes_found', []))
    if lanes_found >= 4:
        score += 15
        feedback_parts.append(f"Lanes: {lanes_found}/6 found")
    elif lanes_found >= 2:
        score += 7
        feedback_parts.append(f"Lanes: {lanes_found}/6 found (partial)")
    else:
        feedback_parts.append(f"Lanes: only {lanes_found} found")

    # --- Criterion 3: Content & Complexity (35 pts) ---
    # Shape count
    total_shapes = analysis.get('total_shapes', 0)
    if total_shapes >= 40:
        score += 10
        feedback_parts.append(f"Shapes: {total_shapes} (good complexity)")
    elif total_shapes >= 20:
        score += 5
        feedback_parts.append(f"Shapes: {total_shapes} (sparse)")
    else:
        feedback_parts.append(f"Shapes: {total_shapes} (too empty)")

    # Specific Content Keywords (Requirements usage)
    content_found = len(analysis.get('content_keywords_found', []))
    if content_found >= 8:
        score += 10
        feedback_parts.append(f"Content: {content_found} keywords verified")
    elif content_found >= 4:
        score += 5
        feedback_parts.append(f"Content: {content_found} keywords (partial)")
    else:
        feedback_parts.append("Content: Requirement specifics missing")
        
    # Flow (Edges)
    total_edges = analysis.get('total_edges', 0)
    if total_edges >= 5:
        score += 5
        feedback_parts.append("Flow arrows present")
    else:
        feedback_parts.append("Missing flow arrows")

    # Swimlanes/Containers
    if analysis.get('swimlanes_found', 0) > 0:
        score += 10
        feedback_parts.append("Swimlanes used")
    else:
        feedback_parts.append("No swimlanes detected")

    # --- Criterion 4: Multi-page & Export (25 pts) ---
    # Pages
    num_pages = analysis.get('num_pages', 0)
    if num_pages >= 2:
        score += 10
        feedback_parts.append("Multi-page created")
    else:
        feedback_parts.append("Single page only (Page 2 missing)")

    # Page 2 Content (Moments of Truth / Metrics)
    page2_content = len(analysis.get('page2_keywords_found', []))
    if page2_content >= 2:
        score += 5
        feedback_parts.append("Page 2 content verified")
        
    # PNG Export
    if result.get('png_exists') and result.get('png_size', 0) > 2000:
        score += 10
        feedback_parts.append("PNG export successful")
    else:
        feedback_parts.append("PNG export missing or invalid")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }