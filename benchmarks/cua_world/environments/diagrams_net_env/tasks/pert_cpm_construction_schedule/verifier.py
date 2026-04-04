#!/usr/bin/env python3
"""
Verifier for PERT/CPM Construction Schedule Task.

Verifies:
1. Draw.io file existence and modification.
2. PDF export existence.
3. Node count (approx 18 activities).
4. Critical path highlighting (red nodes).
5. Data content (Activity IDs, scheduling calculations).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_pert_cpm_construction_schedule(traj, env_info, task_info):
    """
    Verify the PERT/CPM task based on file analysis from export_result.sh.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    analysis = result.get("analysis", {})
    
    score = 0
    feedback = []
    
    # Criterion 1: Drawio file created/modified (10 pts)
    if analysis.get("file_exists") and analysis.get("file_modified"):
        score += 10
        feedback.append("Draw.io file saved and modified (+10)")
    else:
        feedback.append("Draw.io file missing or not modified (0)")
        
    # Criterion 2: PDF Export (10 pts)
    if analysis.get("pdf_exists"):
        score += 10
        feedback.append("PDF export found (+10)")
    else:
        feedback.append("PDF export missing (0)")
        
    # Criterion 3: Node Count (Target 18 activities) (20 pts)
    # Allow some buffer for title nodes, legend, etc.
    node_count = analysis.get("node_count", 0)
    if node_count >= 18:
        score += 20
        feedback.append(f"Sufficient nodes detected ({node_count}) (+20)")
    elif node_count >= 10:
        score += 10
        feedback.append(f"Partial nodes detected ({node_count}/18) (+10)")
    else:
        feedback.append(f"Insufficient nodes ({node_count}) (0)")

    # Criterion 4: Edge Count (Target ~20 edges) (10 pts)
    edge_count = analysis.get("edge_count", 0)
    if edge_count >= 15:
        score += 10
        feedback.append(f"Sufficient connections detected ({edge_count}) (+10)")
    elif edge_count >= 8:
        score += 5
        feedback.append(f"Partial connections detected ({edge_count}) (+5)")
    else:
        feedback.append("Insufficient connections (0)")

    # Criterion 5: Activity IDs present (15 pts)
    # We look for A, B, C... R in the text
    found_ids = analysis.get("found_ids", [])
    unique_ids = len(set(found_ids))
    if unique_ids >= 15:
        score += 15
        feedback.append(f"Most activity IDs found ({unique_ids}/18) (+15)")
    elif unique_ids >= 8:
        score += 8
        feedback.append(f"Some activity IDs found ({unique_ids}/18) (+8)")
    else:
        feedback.append("Few activity IDs found (0)")

    # Criterion 6: Critical Path Highlighting (Red Nodes) (20 pts)
    # The critical path has 14 nodes. Expecting at least some red nodes.
    red_nodes = analysis.get("red_node_count", 0)
    if red_nodes >= 10:
        score += 20
        feedback.append(f"Critical path highlighted significantly ({red_nodes} red nodes) (+20)")
    elif red_nodes >= 5:
        score += 10
        feedback.append(f"Partial critical path highlighting ({red_nodes} red nodes) (+10)")
    elif red_nodes > 0:
        score += 5
        feedback.append("Minimal highlighting detected (+5)")
    else:
        feedback.append("No critical path highlighting (red nodes) detected (0)")

    # Criterion 7: Calculation/Values (15 pts)
    # Check for "61" (project duration) and terms like ES/EF/Slack
    has_duration = analysis.get("has_correct_duration", False)
    has_labels = analysis.get("has_scheduling_values", False)
    
    if has_duration:
        score += 10
        feedback.append("Project duration (61) found in diagram (+10)")
    if has_labels:
        score += 5
        feedback.append("Scheduling labels (ES/EF/Slack) found (+5)")

    # Final Check
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }