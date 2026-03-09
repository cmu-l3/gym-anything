#!/usr/bin/env python3
"""
Verifier for High Burden District Ranking Visualization task.

SCORING CRITERIA (100 pts total):
1. Visualization Saved in DHIS2 (20 pts)
   - Must match name pattern "Top 10... Malaria..."
2. Sort Order Configured (20 pts)
   - API sortOrder must indicate descending (-1)
3. Value Labels Enabled (15 pts)
   - API showValues must be true
4. Subtitle Configured (15 pts)
   - Must contain "Source: National Malaria Control Programme"
5. Data/Period/Type Correct (10 pts)
   - Type: COLUMN or BAR
   - Period: 2023
6. PNG Exported (20 pts)
   - File exists, created during task, valid size

PASS THRESHOLD: 65 pts
"""

import json
import os
import logging
import tempfile

logger = logging.getLogger(__name__)

def verify_high_burden_district_ranking_viz(traj, env_info, task_info):
    """Verify the visualization configuration and export."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    # 1. Load result file
    temp_path = tempfile.mktemp(suffix='.json')
    try:
        copy_from_env("/tmp/high_burden_viz_result.json", temp_path)
        with open(temp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)

    score = 0
    feedback = []
    
    # Data extraction
    file_check = result.get('file_check', {})
    api_check = result.get('api_check', {})
    viz_found = api_check.get('found', False)
    viz_data = api_check.get('data', {})

    # --- CRITERION 1: Visualization Saved (20 pts) ---
    if viz_found:
        score += 20
        feedback.append("Visualization saved successfully (+20)")
    else:
        feedback.append("Visualization NOT found in DHIS2")

    # --- CRITERION 2: Sort Order (20 pts) ---
    # DHIS2 API: sortOrder = -1 (DESC), 1 (ASC), 0 (NONE)
    if viz_found:
        sort_order = viz_data.get('sortOrder', 0)
        if sort_order == -1:
            score += 20
            feedback.append("Sort order set to Descending (+20)")
        else:
            feedback.append(f"Sort order incorrect (found {sort_order}, expected -1/Descending)")
    
    # --- CRITERION 3: Value Labels (15 pts) ---
    # DHIS2 API: showValues = true/false
    if viz_found:
        show_values = viz_data.get('showValues', False)
        if show_values:
            score += 15
            feedback.append("Value labels enabled (+15)")
        else:
            feedback.append("Value labels NOT enabled")

    # --- CRITERION 4: Subtitle (15 pts) ---
    if viz_found:
        subtitle = viz_data.get('subtitle', '')
        if "National Malaria Control Programme" in subtitle:
            score += 15
            feedback.append("Subtitle configured correctly (+15)")
        else:
            feedback.append(f"Subtitle incorrect or missing (found: '{subtitle}')")

    # --- CRITERION 5: Data/Period/Type (10 pts) ---
    if viz_found:
        viz_type = viz_data.get('type', '')
        # Check period in dimensions (columns/rows/filters)
        # We look for '2023' in the item names or IDs
        all_dims = viz_data.get('columns', []) + viz_data.get('rows', []) + viz_data.get('filters', [])
        has_2023 = False
        for dim in all_dims:
            for item in dim.get('items', []):
                if '2023' in item.get('name', '') or '2023' in item.get('id', ''):
                    has_2023 = True
        
        type_ok = viz_type in ['COLUMN', 'BAR']
        
        if type_ok and has_2023:
            score += 10
            feedback.append("Chart type and Period correct (+10)")
        else:
            feedback.append(f"Chart type ({viz_type}) or Period check failed (Has 2023: {has_2023})")

    # --- CRITERION 6: PNG Export (20 pts) ---
    if file_check.get('exists') and file_check.get('created_during_task'):
        fsize = file_check.get('size', 0)
        if fsize > 1000: # Arbitrary small limit to ensure not empty
            score += 20
            feedback.append("Valid PNG export found on Desktop (+20)")
        else:
            score += 10
            feedback.append("PNG found but seems too small/empty (+10)")
    else:
        feedback.append("No new PNG export found on Desktop")

    # Final Evaluation
    passed = (score >= 65) and viz_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }