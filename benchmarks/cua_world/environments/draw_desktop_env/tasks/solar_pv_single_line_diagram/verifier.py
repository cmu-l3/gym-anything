#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_solar_sld(traj, env_info, task_info):
    """
    Verifies the Solar PV Single Line Diagram task.
    """
    # 1. Setup - Read result using copy_from_env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # 2. Extract Data
    analysis = result.get('analysis', {})
    text_content_list = analysis.get('text_content', [])
    # Join all text content for easy searching
    full_text = " ".join(text_content_list).lower()
    
    components_found = set(analysis.get('components_found', []))
    is_connected = analysis.get('is_connected_pv_to_grid', False)
    
    drawio_exists = result.get('drawio_exists', False)
    png_exists = result.get('png_exists', False)
    file_created = result.get('file_created_during_task', False)

    # 3. Scoring Logic
    score = 0
    feedback = []

    # Criterion 1: Files Created (10 pts)
    if drawio_exists and png_exists and file_created:
        score += 10
        feedback.append("Files created successfully.")
    elif drawio_exists and file_created:
        score += 5
        feedback.append("Source file created, but PNG missing.")
    else:
        feedback.append("No new files created.")

    # Criterion 2: Critical Components Present (30 pts)
    # Looking for abstract component types identified by the analyzer
    required_comps = {"PV", "Inverter", "Grid", "ServicePanel", "Meter"}
    found_count = len(components_found.intersection(required_comps))
    
    # 6 points per component type
    comp_score = found_count * 6
    score += comp_score
    if found_count < 5:
        missing = required_comps - components_found
        feedback.append(f"Missing components: {', '.join(missing)}.")
    else:
        feedback.append("All critical components found.")

    # Criterion 3: Specific Model Numbers / Ratings (20 pts)
    # Check for specific strings from spec
    specs_to_check = [
        ("se7600", 5),      # Inverter model
        ("q.peak", 5),      # Panel model
        ("square d", 2.5),  # Disconnect
        ("60a", 2.5),       # Disconnect rating
        ("200a", 2.5),      # Panel rating
        ("bi-directional", 2.5) # Meter type
    ]
    
    spec_score = 0
    for term, pts in specs_to_check:
        if term in full_text:
            spec_score += pts
        else:
            feedback.append(f"Missing spec details: '{term}'")
    
    score += spec_score

    # Criterion 4: Connectivity (25 pts)
    if is_connected:
        score += 25
        feedback.append("Valid connection path from PV to Grid found.")
    else:
        # Partial credit for having edges at all
        edge_count = analysis.get('edge_count', 0)
        if edge_count >= 4:
            score += 10
            feedback.append(f"Components not fully connected (PV to Grid path broken), but {edge_count} connections exist.")
        else:
            feedback.append("Diagram lacks connectivity.")

    # Criterion 5: Diagram Complexity/Symbols (15 pts)
    # If we have enough vertices and edges, we assume reasonable effort
    vertex_count = analysis.get('vertex_count', 0)
    if vertex_count >= 5 and analysis.get('edge_count', 0) >= 4:
        score += 15
        feedback.append("Diagram has sufficient complexity.")
    else:
        feedback.append("Diagram is too simple.")

    # Final tally
    passed = score >= 60 and drawio_exists and file_created

    return {
        "passed": passed,
        "score": round(score),
        "feedback": " ".join(feedback)
    }