#!/usr/bin/env python3
"""
Verifier for insurance_archimate_landscape task.

Scoring Criteria:
- File Saved (10 pts)
- ArchiMate Library Used (25 pts) - Critical requirement
- Business Layer Elements (15 pts)
- App Layer Elements (15 pts)
- Tech Layer Elements (15 pts)
- Relationships (10 pts)
- PNG Export (10 pts)

Pass Threshold: 60 points AND ArchiMate library usage.
"""

import json
import tempfile
import os
import logging
import re

logger = logging.getLogger(__name__)

def verify_insurance_archimate_landscape(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_elements = metadata.get('required_elements', {})
    
    # 2. Get Result JSON
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

    # 3. Initialize Scoring
    score = 0
    feedback = []
    analysis = result.get('analysis', {})
    text_content = " ".join(analysis.get('text_content', [])).lower()
    
    # --- Criterion 1: File Saved (10 pts) ---
    if result.get('file_exists') and result.get('file_modified'):
        score += 10
        feedback.append("Draw.io file saved successfully.")
    else:
        feedback.append("Draw.io file not saved or not modified.")

    # --- Criterion 2: ArchiMate Library Usage (25 pts) ---
    # This is critical. The task specifically asks for ArchiMate shapes.
    archimate_count = analysis.get('archimate_shapes_count', 0)
    uses_archimate = False
    
    if archimate_count >= 5:
        score += 25
        uses_archimate = True
        feedback.append(f"Correctly used ArchiMate shape library ({archimate_count} shapes).")
    elif archimate_count > 0:
        score += 10
        uses_archimate = True # Partial credit but still counts as using it
        feedback.append(f"Used some ArchiMate shapes ({archimate_count}), but expected more.")
    else:
        feedback.append("CRITICAL: Did not use ArchiMate shape library (generic shapes used).")

    # --- Criterion 3: Business Layer (15 pts) ---
    # Look for keywords: customer, submit claim, damage report
    bus_score = 0
    missing_bus = []
    for term in required_elements.get('business', []):
        if term in text_content:
            bus_score += 5
        else:
            missing_bus.append(term)
    
    score += bus_score
    if not missing_bus:
        feedback.append("All Business Layer elements found.")
    else:
        feedback.append(f"Missing Business elements: {', '.join(missing_bus)}.")

    # --- Criterion 4: Application Layer (15 pts) ---
    # Look for: claims intake, policy administration, document management
    app_score = 0
    missing_app = []
    for term in required_elements.get('application', []):
        # Flexible matching for "Policy Administration System" vs "Policy Administration"
        if term in text_content:
            app_score += 5
        else:
            missing_app.append(term)

    score += app_score
    if not missing_app:
        feedback.append("All Application Layer elements found.")
    else:
        feedback.append(f"Missing Application elements: {', '.join(missing_app)}.")

    # --- Criterion 5: Technology Layer (15 pts) ---
    # Look for: mainframe, db2, claim pdf
    tech_score = 0
    missing_tech = []
    for term in required_elements.get('technology', []):
        if term in text_content:
            tech_score += 5
        else:
            missing_tech.append(term)

    score += tech_score
    if not missing_tech:
        feedback.append("All Technology Layer elements found.")
    else:
        feedback.append(f"Missing Technology elements: {', '.join(missing_tech)}.")

    # --- Criterion 6: Relationships (10 pts) ---
    num_edges = analysis.get('num_edges', 0)
    if num_edges >= 6:
        score += 10
        feedback.append(f"Sufficient relationships drawn ({num_edges}).")
    elif num_edges >= 3:
        score += 5
        feedback.append(f"Some relationships drawn ({num_edges}), expected 6+.")
    else:
        feedback.append("Few or no relationships connecting elements.")

    # --- Criterion 7: PNG Export (10 pts) ---
    if result.get('png_exists') and result.get('png_size', 0) > 1000:
        score += 10
        feedback.append("Valid PNG export found.")
    else:
        feedback.append("PNG export missing or empty.")

    # 4. Final Verdict
    # Must achieve score threshold AND use the correct library
    passed = (score >= 60) and uses_archimate
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }