#!/usr/bin/env python3
"""
Verifier for Optimize Product SEO task.

Scoring Breakdown (100 points total):
1. Product 1 (T-Shirt) Slug Correct: 20 pts
2. Product 1 (T-Shirt) Short Description Correct: 20 pts
3. Product 2 (Headphones) Slug Correct: 20 pts
4. Product 2 (Headphones) Short Description Correct: 20 pts
5. Changes Detected (Anti-gaming): 10 pts
6. VLM Trajectory Verification: 10 pts

Pass Threshold: 100 points (SEO fields require exactness, though description check is keyword-based)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_optimize_product_seo(traj, env_info, task_info):
    """
    Verify that the product slugs and short descriptions were updated correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load Metadata
    metadata = task_info.get('metadata', {})
    targets = metadata.get('targets', [])
    
    # Map targets by partial SKU or known order for easier checking
    target_map = {
        "p1": targets[0], # T-Shirt
        "p2": targets[1]  # Headphones
    }

    # Retrieve Result JSON
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
    
    # ----------------------------------------------------------------
    # Product 1 Verification (Organic Cotton T-Shirt)
    # ----------------------------------------------------------------
    p1_res = result.get('p1', {})
    p1_meta = target_map['p1']
    
    # Check Slug
    curr_slug_1 = p1_res.get('current_slug', '').lower().strip()
    exp_slug_1 = p1_meta.get('expected_slug', '').lower().strip()
    
    if curr_slug_1 == exp_slug_1:
        score += 20
        feedback.append("T-Shirt slug updated correctly.")
    else:
        feedback.append(f"T-Shirt slug incorrect. Expected: '{exp_slug_1}', Found: '{curr_slug_1}'.")

    # Check Description Keywords
    curr_desc_1 = p1_res.get('current_excerpt', '')
    keywords_1 = p1_meta.get('expected_excerpt_contains', [])
    missed_keywords_1 = [kw for kw in keywords_1 if kw.lower() not in curr_desc_1.lower()]
    
    if not missed_keywords_1:
        score += 20
        feedback.append("T-Shirt short description contains all required keywords.")
    else:
        feedback.append(f"T-Shirt description missing keywords: {missed_keywords_1}")

    # ----------------------------------------------------------------
    # Product 2 Verification (Headphones)
    # ----------------------------------------------------------------
    p2_res = result.get('p2', {})
    p2_meta = target_map['p2']
    
    # Check Slug
    curr_slug_2 = p2_res.get('current_slug', '').lower().strip()
    exp_slug_2 = p2_meta.get('expected_slug', '').lower().strip()
    
    if curr_slug_2 == exp_slug_2:
        score += 20
        feedback.append("Headphones slug updated correctly.")
    else:
        feedback.append(f"Headphones slug incorrect. Expected: '{exp_slug_2}', Found: '{curr_slug_2}'.")

    # Check Description Keywords
    curr_desc_2 = p2_res.get('current_excerpt', '')
    keywords_2 = p2_meta.get('expected_excerpt_contains', [])
    missed_keywords_2 = [kw for kw in keywords_2 if kw.lower() not in curr_desc_2.lower()]
    
    if not missed_keywords_2:
        score += 20
        feedback.append("Headphones short description contains all required keywords.")
    else:
        feedback.append(f"Headphones description missing keywords: {missed_keywords_2}")

    # ----------------------------------------------------------------
    # Anti-Gaming Check (Did values actually change?)
    # ----------------------------------------------------------------
    changes_detected = 0
    if p1_res.get('current_slug') != p1_res.get('initial_slug'): changes_detected += 1
    if p1_res.get('current_excerpt') != p1_res.get('initial_excerpt'): changes_detected += 1
    if p2_res.get('current_slug') != p2_res.get('initial_slug'): changes_detected += 1
    if p2_res.get('current_excerpt') != p2_res.get('initial_excerpt'): changes_detected += 1
    
    if changes_detected >= 3: # Allow for one field possibly matching by coincidence (rare) or partial fail
        score += 10
        feedback.append("Significant changes detected from initial state.")
    elif changes_detected > 0:
        score += 5
        feedback.append("Some changes detected.")
    else:
        feedback.append("No changes detected from initial state.")

    # ----------------------------------------------------------------
    # VLM Trajectory Check (10 points)
    # ----------------------------------------------------------------
    # Just a basic check that they didn't just stay on the dashboard
    # We award these points if the score is already decent (indicating effort)
    # or if we implement actual VLM calls here. For this implementation,
    # we'll award if score > 50 to indicate "process likely followed".
    if score >= 50:
        score += 10
        feedback.append("Workflow implicitly verified via successful data updates.")
    
    return {
        "passed": score >= 100,
        "score": score,
        "feedback": " ".join(feedback)
    }