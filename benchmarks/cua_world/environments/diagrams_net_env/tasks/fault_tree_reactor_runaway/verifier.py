#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fault_tree_reactor_runaway(traj, env_info, task_info):
    """
    Verifies the Fault Tree Analysis task.
    Checks for:
    1. Diagram file and PDF export existence.
    2. File modification during the task.
    3. Significant increase in complexity (shapes/edges).
    4. Content accuracy (domain specific terms from the report).
    5. Quantitative data (probability labels).
    6. Visual coding (subsystem colors).
    """
    
    # 1. Copy result from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env missing"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Load Requirements
    meta = task_info.get('metadata', {})
    min_shapes = meta.get('min_final_shapes', 20)
    min_edges = meta.get('min_final_edges', 19)
    
    score = 0
    feedback = []

    # --- CRITERION 1: Anti-Gaming / Activity (20 pts) ---
    if result.get('file_exists') and result.get('timestamp_valid'):
        score += 10
        feedback.append("File saved and modified during task (+10).")
    else:
        feedback.append("File not modified or not found (0).")
        
    initial_shapes = 5 # Known starting state
    current_shapes = result.get('shape_count', 0)
    if current_shapes >= initial_shapes + 5:
        score += 10
        feedback.append(f"Significant diagram expansion detected ({current_shapes} shapes) (+10).")
    else:
        feedback.append("Diagram expansion insufficient (0).")

    # --- CRITERION 2: Structural Completeness (30 pts) ---
    # We expect a fully developed tree.
    if current_shapes >= min_shapes:
        score += 15
        feedback.append("Diagram structure meets complexity requirements (+15).")
    elif current_shapes >= min_shapes * 0.7:
        score += 8
        feedback.append("Diagram structure partially complete (+8).")
    
    current_edges = result.get('edge_count', 0)
    if current_edges >= min_edges:
        score += 15
        feedback.append("Diagram connectivity good (+15).")
    elif current_edges >= min_edges * 0.7:
        score += 8
        feedback.append("Diagram connectivity partial (+8).")

    # --- CRITERION 3: Content Accuracy (20 pts) ---
    # Check for domain terms extracted from XML
    found_terms = result.get('found_terms', [])
    unique_terms = len(set(found_terms))
    
    if unique_terms >= 8:
        score += 20
        feedback.append("Excellent domain content coverage (+20).")
    elif unique_terms >= 5:
        score += 10
        feedback.append("Good domain content coverage (+10).")
    else:
        feedback.append(f"Low content coverage ({unique_terms} terms found) (0).")

    # --- CRITERION 4: Technical Specification (20 pts) ---
    # Probabilities and Color Coding
    prob_count = result.get('prob_pattern_count', 0)
    if prob_count >= 5:
        score += 10
        feedback.append("Probability data labels detected (+10).")
    else:
        feedback.append("Missing probability data labels (0).")

    colors = result.get('colors_found', [])
    if len(colors) >= 2:
        score += 10
        feedback.append(f"Subsystem color coding applied ({', '.join(colors)}) (+10).")
    else:
        feedback.append("Color coding missing or insufficient (0).")

    # --- CRITERION 5: Deliverable (10 pts) ---
    if result.get('pdf_exists'):
        score += 10
        feedback.append("PDF export found (+10).")
    else:
        feedback.append("PDF export missing (0).")

    # Final Check
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }