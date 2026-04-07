#!/usr/bin/env python3
"""Verifier for dynamic_threat_intel_pipeline task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_name(name):
    """Normalize names to ignore case and convert spaces/hyphens to underscores."""
    return name.lower().replace(' ', '_').replace('-', '_')

def verify_dynamic_threat_intel_pipeline(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Read result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/pipeline_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    new_searches = result.get('analysis', {}).get('new_searches', [])
    lookup_file_exists = result.get('lookup_file_exists', False)
    
    score = 0
    feedback_parts = []
    
    stage1_found = False
    stage1_logic_ok = False
    stage1_scheduled = False
    
    stage2_found = False
    stage2_logic_ok = False
    
    for search in new_searches:
        name = normalize_name(search.get('name', ''))
        spl = search.get('search', '').lower()
        is_scheduled = search.get('is_scheduled', False)
        
        # Check Stage 1: Generate_Threat_Intel
        if name == 'generate_threat_intel':
            stage1_found = True
            has_fail_keyword = any(kw in spl for kw in ['fail', 'invalid', 'denied'])
            if 'security_logs' in spl and 'outputlookup' in spl and 'local_threat_intel.csv' in spl and has_fail_keyword:
                stage1_logic_ok = True
            if is_scheduled:
                stage1_scheduled = True
                
        # Check Stage 2: Web_Threat_Correlation
        if name == 'web_threat_correlation':
            stage2_found = True
            # inputlookup or lookup handles both
            if 'web_logs' in spl and 'lookup' in spl and 'local_threat_intel.csv' in spl:
                stage2_logic_ok = True

    # Scoring Execution
    if stage1_found:
        score += 15
        feedback_parts.append("Generate_Threat_Intel report found")
        
        if stage1_logic_ok:
            score += 25
            feedback_parts.append("Stage 1 logic is correct (filters for failures and outputs to lookup)")
        else:
            feedback_parts.append("FAIL: Stage 1 logic is missing required SPL commands or keywords")
            
        if stage1_scheduled:
            score += 15
            feedback_parts.append("Stage 1 report is scheduled")
        else:
            feedback_parts.append("FAIL: Stage 1 report is NOT scheduled")
    else:
        feedback_parts.append("FAIL: Generate_Threat_Intel report NOT found")
        
    if stage2_found:
        score += 15
        feedback_parts.append("Web_Threat_Correlation report found")
        
        if stage2_logic_ok:
            score += 30
            feedback_parts.append("Stage 2 logic is correct (correlates web logs with lookup)")
        else:
            feedback_parts.append("FAIL: Stage 2 logic is missing required SPL commands (web_logs, lookup, etc.)")
    else:
        feedback_parts.append("FAIL: Web_Threat_Correlation report NOT found")

    if lookup_file_exists:
        feedback_parts.append("Bonus: Lookup file successfully executed and created physically")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }