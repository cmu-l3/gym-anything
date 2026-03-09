#!/usr/bin/env python3
"""
Verifier for un_organizational_chart task.
"""

import json
import sys
import os
import tempfile

def verify_un_org_chart(traj, env_info, task_info):
    """
    Verify the UN Organizational Chart task.
    
    Criteria:
    1. File creation/modification (Anti-gaming).
    2. Principal Organs presence.
    3. Subsidiary Bodies presence.
    4. Specialized Agencies presence.
    5. Diagram structure (edges/pages).
    6. Visual styling (color coding).
    7. PNG Export.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. File Check (5 pts)
    if not result.get("drawio_file_exists"):
        return {"passed": False, "score": 0, "feedback": "FAIL: No draw.io file found."}
    
    if result.get("drawio_file_modified_after_start"):
        score += 5
        feedback_parts.append("File saved successfully")
    else:
        return {"passed": False, "score": 0, "feedback": "FAIL: File not modified during task."}

    # 2. Principal Organs (20 pts)
    organs = result.get("principal_organs_found", [])
    # Filter aliases to avoid double counting (e.g., ECOSOC vs Economic...)
    unique_organs = set()
    for o in organs:
        norm = o.lower()
        if "economic" in norm or "ecosoc" in norm: unique_organs.add("ecosoc")
        elif "court" in norm or "icj" in norm: unique_organs.add("icj")
        else: unique_organs.add(norm)
    
    if len(unique_organs) >= 5:
        score += 20
        feedback_parts.append(f"Principal Organs: {len(unique_organs)}/6 found")
    elif len(unique_organs) >= 3:
        score += 10
        feedback_parts.append(f"Principal Organs: {len(unique_organs)}/6 found (Partial)")
    else:
        feedback_parts.append(f"Principal Organs: Only {len(unique_organs)} found")

    # 3. Subsidiary Bodies (20 pts)
    bodies = result.get("subsidiary_bodies_found", [])
    if len(bodies) >= 6:
        score += 20
        feedback_parts.append(f"Subsidiary Bodies: {len(bodies)} found")
    elif len(bodies) >= 3:
        score += 10
        feedback_parts.append(f"Subsidiary Bodies: {len(bodies)} found (Partial)")
    else:
        feedback_parts.append(f"Subsidiary Bodies: Only {len(bodies)} found")

    # 4. Specialized Agencies (15 pts)
    agencies = result.get("specialized_agencies_found", [])
    if len(agencies) >= 6:
        score += 15
        feedback_parts.append(f"Specialized Agencies: {len(agencies)} found")
    elif len(agencies) >= 3:
        score += 7
        feedback_parts.append(f"Specialized Agencies: {len(agencies)} found (Partial)")
    else:
        feedback_parts.append(f"Specialized Agencies: Only {len(agencies)} found")

    # 5. Structure & Pages (20 pts)
    edges = result.get("edge_count", 0)
    pages = result.get("page_count", 0)
    
    if edges >= 12:
        score += 10
        feedback_parts.append(f"Connections: {edges} edges")
    elif edges >= 6:
        score += 5
        feedback_parts.append(f"Connections: {edges} edges (Partial)")
        
    if pages >= 2:
        score += 10
        feedback_parts.append("Multi-page diagram: Yes")
    else:
        feedback_parts.append("Multi-page diagram: No")

    # 6. Color Coding (10 pts)
    colors = result.get("fill_colors", [])
    if len(colors) >= 3:
        score += 10
        feedback_parts.append(f"Color coding: {len(colors)} distinct colors")
    elif len(colors) >= 2:
        score += 5
        feedback_parts.append(f"Color coding: {len(colors)} distinct colors (Partial)")
    else:
        feedback_parts.append("Color coding: Insufficient variation")

    # 7. PNG Export (10 pts)
    if result.get("png_file_exists") and result.get("png_file_size", 0) > 2000:
        score += 10
        feedback_parts.append("PNG export: Valid")
    elif result.get("png_file_exists"):
        score += 5
        feedback_parts.append("PNG export: File too small/empty")
    else:
        feedback_parts.append("PNG export: Missing")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }