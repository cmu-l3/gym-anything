#!/usr/bin/env python3
"""
Verifier for ecommerce_wardley_map task.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_ecommerce_wardley_map(traj, env_info, task_info):
    """Verify Wardley Map creation."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback = []
    
    # 1. File Check (5 pts)
    if result.get('file_exists') and result.get('file_modified'):
        score += 5
        feedback.append("Draw.io file saved")
    else:
        return {"passed": False, "score": 0, "feedback": "File not saved or not modified"}
        
    analysis = result.get('analysis', {})
    
    # 2. Components (25 pts)
    # We look for ~18 components. Partial credit.
    labels = analysis.get('labels_found', [])
    # Distinct components (fuzzy matching done in export script)
    # The export script searches for keywords like 'customer', 'fraud', etc.
    # We want to see how many distinct keywords matched.
    distinct_count = len(labels)
    
    if distinct_count >= 14:
        score += 25
        feedback.append(f"Components: Excellent ({distinct_count} identified)")
    elif distinct_count >= 10:
        score += 15
        feedback.append(f"Components: Good ({distinct_count} identified)")
    elif distinct_count >= 6:
        score += 8
        feedback.append(f"Components: Partial ({distinct_count} identified)")
    else:
        feedback.append(f"Components: Too few ({distinct_count})")
        
    # 3. Edges (20 pts)
    num_edges = analysis.get('num_edges', 0)
    if num_edges >= 12:
        score += 20
        feedback.append(f"Connections: {num_edges} (Good)")
    elif num_edges >= 7:
        score += 10
        feedback.append(f"Connections: {num_edges} (Partial)")
    elif num_edges >= 4:
        score += 5
        feedback.append(f"Connections: {num_edges} (Few)")
    else:
        feedback.append("Connections: Minimal or none")
        
    # 4. Axis Labels (10 pts)
    axis_labels = analysis.get('axis_labels_found', [])
    if len(axis_labels) >= 2:
        score += 10
        feedback.append(f"Axis labels found: {', '.join(axis_labels)}")
    else:
        feedback.append("Axis labels missing (Genesis, Custom, Product, Commodity)")

    # 5. Value Chain Label (5 pts)
    if 'visible' in axis_labels or 'invisible' in axis_labels:
        score += 5
        feedback.append("Value chain axis labeled")
        
    # 6. Title (5 pts)
    if analysis.get('has_title'):
        score += 5
        feedback.append("Title present")
        
    # 7. Multi-page (10 pts)
    if analysis.get('num_pages', 0) >= 2:
        score += 10
        feedback.append("Multi-page diagram created")
    else:
        feedback.append("Single page only")
        
    # 8. Strategic Moves (5 pts)
    if analysis.get('has_second_page_content'):
        score += 5
        feedback.append("Content found on second page")
        
    # 9. PNG Export (10 pts)
    if result.get('png_exists') and result.get('png_size', 0) > 2000:
        score += 10
        feedback.append("PNG exported")
        
    # 10. Spatial Distribution (5 pts)
    # Check if shapes are distributed across X-axis (evolution stages)
    zones = analysis.get('x_distribution', [])
    # Valid if at least 3 zones have shapes
    occupied_zones = sum(1 for z in zones if z > 0)
    if occupied_zones >= 3:
        score += 5
        feedback.append("Good spatial distribution")
    else:
        feedback.append("Shapes clustered in few zones")
        
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }