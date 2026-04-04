#!/usr/bin/env python3
"""
Verifier for Perseverance SysML BDD Task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_perseverance_sysml_bdd(traj, env_info, task_info):
    """
    Verifies the creation of a SysML Block Definition Diagram.
    
    Criteria:
    1. .drawio file exists and is valid (10 pts)
    2. PNG export exists (10 pts)
    3. Structural Analysis (XML):
       - Core blocks found (Perseverance, Power, Mobility, Science, etc.) (30 pts)
       - Composition edges (Diamonds) used (25 pts)
       - Multiplicity/Mass properties found (15 pts)
    4. Anti-gaming: File created during task (10 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}
    
    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. File Checks
    if result.get("file_exists") and result.get("file_modified"):
        score += 10
        feedback.append("Draw.io file saved successfully.")
    else:
        feedback.append("Draw.io file missing or not modified.")
        
    if result.get("png_exists"):
        score += 10
        feedback.append("PNG export found.")
    else:
        feedback.append("PNG export missing.")
        
    # 2. XML Analysis
    analysis = result.get("analysis", {})
    
    # Check Blocks
    found_terms = analysis.get("found_terms", {})
    terms_count = sum(1 for v in found_terms.values() if v)
    total_terms = len(found_terms)
    
    if terms_count == total_terms:
        score += 30
        feedback.append(f"All {terms_count} required blocks identified.")
    elif terms_count >= 3:
        # Partial credit
        partial = int((terms_count / total_terms) * 30)
        score += partial
        feedback.append(f"Found {terms_count}/{total_terms} required blocks.")
    else:
        feedback.append("Significant blocks missing (e.g., Perseverance, MMRTG, Mobility).")
        
    # Check Composition
    comp_edges = analysis.get("composition_edges", 0)
    if comp_edges >= 6:
        score += 25
        feedback.append(f"Excellent use of Composition (found {comp_edges} diamond edges).")
    elif comp_edges >= 3:
        score += 15
        feedback.append(f"Some Composition edges found ({comp_edges}), but diagram may be incomplete.")
    elif comp_edges > 0:
        score += 5
        feedback.append("Few composition edges found.")
    else:
        feedback.append("No Composition (Diamond) relationships found. SysML BDD requires composition.")
        
    # Check Properties
    if analysis.get("mass_property_found"):
        score += 10
        feedback.append("Mass properties identified correctly.")
    
    if analysis.get("multiplicity_labels", 0) > 0:
        score += 5
        feedback.append("Multiplicity labels found.")
        
    # Anti-gaming / Minimum effort check
    block_count = analysis.get("block_count", 0)
    if block_count < 5:
        score = min(score, 40) # Cap score if diagram is trivial
        feedback.append("Diagram is too simple (fewer than 5 blocks).")

    # Final Pass Decision
    passed = score >= 65 and comp_edges >= 3
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }