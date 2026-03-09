#!/usr/bin/env python3
"""
Verifier for dc_metro_transit_map task.

Scoring (100 points total):
1. File saved & modified: 5 pts
2. Station labels found (≥30): 25 pts (Partial: ≥20=15, ≥10=7)
3. Connection edges (≥50): 15 pts (Partial: ≥30=8, ≥15=4)
4. Distinct line colors (≥4): 15 pts (Partial: ≥2=6)
5. Interchange stations marked (≥5): 10 pts
6. Terminus stations present (All 6 lines/12 ends): 10 pts (Partial ≥8=5)
7. Legend present: 5 pts
8. PNG exported: 10 pts
9. Spatial layout check (heuristic): 5 pts

Pass Threshold: 55 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_dc_metro_transit_map(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
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
    feedback = []
    analysis = result.get('analysis', {})
    
    # Criterion 1: File Saved (5 pts)
    if result.get('file_exists') and result.get('file_modified_after_start'):
        score += 5
        feedback.append("File saved successfully.")
    else:
        feedback.append("File not saved or not modified.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criterion 2: Station Labels (25 pts)
    stations_found = len(analysis.get('stations_found', []))
    if stations_found >= 30:
        score += 25
        feedback.append(f"Stations: {stations_found} (Excellent)")
    elif stations_found >= 20:
        score += 15
        feedback.append(f"Stations: {stations_found} (Good)")
    elif stations_found >= 10:
        score += 7
        feedback.append(f"Stations: {stations_found} (Sparse)")
    else:
        feedback.append(f"Stations: Only {stations_found} found")

    # Criterion 3: Edges (15 pts)
    num_edges = analysis.get('num_edges', 0)
    if num_edges >= 50:
        score += 15
        feedback.append(f"Connections: {num_edges} (Complex)")
    elif num_edges >= 30:
        score += 8
        feedback.append(f"Connections: {num_edges} (Moderate)")
    elif num_edges >= 15:
        score += 4
        feedback.append(f"Connections: {num_edges} (Basic)")
    else:
        feedback.append(f"Connections: {num_edges} (Insufficient)")

    # Criterion 4: Colors (15 pts)
    colors = analysis.get('unique_edge_colors', 0)
    # Note: XML parsing might miss some default colors or named colors, 
    # but a good diagram usually sets explicit hex codes.
    # We relax the threshold slightly.
    if colors >= 4:
        score += 15
        feedback.append(f"Colors: {colors} distinct colors used")
    elif colors >= 2:
        score += 6
        feedback.append(f"Colors: {colors} distinct colors (Partial)")
    else:
        feedback.append(f"Colors: {colors} (Monochrome or default)")

    # Criterion 5: Interchanges (10 pts)
    interchanges = len(analysis.get('interchanges_found', []))
    if interchanges >= 5:
        score += 10
        feedback.append(f"Interchanges: {interchanges} marked")
    else:
        feedback.append(f"Interchanges: {interchanges} found (Need ≥5)")

    # Criterion 6: Terminus Stations (10 pts)
    termini = len(analysis.get('termini_found', []))
    if termini >= 10: # Total is ~11
        score += 10
        feedback.append(f"Termini: {termini} (Complete)")
    elif termini >= 8:
        score += 5
        feedback.append(f"Termini: {termini} (Partial)")
    else:
        feedback.append(f"Termini: {termini} (Missing lines)")

    # Criterion 7: Legend (5 pts)
    if analysis.get('legend_found'):
        score += 5
        feedback.append("Legend found")
    else:
        feedback.append("No legend detected")

    # Criterion 8: PNG Export (10 pts)
    if result.get('png_exists') and result.get('png_size', 0) > 5000:
        score += 10
        feedback.append("PNG export successful")
    else:
        feedback.append("PNG export missing or empty")

    # Criterion 9: Spatial Layout (5 pts) - Proxy by Shape Count vs Edges
    # A map usually has Shapes ~= Edges (nodes and links).
    # If shapes > 15, we assume some layout effort.
    num_shapes = analysis.get('num_shapes', 0)
    if num_shapes >= 15:
        score += 5
        feedback.append("Diagram has meaningful complexity")

    passed = score >= 55
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }