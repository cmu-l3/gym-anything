#!/usr/bin/env python3
"""
Verifier for demographic_inequality_error_bars task.

Scoring (100 points total):
1. File Saved (10 pts): PBIX exists and was modified during task.
2. Data Measures (30 pts): Avg_LifeExp, Min_LifeExp, Max_LifeExp exist.
3. Visual Exists (20 pts): Line Chart present.
4. Error Bars Configured (40 pts): Visual references Min/Max measures for bounds.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_demographic_inequality(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    try:
        copy_from_env("C:/Users/Docker/Desktop/task_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. File Saved (10 pts)
    if result.get('file_exists') and result.get('file_created_during_task'):
        score += 10
        feedback.append("File saved successfully.")
    elif result.get('file_exists'):
        score += 5
        feedback.append("File exists but timestamp verification failed (pre-existing?).")
    else:
        feedback.append("File 'Inequality_Analysis.pbix' not found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # 2. Measures Created (30 pts)
    # Power BI stores measure names in the DataModel binary. 
    # The export script converted this to ASCII, so we search for the names.
    model_strings = result.get('model_strings', '')
    layout_content = result.get('layout_sample', '')
    
    measures = ["Avg_LifeExp", "Min_LifeExp", "Max_LifeExp"]
    found_measures = []
    for m in measures:
        # Check both model (definition) and layout (usage)
        if m in model_strings or m in layout_content:
            found_measures.append(m)
    
    score += len(found_measures) * 10
    if len(found_measures) == 3:
        feedback.append("All DAX measures created.")
    else:
        feedback.append(f"Missing measures: {set(measures) - set(found_measures)}.")

    # 3. Visual Type (20 pts)
    # Parse Layout JSON for "lineChart"
    try:
        layout_json = json.loads(layout_content) if layout_content else {}
        sections = layout_json.get('sections', [])
        visuals = []
        for section in sections:
            visuals.extend(section.get('visualContainers', []))
        
        has_line_chart = False
        line_chart_config = None
        
        for v in visuals:
            # Modern PBI JSON structure puts config in 'config' string
            config_str = v.get('config', '{}')
            config = json.loads(config_str)
            single_visual = config.get('singleVisual', {})
            vis_type = single_visual.get('visualType', '')
            
            if vis_type == 'lineChart':
                has_line_chart = True
                line_chart_config = config
                break
        
        if has_line_chart:
            score += 20
            feedback.append("Line Chart visual found.")
        else:
            feedback.append("No Line Chart visual found.")
            
    except Exception as e:
        feedback.append(f"Error parsing report layout: {str(e)}")
        has_line_chart = False

    # 4. Error Bars Configuration (40 pts)
    # If error bars are used, the visual MUST query the Min and Max measures,
    # even though they aren't on the main Y-axis.
    # We check if the line chart visual config references the Min/Max measures.
    if has_line_chart and line_chart_config:
        # Convert config back to string to search for measure references within that specific visual
        vis_config_str = json.dumps(line_chart_config)
        
        has_min = "Min_LifeExp" in vis_config_str
        has_max = "Max_LifeExp" in vis_config_str
        
        if has_min and has_max:
            score += 40
            feedback.append("Error Bars configured (Min/Max measures used in visual).")
        elif has_min or has_max:
            score += 20
            feedback.append("Partial Error Bars configuration (only one bound found).")
        else:
            feedback.append("Error Bars not detected (Min/Max measures not used in Line Chart).")
    elif has_line_chart:
        feedback.append("Could not verify Error Bars configuration.")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }