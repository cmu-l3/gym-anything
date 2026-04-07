#!/usr/bin/env python3
"""
Verifier for visualize_web_attacks_dashboard.
Checks if the correct dashboard and visualizations were created in OpenSearch Dashboards.
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_visualize_web_attacks_dashboard(traj, env_info, task_info):
    """
    Verify the dashboard creation task.
    
    Steps:
    1. Check if 'Web_Attack_Analysis' dashboard exists.
    2. Check if it has at least 4 panels.
    3. Verify the logic of the 4 required visualizations:
       - Metric: Filter rule.level >= 10, Group 'web'
       - Pie: Terms agg on rule.description
       - Bar: Terms agg on data.srcip
       - Table: Columns data.srcip, data.url
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if 'error' in result:
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    dashboards = result.get('dashboard_objects', [])
    visualizations = result.get('visualization_objects', [])
    
    score = 0
    feedback_parts = []
    
    # 1. Verify Dashboard Existence
    target_dash = None
    for d in dashboards:
        attrs = d.get('attributes', {})
        if attrs.get('title') == 'Web_Attack_Analysis':
            target_dash = d
            break
            
    if target_dash:
        score += 20
        feedback_parts.append("Dashboard 'Web_Attack_Analysis' found.")
    else:
        feedback_parts.append("Dashboard 'Web_Attack_Analysis' NOT found.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 2. Check Dashboard Panels
    # The 'panelsJSON' attribute is a stringified JSON list of panels
    try:
        panels_str = target_dash['attributes'].get('panelsJSON', '[]')
        panels = json.loads(panels_str)
    except:
        panels = []
        
    if len(panels) >= 4:
        score += 10 # Bonus for adding them
        feedback_parts.append(f"Dashboard has {len(panels)} panels.")
    else:
        feedback_parts.append(f"Dashboard has only {len(panels)} panels (expected 4).")

    # 3. Verify Visualization Logic
    # We look for visualizations that match the criteria. They might be linked to the dashboard
    # or just exist in the saved objects. We'll search the exported visualizations list.
    
    # Helpers
    def check_vis_state(vis_state_str, criteria):
        """Parse visState JSON and check criteria"""
        try:
            state = json.loads(vis_state_str)
            
            # Check Aggregations
            aggs = state.get('aggs', [])
            params = state.get('params', {})
            
            # Helper for type check
            if criteria.get('type') and state.get('type') != criteria['type']:
                return False
                
            # Check Aggregation Field (e.g., terms on rule.description)
            if criteria.get('agg_field'):
                found_field = False
                for agg in aggs:
                    if agg.get('schema') in ['metric', 'bucket', 'segment', 'group']:
                        # Depending on vis type, the field might be nested differently
                        # Standard bucket agg:
                        field = agg.get('params', {}).get('field', '')
                        if field == criteria['agg_field'] or field == criteria['agg_field'] + ".keyword":
                            found_field = True
                if not found_field:
                    return False
            
            # Check Columns (for table)
            if criteria.get('columns'):
                # In tables, params.dimensions.columns usually holds this, OR it's just bucket aggs
                # Simplify: check if params string contains the field name
                # This is a bit heuristic because OpenSearch/Kibana structure varies by version
                raw_str = json.dumps(state)
                for col in criteria['columns']:
                    if col not in raw_str:
                        return False

            return True
        except:
            return False

    # Check for search source (filters)
    def check_search_source(search_source_str, criteria):
        """Parse kibanaSavedObjectMeta.searchSourceJSON"""
        try:
            source = json.loads(search_source_str)
            # Check filters
            # Looking for something like: meta: { key: "rule.level", ... params: { gte: 10 } }
            if criteria.get('filter_field'):
                filters = source.get('filter', [])
                # Also check query (query string)
                query = source.get('query', {}).get('query', '')
                
                found_filter = False
                
                # Check explicit filters array
                for f in filters:
                    meta = f.get('meta', {})
                    if meta.get('key') == criteria['filter_field']:
                        # Check value logic if needed
                        found_filter = True
                
                # Check query string (Lucene/KQL)
                # e.g. "rule.level >= 10"
                if criteria['filter_field'] in str(query) and str(criteria.get('filter_value', '')) in str(query):
                    found_filter = True
                    
                return found_filter
            return True # No filter criteria required
        except:
            return False

    # Define Criteria
    reqs = {
        "metric": {"type": "metric", "filter_field": "rule.level", "filter_value": 10, "points": 20},
        "pie": {"type": "pie", "agg_field": "rule.description", "points": 20},
        "bar": {"type": "horizontal_bar", "agg_field": "data.srcip", "points": 20},
        "table": {"type": "table", "columns": ["data.srcip", "data.url"], "points": 10} # 10 pts + 10 for dashboard link
    }
    
    found_reqs = {"metric": False, "pie": False, "bar": False, "table": False}

    for vis in visualizations:
        attrs = vis.get('attributes', {})
        vis_state = attrs.get('visState', '{}')
        search_source = attrs.get('kibanaSavedObjectMeta', {}).get('searchSourceJSON', '{}')
        title = attrs.get('title', '')
        
        # Check Metric
        if not found_reqs['metric']:
            if check_vis_state(vis_state, reqs['metric']):
                # Strict check: must have the high severity filter
                # The filter is often in the searchSource
                if check_search_source(search_source, reqs['metric']):
                    found_reqs['metric'] = True
                    score += reqs['metric']['points']
                    feedback_parts.append(f"Found Metric '{title}' with correct filter.")

        # Check Pie
        if not found_reqs['pie']:
            if check_vis_state(vis_state, reqs['pie']):
                found_reqs['pie'] = True
                score += reqs['pie']['points']
                feedback_parts.append(f"Found Pie Chart '{title}' aggregating rule.description.")

        # Check Bar
        if not found_reqs['bar']:
            if check_vis_state(vis_state, reqs['bar']):
                found_reqs['bar'] = True
                score += reqs['bar']['points']
                feedback_parts.append(f"Found Bar Chart '{title}' aggregating data.srcip.")

        # Check Table
        if not found_reqs['table']:
            # Allow data table or saved search
            # If it's a visualization of type table:
            if check_vis_state(vis_state, reqs['table']):
                found_reqs['table'] = True
                score += reqs['table']['points']
                feedback_parts.append(f"Found Data Table '{title}' with correct columns.")
            # Alternatively, check if it's a Saved Search (type 'search')
            # But the task asked for a Visualization (Data Table). We'll stick to vis type table.

    # Missing items
    for k, v in found_reqs.items():
        if not v:
            feedback_parts.append(f"Missing valid {k} visualization.")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }