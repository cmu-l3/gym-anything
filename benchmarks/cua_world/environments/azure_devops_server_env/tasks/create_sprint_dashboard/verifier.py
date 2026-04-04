#!/usr/bin/env python3
"""
Verifier for Create Sprint Review Dashboard task.

SCORING CRITERIA:
1. Dashboard 'Sprint 1 Review' exists (15 pts)
2. At least 4 widgets present (15 pts)
3. Markdown widget contains required text (20 pts)
4. Query Tile widget bound to 'Active Bugs' (20 pts)
5. Chart widget bound to 'Sprint 1 All Items' (20 pts)
6. At least one additional widget (10 pts)

Pass Threshold: 60 points
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_sprint_dashboard(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Retrieve result file
    tmp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp_file.close()
    
    try:
        # Try Windows path first (as used in export script)
        # Note: Framework might map this to a local path or require specific handling
        # Assuming copy_from_env handles the container path mapping
        copy_from_env("C:/Users/Docker/task_results/create_sprint_dashboard_result.json", tmp_file.name)
        
        with open(tmp_file.name, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Could not retrieve verification results. Ensure export_result.ps1 ran successfully. Error: {e}"
        }
    finally:
        if os.path.exists(tmp_file.name):
            os.unlink(tmp_file.name)

    score = 0
    feedback = []

    # 1. Dashboard Exists
    if result.get("dashboard_exists"):
        score += 15
        feedback.append("Dashboard 'Sprint 1 Review' found.")
    else:
        return {"passed": False, "score": 0, "feedback": "Dashboard 'Sprint 1 Review' was not found."}

    # 2. Widget Count
    w_count = result.get("widget_count", 0)
    if w_count >= 4:
        score += 15
        feedback.append(f"Widget count acceptable ({w_count}).")
    else:
        feedback.append(f"Not enough widgets found. Expected >= 4, found {w_count}.")

    # Analyze Widgets
    widgets = result.get("widgets", [])
    active_bugs_id = result.get("active_bugs_query_id", "UNKNOWN")
    sprint1_items_id = result.get("sprint1_items_query_id", "UNKNOWN")
    
    markdown_passed = False
    query_tile_passed = False
    chart_passed = False
    extra_widget_passed = False
    
    required_goals = [
        "product inventory search",
        "fix all priority 1 bugs",
        "80% code coverage"
    ]

    for w in widgets:
        w_type = w.get("type_id", "")
        settings = w.get("settings", {})
        
        # Check Markdown
        if "Microsoft.VisualStudioOnline.Dashboards.MarkdownWidget" in w_type:
            content = settings.get("content", "").lower()
            if all(g in content for g in required_goals):
                markdown_passed = True
        
        # Check Query Tile
        # Type ID usually: Microsoft.VisualStudioOnline.Dashboards.QueryScalarWidget
        elif "QueryScalarWidget" in w_type:
            # Check if queryId or queryName matches
            q_id = settings.get("queryId", "")
            q_name = settings.get("queryName", "")
            if (active_bugs_id and q_id == active_bugs_id) or "Active Bugs" in q_name:
                query_tile_passed = True

        # Check Chart
        # Type ID usually: Microsoft.VisualStudioOnline.Dashboards.ChartWidget
        elif "ChartWidget" in w_type:
            # Check grouping and query
            group_by = settings.get("groupBy", "")
            q_id = settings.get("queryId", "")
            q_name = settings.get("queryName", "")
            
            is_sprint_query = (sprint1_items_id and q_id == sprint1_items_id) or "Sprint 1 All Items" in q_name
            is_state_group = "System.State" in group_by or "State" in group_by
            
            if is_sprint_query and is_state_group:
                chart_passed = True

    # Scoring Specific Widgets
    if markdown_passed:
        score += 20
        feedback.append("Markdown widget configured correctly.")
    else:
        feedback.append("Markdown widget missing or text content incorrect.")

    if query_tile_passed:
        score += 20
        feedback.append("Query Tile configured for 'Active Bugs'.")
    else:
        feedback.append("Query Tile missing or not pointing to 'Active Bugs'.")

    if chart_passed:
        score += 20
        feedback.append("Chart widget configured for Sprint 1 Items by State.")
    else:
        feedback.append("Chart widget missing or configuration incorrect (wrong query or grouping).")

    # Extra Widget (Automatic if count >= 4 and we identified some types, 
    # but strictly checking if there's a 4th widget is implicit in count check logic + existence of others)
    # If they have 4 widgets, and we checked 3 specific ones, the 4th exists.
    # We'll just award the last 10 points if count >= 4.
    if w_count >= 4:
        score += 10
        feedback.append("Additional widget requirement met.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }