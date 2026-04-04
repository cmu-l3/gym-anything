#!/usr/bin/env python3
"""
Verifier for predictor_threshold_config task.

Scoring (100 points total):
- Data Element Created (20 pts)
- Data Element Config (15 pts) [Domain=Aggregate, Type=Number, Agg=Average]
- Predictor Created (20 pts)
- Predictor Config (45 pts) [Output Linked, Monthly, Sample=3, Expression Valid]

Pass Threshold: 60 points AND (Data Element Exists AND Predictor Exists)
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logger = logging.getLogger(__name__)

def verify_predictor_threshold_config(traj, env_info, task_info):
    """Verify creation and configuration of DHIS2 predictor and data element."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # 1. Load Result JSON
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()
        
        copy_from_env("/tmp/predictor_threshold_result.json", temp_path)
        
        with open(temp_path, 'r') as f:
            result = json.load(f)
        
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse result: {str(e)}"}

    score = 0
    feedback_parts = []
    
    task_start_iso = result.get("task_start_iso", "")
    
    # --- Verify Data Element ---
    de_candidates = result.get("candidate_data_elements", [])
    target_de = None
    
    # Filter candidates for one created AFTER task start
    for de in de_candidates:
        created = de.get("created", "")
        # Basic string comparison for ISO format works if TZ is consistent (DHIS2 uses UTC Z usually)
        # We'll allow fuzzy timing (created > start)
        if created >= task_start_iso:
            # Check name relevance
            name = de.get("name", "").lower()
            if "threshold" in name or "expected" in name:
                target_de = de
                break
    
    de_exists = False
    if target_de:
        de_exists = True
        score += 20
        feedback_parts.append(f"Data Element '{target_de.get('name')}' created (+20)")
        
        # Check DE Config
        de_config_score = 0
        if target_de.get("domainType") == "AGGREGATE":
            de_config_score += 5
        if target_de.get("valueType") in ["NUMBER", "INTEGER", "INTEGER_ZERO_OR_POSITIVE"]:
            de_config_score += 5
        if target_de.get("aggregationType") == "AVERAGE":
            de_config_score += 5
        
        if de_config_score == 15:
            feedback_parts.append("DE Config Correct (+15)")
        else:
            feedback_parts.append(f"DE Config Partial (+{de_config_score})")
        score += de_config_score
    else:
        feedback_parts.append("No new Data Element found matching 'Threshold' or 'Expected'")

    # --- Verify Predictor ---
    pred_candidates = result.get("candidate_predictors", [])
    target_pred = None
    
    for pred in pred_candidates:
        created = pred.get("created", "")
        if created >= task_start_iso:
            name = pred.get("name", "").lower()
            if "predictor" in name or "threshold" in name:
                target_pred = pred
                break
                
    pred_exists = False
    if target_pred:
        pred_exists = True
        score += 20
        feedback_parts.append(f"Predictor '{target_pred.get('name')}' created (+20)")
        
        # Check Predictor Config
        # 1. Output linkage (15 pts)
        output = target_pred.get("output", {})
        output_id = output.get("id")
        if target_de and output_id == target_de.get("id"):
            score += 15
            feedback_parts.append("Predictor correctly linked to new Data Element (+15)")
        else:
            feedback_parts.append("Predictor output NOT linked to new Data Element")
            
        # 2. Period Type (10 pts)
        if target_pred.get("periodType") == "Monthly":
            score += 10
            feedback_parts.append("Period: Monthly (+10)")
        else:
            feedback_parts.append(f"Period incorrect: {target_pred.get('periodType')}")
            
        # 3. Sample Count (10 pts)
        if str(target_pred.get("sequentialSampleCount")) == "3":
            score += 10
            feedback_parts.append("Sample Count: 3 (+10)")
        else:
            feedback_parts.append(f"Sample Count incorrect: {target_pred.get('sequentialSampleCount')}")
            
        # 4. Generator Expression (10 pts)
        generator = target_pred.get("generator", {})
        expression = generator.get("expression", "")
        if expression and "#{" in expression:
            score += 10
            feedback_parts.append("Generator expression configured (+10)")
        else:
            feedback_parts.append("Generator expression missing or invalid")
            
    else:
        feedback_parts.append("No new Predictor found matching criteria")

    # --- Final Result ---
    # Mandatory Criteria: Both objects must be created
    passed = (score >= 60) and de_exists and pred_exists
    
    if not de_exists or not pred_exists:
        feedback_parts.append("FAILED: Both Data Element and Predictor must be created.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }