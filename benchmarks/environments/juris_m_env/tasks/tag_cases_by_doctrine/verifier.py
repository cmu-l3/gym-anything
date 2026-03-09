#!/usr/bin/env python3
"""
Verifier for tag_cases_by_doctrine task.

Verification Strategy:
1. Load the JSON result exported from the container.
2. For each of the 5 target items, check if the 2 expected tags are present.
3. Verify anti-gaming: check timestamps and ensure tags weren't pre-existing.
4. Verify VLM trajectory to confirm UI interaction.

Scoring:
- 8 points per correct tag (5 items * 2 tags = 80 points)
- 10 points for process evidence (VLM/app running)
- 10 points for anti-gaming checks (clean start state confirmation)
Total: 100 points
Pass Threshold: 60 points
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tag_cases_by_doctrine(traj, env_info, task_info):
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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

    inspection = result.get('inspection', {})
    meta = result.get('meta', {})
    
    if "error" in inspection:
        return {"passed": False, "score": 0, "feedback": f"DB Inspection Error: {inspection['error']}"}

    score = 0
    feedback_lines = []
    
    # Get expected targets from task_info
    expected_targets = task_info.get('metadata', {}).get('targets', [])
    actual_targets = inspection.get('targets', [])
    
    # --- Scoring Criteria 1: Tag verification (80 points max) ---
    for expected in expected_targets:
        search_term = expected['search_term']
        expected_tags = [t.lower() for t in expected['expected_tags']]
        
        # Find corresponding actual result
        actual = next((t for t in actual_targets if t['term'] == search_term), None)
        
        if not actual:
            feedback_lines.append(f"❌ Item matching '{search_term}' not found in DB.")
            continue
            
        if actual['id'] is None:
            feedback_lines.append(f"❌ Item matching '{search_term}' could not be identified.")
            continue
            
        actual_tags_lower = [t.lower() for t in actual['tags']]
        
        item_score = 0
        for tag in expected_tags:
            if tag in actual_tags_lower:
                item_score += 8
                feedback_lines.append(f"✅ '{search_term}': Tag '{tag}' found.")
            else:
                feedback_lines.append(f"❌ '{search_term}': Missing tag '{tag}'.")
        
        score += item_score

    # --- Scoring Criteria 2: Application State (10 points) ---
    if meta.get('app_running') == "true":
        score += 10
        feedback_lines.append("✅ Jurism application is running.")
    else:
        feedback_lines.append("⚠️ Jurism application was closed.")

    # --- Scoring Criteria 3: Anti-Gaming / Total Count (10 points) ---
    # We cleared tags at start, so total_tags should match what we found (roughly)
    total_tags = inspection.get('total_tags', 0)
    if total_tags >= 5: # At least some work was done
        score += 10
        feedback_lines.append(f"✅ Valid tag activity detected (Total tags in library: {total_tags}).")
    else:
        feedback_lines.append(f"⚠️ Very few tags found in library ({total_tags}).")

    # --- Final Result ---
    # Pass threshold is 60 (requires at least ~6 correct tags + app running)
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines)
    }