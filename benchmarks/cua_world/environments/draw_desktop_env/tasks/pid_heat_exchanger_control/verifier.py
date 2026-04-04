#!/usr/bin/env python3
"""
Verifier for pid_heat_exchanger_control task.

Scoring (100 points):
1. Files Created (10 pts): .drawio and .png exist.
2. Anti-Gaming (Pass/Fail): File modified after task start.
3. Shape Library Usage (15 pts): Detected P&ID styles in XML.
4. Heat Exchanger Tag (15 pts): 'HX-200' found.
5. Valve Tag (15 pts): 'TV-201' found.
6. Instrumentation Tags (20 pts): 'TT-201', 'TIC-201' found.
7. Control Loop Logic (25 pts): Edges exist (connectivity) + Enough shapes.

Pass Threshold: 60 points.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_pid_heat_exchanger_control(traj, env_info, task_info):
    """Verify the P&ID diagram creation."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}
    
    # Load result from container
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
    
    # 1. File Existence & Anti-Gaming (10 pts)
    if not result.get('file_exists'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "P&ID file not found. Nothing saved."
        }
        
    if not result.get('file_modified_after_start'):
        feedback.append("WARN: File was not modified after task start.")
    else:
        score += 5
        feedback.append("Source file saved.")
        
    if result.get('png_exists'):
        score += 5
        feedback.append("PNG exported.")
    else:
        feedback.append("PNG export missing.")
        
    analysis = result.get('analysis', {})
    tags_found = analysis.get('tags_found', [])
    
    # 2. Shape Library Usage (15 pts)
    # Check if specific P&ID shapes were used (detected by style keywords)
    if analysis.get('pid_library_used') or analysis.get('pid_shapes_count', 0) >= 3:
        score += 15
        feedback.append("P&ID shape library usage detected.")
    else:
        feedback.append("Standard shapes used (P&ID library recommended).")
        
    # 3. Heat Exchanger (15 pts)
    if 'hx-200' in tags_found:
        score += 15
        feedback.append("Heat Exchanger (HX-200) found.")
    else:
        feedback.append("Missing Heat Exchanger 'HX-200'.")
        
    # 4. Control Valve (15 pts)
    if 'tv-201' in tags_found:
        score += 15
        feedback.append("Control Valve (TV-201) found.")
    else:
        feedback.append("Missing Control Valve 'TV-201'.")
        
    # 5. Instrumentation (20 pts)
    inst_score = 0
    if 'tt-201' in tags_found:
        inst_score += 10
    if 'tic-201' in tags_found:
        inst_score += 10
    score += inst_score
    if inst_score == 20:
        feedback.append("Instrumentation (TT-201, TIC-201) found.")
    elif inst_score > 0:
        feedback.append("Partial instrumentation found.")
    else:
        feedback.append("Missing instrumentation tags.")
        
    # 6. Control Loop Logic / Connectivity (25 pts)
    # We check if there are edges connecting things
    num_edges = analysis.get('num_edges', 0)
    num_shapes = analysis.get('num_shapes', 0)
    
    if num_shapes >= 4 and num_edges >= 3:
        score += 25
        feedback.append("Control loop connectivity logic appears valid.")
    elif num_shapes >= 2 and num_edges >= 1:
        score += 10
        feedback.append("Partial diagram structure found.")
    else:
        feedback.append("Diagram structure incomplete (few shapes/edges).")
        
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }