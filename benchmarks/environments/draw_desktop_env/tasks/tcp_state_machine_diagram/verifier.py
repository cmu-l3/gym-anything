#!/usr/bin/env python3
"""
Verifier for tcp_state_machine_diagram task.

Scoring Breakdown (100 pts total):
1. File Validation (10 pts)
   - .drawio exists & modified: 5 pts
   - Valid XML structure: 5 pts
2. States (20 pts)
   - 9+ states found: 20 pts
   - 6-8 states: 12 pts
   - 3-5 states: 5 pts
3. Transitions (15 pts)
   - 14+ edges: 15 pts
   - 8-13 edges: 8 pts
   - 4-7 edges: 3 pts
4. Transition Content (15 pts)
   - 8+ unique TCP keywords found in edge labels: 15 pts
   - 4-7 keywords: 7 pts
5. Color Coding (10 pts)
   - At least 2 distinct colors detected on edges: 10 pts
6. Legend (5 pts)
   - Legend/Key detected: 5 pts
7. Multi-page & Structure (15 pts)
   - 2+ pages: 10 pts
   - "Happy Path" page detected: 5 pts
8. Export (10 pts)
   - PNG export exists & size > 5KB: 10 pts

Pass Threshold: 60 pts
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tcp_state_machine(traj, env_info, task_info):
    """Verify the TCP State Machine diagram task."""
    
    # 1. Load result from container
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

    score = 0
    feedback_parts = []
    
    analysis = result.get("analysis", {})
    
    # --- Criterion 1: File Validation (10 pts) ---
    if result.get("file_exists") and result.get("file_modified_after_start"):
        score += 5
        feedback_parts.append("File saved")
    else:
        feedback_parts.append("File NOT saved/modified")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
    if analysis.get("valid_xml"):
        score += 5
        feedback_parts.append("Valid XML")
    else:
        feedback_parts.append("Invalid XML")
        
    # --- Criterion 2: States (20 pts) ---
    found_states = len(analysis.get("found_states", []))
    if found_states >= 9:
        score += 20
        feedback_parts.append(f"States: {found_states}/11 (Excellent)")
    elif found_states >= 6:
        score += 12
        feedback_parts.append(f"States: {found_states}/11 (Good)")
    elif found_states >= 3:
        score += 5
        feedback_parts.append(f"States: {found_states}/11 (Partial)")
    else:
        feedback_parts.append(f"States: {found_states}/11 (Fail)")
        
    # --- Criterion 3: Transitions (15 pts) ---
    num_transitions = analysis.get("num_transitions", 0)
    if num_transitions >= 14:
        score += 15
        feedback_parts.append(f"Transitions: {num_transitions} (Excellent)")
    elif num_transitions >= 8:
        score += 8
        feedback_parts.append(f"Transitions: {num_transitions} (Fair)")
    elif num_transitions >= 4:
        score += 3
        feedback_parts.append(f"Transitions: {num_transitions} (Low)")
    else:
        feedback_parts.append(f"Transitions: {num_transitions} (Fail)")

    # --- Criterion 4: Transition Content (15 pts) ---
    # Keywords: SYN, ACK, FIN, RST, CLOSE, OPEN, TIMEOUT...
    found_keywords = len(analysis.get("found_keywords", []))
    if found_keywords >= 8:
        score += 15
        feedback_parts.append(f"Keywords: {found_keywords} (Detailed)")
    elif found_keywords >= 4:
        score += 7
        feedback_parts.append(f"Keywords: {found_keywords} (Basic)")
    else:
        feedback_parts.append(f"Keywords: {found_keywords} (Missing details)")
        
    # --- Criterion 5: Color Coding (10 pts) ---
    colors = analysis.get("colors_used", [])
    # Filter out common defaults if necessary (usually '000000' or 'none')
    distinct_colors = len([c for c in colors if c not in ['#000000', 'black', 'none', 'default', 'white', '#ffffff']])
    
    if distinct_colors >= 2:
        score += 10
        feedback_parts.append(f"Color Coding: {distinct_colors} colors detected")
    elif distinct_colors == 1:
        score += 4
        feedback_parts.append("Color Coding: Minimal variety")
    else:
        feedback_parts.append("Color Coding: Monochrome/Default only")
        
    # --- Criterion 6: Legend (5 pts) ---
    if analysis.get("has_legend"):
        score += 5
        feedback_parts.append("Legend found")
    else:
        feedback_parts.append("No Legend")

    # --- Criterion 7: Multi-page & Structure (15 pts) ---
    num_pages = analysis.get("num_pages", 0)
    if num_pages >= 2:
        score += 10
        feedback_parts.append("Multi-page")
    else:
        feedback_parts.append("Single page only")
        
    if analysis.get("has_happy_path"):
        score += 5
        feedback_parts.append("Happy Path found")
    else:
        feedback_parts.append("No Happy Path page")
        
    # --- Criterion 8: Export (10 pts) ---
    png_size = result.get("png_size", 0)
    if result.get("png_exists") and png_size > 5000:
        score += 10
        feedback_parts.append("PNG exported")
    elif result.get("png_exists"):
        score += 2
        feedback_parts.append("PNG empty/small")
    else:
        feedback_parts.append("No PNG export")

    # Final result
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }