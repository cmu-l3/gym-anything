#!/usr/bin/env python3
"""
Verifier for genetic_pedigree_royal_hemophilia task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_genetic_pedigree(traj, env_info, task_info):
    """
    Verify the genetic pedigree chart creation.
    
    Checks:
    1. File creation and export (drawio + PDF).
    2. Data completeness (shapes count, specific names).
    3. Structural correctness (generations, connections).
    4. Visual encoding (affected vs unaffected).
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. File checks (25 pts)
    if result.get("file_exists") and result.get("file_modified_during_task"):
        score += 15
        feedback_parts.append("Drawio file created/modified.")
    else:
        feedback_parts.append("Drawio file missing or not modified.")

    if result.get("pdf_exists"):
        score += 10
        feedback_parts.append("PDF export found.")
    else:
        feedback_parts.append("PDF export missing.")

    # 2. Shape Counts & Structure (30 pts)
    # Expecting ~28 individuals. Minimum 24.
    shapes = result.get("shapes_total", 0)
    if shapes >= 24:
        score += 15
        feedback_parts.append(f"Sufficient individuals found ({shapes}).")
    elif shapes >= 15:
        score += 8
        feedback_parts.append(f"Partial individuals found ({shapes}).")
    else:
        feedback_parts.append(f"Too few individuals ({shapes}).")

    connections = result.get("connections", 0)
    if connections >= 20:
        score += 15
        feedback_parts.append("Sufficient connections.")
    elif connections >= 10:
        score += 8
        feedback_parts.append("Partial connections.")

    # 3. Content Verification (Names) (25 pts)
    text_content = " ".join(result.get("text_content", [])).lower()
    required_names = ["victoria", "albert", "alice", "leopold", "beatrice", "alexei", "alfonso"]
    found_names = [name for name in required_names if name in text_content]
    
    name_score = 0
    if len(found_names) >= 6:
        name_score = 25
    elif len(found_names) >= 4:
        name_score = 15
    elif len(found_names) >= 1:
        name_score = 5
    
    score += name_score
    feedback_parts.append(f"Key names found: {len(found_names)}/{len(required_names)}.")

    # 4. Notation Compliance (20 pts)
    # Check for visual encoding of Affected individuals
    affected_count = result.get("affected", 0)
    if affected_count >= 5: # Expecting ~6 affected
        score += 10
        feedback_parts.append("Affected individuals visually distinguished.")
    elif affected_count >= 1:
        score += 5
        feedback_parts.append("Some affected individuals distinguished.")
    
    # Check for Generations
    gens = result.get("generations_found", [])
    if len(gens) >= 3:
        score += 5
        feedback_parts.append("Generation labels found.")
        
    # Check for Legend
    if result.get("legend_found"):
        score += 5
        feedback_parts.append("Legend found.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }