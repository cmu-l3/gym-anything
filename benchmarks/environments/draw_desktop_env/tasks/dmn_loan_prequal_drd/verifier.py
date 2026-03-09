#!/usr/bin/env python3
"""
Verifier for dmn_loan_prequal_drd task.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_dmn_loan_prequal_drd(traj, env_info, task_info):
    """Verify the DMN Decision Requirements Diagram."""
    
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
    
    # 1. File Existence (10 pts)
    if result.get('file_exists') and result.get('file_modified_after_start'):
        score += 10
        feedback.append("Draw.io file saved")
    else:
        feedback.append("Draw.io file not saved or not modified")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    analysis = result.get('analysis', {})
    
    # 2. Input Nodes (20 pts)
    # Expect 4: credit score, annual income, loan amount, monthly debt
    inputs_found = set(analysis.get('inputs_found', []))
    expected_inputs = {"credit score", "annual income", "loan amount", "monthly debt"}
    # Allow some fuzzy matching handled in export script
    unique_inputs = len(inputs_found)
    
    if unique_inputs >= 4:
        score += 20
        feedback.append("All 4 Input Data nodes found")
    elif unique_inputs >= 2:
        score += 10
        feedback.append(f"Only {unique_inputs}/4 Input Data nodes found")
    else:
        feedback.append("Missing Input Data nodes")

    # 3. Decision Nodes (20 pts)
    # Expect 3: risk tier, dti ratio, result
    decisions_found = set(analysis.get('decisions_found', []))
    unique_decisions = 0
    # Map synonyms
    if "risk tier" in decisions_found: unique_decisions += 1
    if "dti ratio" in decisions_found: unique_decisions += 1
    if any(x in decisions_found for x in ["pre-qualification result", "pre-qual", "result"]): unique_decisions += 1
    
    if unique_decisions >= 3:
        score += 20
        feedback.append("All 3 Decision nodes found")
    elif unique_decisions >= 1:
        score += 10
        feedback.append(f"Only {unique_decisions}/3 Decision nodes found")
    else:
        feedback.append("Missing Decision nodes")

    # 4. Topology / Edges (30 pts)
    connections = analysis.get('connections', [])
    num_edges = len(connections)
    connections_str = " ".join(connections).lower()
    
    # Check for specific key relationships
    topo_score = 0
    # Risk depends on Score
    if "score" in connections_str and "risk" in connections_str: topo_score += 5
    # DTI depends on Income/Debt
    if ("income" in connections_str or "debt" in connections_str) and "dti" in connections_str: topo_score += 5
    # Result depends on Risk
    if "risk" in connections_str and ("result" in connections_str or "qual" in connections_str): topo_score += 5
    # Result depends on DTI
    if "dti" in connections_str and ("result" in connections_str or "qual" in connections_str): topo_score += 5
    
    # Base points for having edges at all
    if num_edges >= 6:
        topo_score += 10
    elif num_edges >= 3:
        topo_score += 5
        
    score += topo_score
    if topo_score >= 20:
        feedback.append("Topology logic correct")
    else:
        feedback.append(f"Topology incomplete (edges found: {num_edges})")

    # 5. Shape Distinction (10 pts)
    shapes = analysis.get('shape_types', {})
    ellipses = shapes.get('ellipse', 0)
    rectangles = shapes.get('rectangle', 0)
    
    if ellipses > 0 and rectangles > 0:
        score += 10
        feedback.append("Used distinct shapes for Inputs vs Decisions")
    else:
        feedback.append("Shapes not distinct (all same type?)")

    # 6. PNG Export (10 pts)
    if result.get('png_exists'):
        score += 10
        feedback.append("PNG export found")
    else:
        feedback.append("PNG export missing")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }