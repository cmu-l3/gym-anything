#!/usr/bin/env python3
"""
Verifier for calculate_field_gdp_per_capita task.

Verifies:
1. 'GDP_PCAP' field exists in the DBF file
2. DBF file was modified during the task
3. Calculated values match formula: (GDP_MD_EST * 1000000) / POP_EST
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_calculate_field_gdp_per_capita(traj, env_info, task_info):
    """
    Verify the GDP per capita calculation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy result JSON
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
            
    # Extract data
    dbf = result.get('dbf_analysis', {})
    file_modified = result.get('file_modified', False)
    
    feedback_parts = []
    score = 0
    
    # Criteria 1: File Modification (10 pts)
    if file_modified:
        score += 10
        feedback_parts.append("Database file modified")
    else:
        feedback_parts.append("Database file NOT modified")
        
    # Criteria 2: Field Existence (20 pts)
    target_found = dbf.get('target_field_found', False)
    target_name = dbf.get('target_field_name', 'Unknown')
    
    if target_found:
        score += 20
        feedback_parts.append(f"Field '{target_name}' created")
    else:
        feedback_parts.append("Target field 'GDP_PCAP' NOT found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
    # Criteria 3: Calculation Correctness (70 pts)
    # Check a sample of records
    data = dbf.get('data', [])
    valid_records = 0
    correct_calculations = 0
    total_checked = 0
    
    # We check non-zero populations to avoid division by zero issues
    # Formula: gdp_md (millions) * 1e6 / pop
    
    for rec in data:
        pop = rec.get('pop')
        gdp_md = rec.get('gdp_md')
        agent_val = rec.get('target')
        
        # Skip invalid data
        if pop is None or gdp_md is None or agent_val is None:
            continue
            
        try:
            pop = float(pop)
            gdp_md = float(gdp_md)
            agent_val = float(agent_val)
        except (ValueError, TypeError):
            continue
            
        if pop <= 0:
            continue
            
        valid_records += 1
        
        # Expected value
        expected = (gdp_md * 1000000.0) / pop
        
        # Check tolerance (1%)
        if expected == 0:
            if agent_val == 0:
                correct_calculations += 1
        else:
            diff_pct = abs(agent_val - expected) / expected
            if diff_pct < 0.05: # 5% tolerance for floating point diffs
                correct_calculations += 1
            else:
                # Debug logging for first few failures
                if total_checked < 3:
                    logger.info(f"Mismatch {rec.get('name')}: Expected {expected:.2f}, Got {agent_val:.2f}")
        
        total_checked += 1
        
    accuracy = 0
    if valid_records > 0:
        accuracy = correct_calculations / valid_records
        
    feedback_parts.append(f"Calculation accuracy: {accuracy:.1%}")
    
    # Scoring for accuracy
    if accuracy >= 0.9:
        score += 70
    elif accuracy >= 0.7:
        score += 50
    elif accuracy >= 0.5:
        score += 30
    elif accuracy > 0:
        score += 10
    else:
        feedback_parts.append("Calculations appear incorrect")
        
    # Final verdict
    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "accuracy": accuracy,
            "field_found": target_found,
            "modified": file_modified
        }
    }