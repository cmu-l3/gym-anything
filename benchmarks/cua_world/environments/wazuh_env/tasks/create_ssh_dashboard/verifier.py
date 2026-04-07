#!/usr/bin/env python3
"""
Verifier for create_ssh_dashboard task.

Verifies:
1. A dashboard named "SSH Threat Monitoring" exists.
2. A "SSH Failures Over Time" visualization exists (Bar Chart/Histogram).
3. A "Top SSH Attacking IPs" visualization exists (Pie Chart/Terms Aggregation).
4. Visualizations are correctly configured (Fields, Aggregations).
5. Visualizations are added to the Dashboard.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_ssh_dashboard(traj, env_info, task_info):
    """
    Verify the SSH dashboard creation using exported API data.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    dash_title_req = metadata.get('dashboard_title', "SSH Threat Monitoring")
    vis1_title_req = metadata.get('vis1_title', "SSH Failures Over Time")
    vis2_title_req = metadata.get('vis2_title', "Top SSH Attacking IPs")
    required_field = metadata.get('required_field', "data.srcip")

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    saved_objects = result.get("saved_objects", {})
    if not saved_objects.get("api_accessible", False):
        return {"passed": False, "score": 0, "feedback": "Could not access Kibana Saved Objects API for verification."}

    dashboards = saved_objects.get("dashboards", [])
    visualizations = saved_objects.get("visualizations", [])

    score = 0
    feedback = []
    
    # 1. Verify Dashboard Existence (20 pts)
    target_dashboard = None
    for d in dashboards:
        # Check title (attributes.title)
        title = d.get('attributes', {}).get('title', '')
        if dash_title_req.lower() in title.lower():
            target_dashboard = d
            break
    
    if target_dashboard:
        score += 20
        feedback.append(f"Dashboard '{dash_title_req}' found.")
    else:
        feedback.append(f"Dashboard '{dash_title_req}' NOT found.")

    # 2. Verify Visualization 1: Failures Over Time (Bar Chart) (25 pts)
    # Criteria: Title match + Type histogram/area + Date Histogram aggregation
    vis1_found = False
    vis1_valid = False
    
    for v in visualizations:
        attrs = v.get('attributes', {})
        title = attrs.get('title', '')
        
        if vis1_title_req.lower() in title.lower():
            vis1_found = True
            
            # Parse visState JSON string
            try:
                vis_state = json.loads(attrs.get('visState', '{}'))
            except:
                vis_state = {}
            
            vis_type = vis_state.get('type', '')
            aggs = vis_state.get('aggs', [])
            
            # Check type (histogram, vertical_bar, etc.)
            type_ok = vis_type in ['histogram', 'vertical_bar', 'area']
            
            # Check aggregation (date_histogram)
            agg_ok = False
            for agg in aggs:
                if agg.get('type') == 'date_histogram':
                    agg_ok = True
                    break
            
            if type_ok and agg_ok:
                vis1_valid = True
            elif not type_ok:
                feedback.append(f"Vis 1 '{title}' has wrong type: {vis_type} (expected histogram).")
            elif not agg_ok:
                feedback.append(f"Vis 1 '{title}' missing Date Histogram aggregation.")
            break
            
    if vis1_found:
        score += 10
        feedback.append(f"Visualization '{vis1_title_req}' found.")
        if vis1_valid:
            score += 15
            feedback.append("Visualization 1 configuration correct (Date Histogram).")
    else:
        feedback.append(f"Visualization '{vis1_title_req}' NOT found.")

    # 3. Verify Visualization 2: Top IPs (Pie Chart) (25 pts)
    # Criteria: Title match + Type pie + Terms aggregation on data.srcip
    vis2_found = False
    vis2_valid = False
    
    for v in visualizations:
        attrs = v.get('attributes', {})
        title = attrs.get('title', '')
        
        if vis2_title_req.lower() in title.lower():
            vis2_found = True
            
            try:
                vis_state = json.loads(attrs.get('visState', '{}'))
            except:
                vis_state = {}
            
            vis_type = vis_state.get('type', '')
            aggs = vis_state.get('aggs', [])
            
            type_ok = vis_type == 'pie'
            
            # Check aggregation (terms on srcip)
            agg_ok = False
            for agg in aggs:
                if agg.get('type') == 'terms':
                    field = agg.get('params', {}).get('field', '')
                    # Check for srcip or data.srcip
                    if 'srcip' in field:
                        agg_ok = True
                        break
            
            if type_ok and agg_ok:
                vis2_valid = True
            elif not type_ok:
                feedback.append(f"Vis 2 '{title}' has wrong type: {vis_type} (expected pie).")
            elif not agg_ok:
                feedback.append(f"Vis 2 '{title}' missing Terms aggregation on srcip.")
            break
            
    if vis2_found:
        score += 10
        feedback.append(f"Visualization '{vis2_title_req}' found.")
        if vis2_valid:
            score += 15
            feedback.append("Visualization 2 configuration correct (Pie/Terms).")
    else:
        feedback.append(f"Visualization '{vis2_title_req}' NOT found.")

    # 4. Verify Dashboard Content (20 pts)
    # Check if the visualizations are actually ON the dashboard
    # The dashboard object has a 'panelsJSON' string containing references
    dashboard_integrated = False
    if target_dashboard and vis1_found and vis2_found:
        panels_json = target_dashboard.get('attributes', {}).get('panelsJSON', '[]')
        # We can check if the panels list is not empty, or try to parse and match IDs
        # Simple check: does it have at least 2 panels?
        try:
            panels = json.loads(panels_json)
            if len(panels) >= 2:
                dashboard_integrated = True
        except:
            pass
            
    if dashboard_integrated:
        score += 20
        feedback.append("Dashboard contains multiple panels.")
    elif target_dashboard:
        feedback.append("Dashboard appears empty (no panels found).")

    # 5. Anti-gaming / basic logic (10 pts)
    # Ensure some time passed
    task_start = result.get('task_start', 0)
    task_end = result.get('task_end', 0)
    if (task_end - task_start) > 10:
        score += 10
    
    # Calculate Final
    passed = (score >= 70) and target_dashboard and vis1_valid and vis2_valid
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }