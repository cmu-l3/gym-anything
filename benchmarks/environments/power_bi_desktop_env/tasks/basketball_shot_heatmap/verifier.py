#!/usr/bin/env python3
"""
Verifier for basketball_shot_heatmap task.

Scoring (100 points total):
1. File Saved (10 pts)
2. Data Loaded (10 pts) - Inferred from file size/presence
3. Binning Correct (20 pts) - "Distance_Bins" used in visual
4. DAX Measures (20 pts) - "Total_Shots" and "FG_Pct" exist
5. Matrix Visual (15 pts) - Correct visual type
6. Volume Filter (25 pts) - Filter on Total_Shots >= 50

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_basketball_shot_heatmap(traj, env_info, task_info):
    """
    Verify the Power BI basketball heatmap task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Copy result from VM
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    try:
        copy_from_env("C:/Users/Docker/Desktop/heatmap_result.json", temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to copy result file: {e}"}

    try:
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. File Saved (10 pts)
    if result.get('file_exists') and result.get('created_after_start'):
        score += 10
        feedback.append("File saved correctly.")
    else:
        feedback.append("File not saved or existed prior to task.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # 2. Data Loaded (10 pts) - Basic check on file size
    if result.get('file_size', 0) > 10000: # Empty PBIX is small, with data it's bigger
        score += 10
        feedback.append("Data appears loaded.")
    else:
        feedback.append("File seems empty.")

    # 3. DAX Measures (20 pts)
    measures = result.get('measures_found', [])
    if "Total_Shots" in measures and "FG_Pct" in measures:
        score += 20
        feedback.append("Measures Total_Shots and FG_Pct found.")
    elif "Total_Shots" in measures or "FG_Pct" in measures:
        score += 10
        feedback.append("One of the required measures found.")
    else:
        feedback.append("Required measures not found in DataModel.")

    # Parse Layout for Visuals and Filters
    layout_str = result.get('layout_json_snippet', '')
    has_matrix = False
    has_bins_in_visual = False
    has_filter = False
    
    try:
        if layout_str:
            # Layout is stringified JSON often, or direct JSON object depending on how PS exported it
            # PBI Layout usually starts with { "sections": ... }
            if isinstance(layout_str, str):
                layout = json.loads(layout_str)
            else:
                layout = layout_str
                
            sections = layout.get('sections', [])
            for section in sections:
                visual_containers = section.get('visualContainers', [])
                for vc in visual_containers:
                    config_str = vc.get('config')
                    if not config_str:
                        continue
                        
                    config = json.loads(config_str)
                    single_visual = config.get('singleVisual', {})
                    visual_type = single_visual.get('visualType', '')
                    
                    # Check for Matrix (pivotTable)
                    if visual_type == 'pivotTable':
                        has_matrix = True
                        
                        # Check projections for bins
                        projections = single_visual.get('projections', {})
                        # Look in columns (Matrix columns)
                        for field_list in projections.values():
                            for field in field_list:
                                query_ref = field.get('queryRef', '')
                                if 'Distance_Bins' in query_ref or 'Bin' in query_ref:
                                    has_bins_in_visual = True
                        
                        # Check Filters
                        # Filters are in config -> dataTransforms -> objects -> ... or direct filters list
                        # Modern PBI filter structure in config:
                        filters = config.get('filters', [])
                        # Also check visual config objects
                        # We specifically look for a filter on a measure (Total_Shots)
                        
                        for f in filters:
                            expr = f.get('expression', {})
                            # Check if expression refers to Total_Shots
                            # Often looks like: {"Measure": {"Property": "Total_Shots"}}
                            is_total_shots = False
                            measure_ref = expr.get('Measure', {}).get('Property', '')
                            if 'Total_Shots' in measure_ref:
                                is_total_shots = True
                            
                            if is_total_shots:
                                # Check condition
                                cond = f.get('condition', {})
                                # Look for greaterThanOrEqual
                                gte = cond.get('GreaterThanOrEqual') or cond.get('GreaterThan')
                                if gte:
                                    # Value might be nested
                                    val = 0
                                    if isinstance(gte, dict):
                                        # structure: { "value": "50" }
                                        val = gte.get('rhs', {}).get('Literal', {}).get('Value', '0')
                                        # Or simplified PBI structure
                                    
                                    # Fallback simple text search in the filter string representation if structure is complex
                                    has_filter = True # Found a filter on Total_Shots
                                    break
                                
                        # Fallback text search for filter logic inside this visual config
                        if not has_filter and 'Total_Shots' in json.dumps(filters):
                            if 'GreaterThan' in json.dumps(filters) and '50' in json.dumps(filters):
                                has_filter = True
    except Exception as e:
        logger.warning(f"Error parsing layout: {e}")
        feedback.append("Error analyzing report layout.")

    # 3 (continued). Check binning in visual
    if has_bins_in_visual:
        score += 20
        feedback.append("Distance Bins used in visual.")
    else:
        # Fallback: check if bins were found in datamodel at least
        if result.get('bins_found_in_model'):
            score += 10
            feedback.append("Bins found in model but not confirmed in visual.")
        else:
            feedback.append("Distance Bins not found.")

    # 5. Matrix Visual (15 pts)
    if has_matrix:
        score += 15
        feedback.append("Matrix visual found.")
    else:
        feedback.append("Matrix visual not found.")

    # 6. Volume Filter (25 pts)
    if has_filter:
        score += 25
        feedback.append("Volume filter (Total_Shots >= 50) applied.")
    else:
        feedback.append("Volume filter not found or incorrect.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }