#!/usr/bin/env python3
"""
Verifier for glycolysis_metabolic_pathway task.

Scoring Breakdown (100 pts):
- Files (drawio + png) exist & modified: 10 pts
- Molecules Correct: 30 pts (5 pts per unique molecule type found)
- Enzymes Correct: 25 pts (5 pts per unique enzyme found)
- ATP/ADP Indicated: 10 pts
- Split Topology Detected: 15 pts
- PNG Export Valid: 10 pts

Pass Threshold: 65 pts
"""

import json
import tempfile
import os

def verify_glycolysis_pathway(traj, env_info, task_info):
    """Verify the glycolysis pathway diagram."""
    
    # 1. Retrieve result from container
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
    
    # 2. Score: Files Exist (10 pts)
    if result.get('file_exists') and result.get('file_modified'):
        score += 10
        feedback_parts.append("Draw.io file saved and modified")
    else:
        feedback_parts.append("Draw.io file missing or not modified")
        
    # 3. Score: Molecules (Max 30 pts)
    # Expected: Glucose, G6P, F6P, F1,6BP, DHAP, G3P (6 items)
    mols = result.get('molecules_found', [])
    # Normalize count: DHAP and G3P might be aliased, analysis script handles aliasing
    # We count unique identified entities.
    unique_mols = len(set(mols))
    mol_score = min(30, unique_mols * 5)
    score += mol_score
    feedback_parts.append(f"Molecules found: {unique_mols}/6 ({mol_score} pts)")
    
    # 4. Score: Enzymes (Max 25 pts)
    # Expected: 5 enzymes
    enzs = result.get('enzymes_found', [])
    # Analysis script returns list of found enzyme names (from our list)
    # Filter duplicates just in case
    unique_enzs = len(set(enzs))
    enz_score = min(25, unique_enzs * 5)
    score += enz_score
    feedback_parts.append(f"Enzymes found: {unique_enzs}/5 ({enz_score} pts)")
    
    # 5. Score: ATP/ADP (10 pts)
    if result.get('atp_found') or result.get('adp_found'):
        score += 10
        feedback_parts.append("ATP/ADP consumption indicated (10 pts)")
    else:
        feedback_parts.append("Missing ATP/ADP labels")
        
    # 6. Score: Split Topology (15 pts)
    if result.get('split_detected'):
        score += 15
        feedback_parts.append("Pathway split detected (15 pts)")
    elif unique_mols >= 5 and unique_enzs >= 4:
        # Partial credit if content is there but logic missed split detection
        score += 5
        feedback_parts.append("Split not detected, but content is rich (5 pts)")
    else:
        feedback_parts.append("Pathway split missing or diagram incomplete")
        
    # 7. Score: PNG Export (10 pts)
    if result.get('png_exists') and result.get('png_size', 0) > 1000:
        score += 10
        feedback_parts.append("PNG export valid (10 pts)")
    else:
        feedback_parts.append("PNG export missing or empty")

    # Final tally
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }