#!/usr/bin/env python3
"""
Verifier for openvsp_cfd_mesh_generation task.

Verification Criteria (100 points total):
1. STL file exists, valid format, size > 500KB (15 pts)
2. STL triangle count in [5,000 - 500,000] (15 pts)
3. GMSH file exists, valid format, size > 100KB (15 pts)
4. GMSH valid headers (Nodes/Elements) present (10 pts)
5. Report exists (5 pts)
6. Report contains valid triangle count (10 pts)
7. Report contains valid node count (10 pts)
8. Report/STL cross-validation: Reported tris match STL tris (10 pts)
9. Report mentions requested mesh parameters (5 pts)
10. Anti-gaming: Files modified after task start (5 pts)

Pass Threshold: 60 points. Must have at least one valid mesh file (STL or GMSH).
"""

import json
import os
import re
import tempfile


def verify_openvsp_cfd_mesh_generation(trajectory, env_info, task_info):
    # Setup copy from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Prepare temporary file for the result JSON
    local_tmp = tempfile.mktemp(suffix=".json")
    try:
        copy_from_env("/tmp/openvsp_cfd_mesh_result.json", local_tmp)
        with open(local_tmp, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to retrieve or read result file: {e}"
        }
    finally:
        if os.path.exists(local_tmp):
            os.unlink(local_tmp)

    score = 0
    feedback_parts = []
    
    task_start = data.get('task_start_time', 0)
    stl = data.get('stl', {})
    gmsh = data.get('gmsh', {})
    report = data.get('report', {})
    
    # Check 1 & 2: STL File (30 pts)
    stl_exists = stl.get('exists', False)
    stl_size = stl.get('size', 0)
    stl_tris = stl.get('triangles', 0)
    
    if stl_exists and stl_size > 500000: # 500 KB
        score += 15
        feedback_parts.append(f"STL exists and size is good ({stl_size/1024:.1f} KB)")
        
        if 5000 <= stl_tris <= 500000:
            score += 15
            feedback_parts.append(f"STL triangle count is reasonable ({stl_tris})")
        else:
            feedback_parts.append(f"STL triangle count out of bounds ({stl_tris})")
    elif stl_exists:
        # Partial points if small file
        score += 5
        feedback_parts.append(f"STL exists but size is small ({stl_size/1024:.1f} KB)")
    else:
        feedback_parts.append("STL mesh file not found")

    # Check 3 & 4: GMSH File (25 pts)
    gmsh_exists = gmsh.get('exists', False)
    gmsh_size = gmsh.get('size', 0)
    
    if gmsh_exists and gmsh_size > 100000: # 100 KB
        score += 15
        feedback_parts.append(f"GMSH exists and size is good ({gmsh_size/1024:.1f} KB)")
        
        if gmsh.get('has_nodes') and gmsh.get('has_elements'):
            score += 10
            feedback_parts.append("GMSH headers valid")
        else:
            feedback_parts.append("GMSH headers missing ($Nodes / $Elements)")
    elif gmsh_exists:
        score += 5
        feedback_parts.append(f"GMSH exists but size is small ({gmsh_size/1024:.1f} KB)")
    else:
        feedback_parts.append("GMSH mesh file not found")

    # Check 5: Report exists (5 pts)
    report_exists = report.get('exists', False)
    report_content = report.get('content', '')
    
    if report_exists and len(report_content.strip()) > 10:
        score += 5
        feedback_parts.append("Report file created")
        
        # Parse report for numbers
        # Find triangle count
        tri_match = re.search(r'(?i)(?:triangles?|elements?|tris)[^\d]*(\d+)', report_content)
        report_tris = int(tri_match.group(1)) if tri_match else 0
        
        # Find node count
        node_match = re.search(r'(?i)(?:nodes?|vertices|verts)[^\d]*(\d+)', report_content)
        report_nodes = int(node_match.group(1)) if node_match else 0
        
        # Check 6: Triangle Count in Report (10 pts)
        if 5000 <= report_tris <= 500000:
            score += 10
            feedback_parts.append(f"Report triangle count valid ({report_tris})")
        else:
            feedback_parts.append(f"Report triangle count invalid or missing (found: {report_tris})")
            
        # Check 7: Node Count in Report (10 pts)
        if 2000 <= report_nodes <= 300000:
            score += 10
            feedback_parts.append(f"Report node count valid ({report_nodes})")
        else:
            feedback_parts.append(f"Report node count invalid or missing (found: {report_nodes})")
            
        # Check 8: Cross-validation (10 pts)
        if stl_tris > 0 and report_tris > 0:
            # Check if reported tris are within 50% of STL tris
            if abs(stl_tris - report_tris) / float(stl_tris) < 0.5:
                score += 10
                feedback_parts.append("Report triangle count matches STL data")
            else:
                feedback_parts.append(f"Report tris ({report_tris}) diverge from STL tris ({stl_tris})")
        else:
            feedback_parts.append("Missing data for report cross-validation")
            
        # Check 9: Mentions Parameters (5 pts)
        # Parameters expected: 0.5, 0.01, 0.005, 16, 1.3
        params_found = 0
        for p in ["0.5", "0.01", "0.005", "16", "1.3"]:
            if p in report_content:
                params_found += 1
        
        if params_found >= 2:
            score += 5
            feedback_parts.append(f"Report mentions {params_found} mesh parameters")
        else:
            feedback_parts.append(f"Report missing mesh parameters (found {params_found})")
            
    else:
        feedback_parts.append("Report file not found or empty")

    # Check 10: Anti-gaming (5 pts)
    files_created_during_task = False
    if stl_exists and stl.get('mtime', 0) >= task_start:
        files_created_during_task = True
    if gmsh_exists and gmsh.get('mtime', 0) >= task_start:
        files_created_during_task = True
        
    if files_created_during_task:
        score += 5
        feedback_parts.append("Mesh files generated during task (anti-gaming)")
    elif stl_exists or gmsh_exists:
        feedback_parts.append("WARNING: Mesh files appear older than task start")

    # Final pass/fail logic
    # Must achieve threshold AND have actually created at least one valid mesh
    has_valid_mesh = (stl_exists and stl_tris >= 5000) or (gmsh_exists and gmsh_size >= 100000)
    passed = score >= 60 and has_valid_mesh

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }