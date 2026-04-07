#!/usr/bin/env python3
"""
Verifier for temporal_bucketing_ops_review task.

Scoring (100 pts, pass >= 60):
  10 pts  Dashboard 'Operations Review Buckets' exists
  10 pts  Dashboard has >= 3 graphs
  10 pts  Graph 'Hourly CPU Average' found
  10 pts  Graph 1 uses summarize() with correct metric and "1h" interval
   5 pts  Graph 1 uses "avg" aggregation
  10 pts  Graph 'Daily Temperature Peaks' found
  10 pts  Graph 2 uses smartSummarize() with correct metric and "1d" interval
   5 pts  Graph 2 uses "max" aggregation
  10 pts  Graph '6-Hour Network Volume' found
  10 pts  Graph 3 uses summarize() with correct metric and "6h" interval
  10 pts  Graph 3 uses "sum" aggregation
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DASHBOARD_NAME = "Operations Review Buckets"
RESULT_PATH = "/tmp/temporal_bucketing_ops_review_result.json"


def _get_graphs(dashboard_state):
    """Return list of (title, targets_list) from dashboard state dict."""
    graphs = []
    raw_graphs = dashboard_state.get("graphs", [])
    for entry in raw_graphs:
        if not isinstance(entry, (list, tuple)) or len(entry) < 2:
            continue
        params = entry[1] if isinstance(entry[1], dict) else {}
        title = params.get("title", "")
        targets = params.get("target", [])
        if isinstance(targets, str):
            targets = [targets]
        graphs.append((title, [str(t) for t in targets]))
    return graphs


def _find_graph(graphs, expected_title):
    """Find a graph by exact title, then case-insensitive. Returns (title, targets) or None."""
    for title, targets in graphs:
        if title == expected_title:
            return title, targets
    for title, targets in graphs:
        if expected_title.lower() in title.lower():
            return title, targets
    return None


def verify_temporal_bucketing(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}
    
    score = 0
    feedback_parts = []
    
    # --- Load result file ---
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        copy_from_env(RESULT_PATH, tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not load result file: {e}"}

    dashboards = result.get("dashboards", {})
    
    # --- Check Dashboard ---
    if DASHBOARD_NAME not in dashboards:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Dashboard '{DASHBOARD_NAME}' not found. Present: {list(dashboards.keys())}"
        }
    
    score += 10
    feedback_parts.append(f"Dashboard '{DASHBOARD_NAME}' exists")
    
    dashboard_state = dashboards[DASHBOARD_NAME]
    if "parse_error" in dashboard_state:
        return {"passed": False, "score": score, "feedback": f"Dashboard JSON parse error: {dashboard_state['parse_error']}"}

    graphs = _get_graphs(dashboard_state)
    
    if len(graphs) >= 3:
        score += 10
        feedback_parts.append(f"Dashboard has {len(graphs)} graphs")
    else:
        feedback_parts.append(f"Dashboard has {len(graphs)} graphs (expected >= 3)")
        
    # --- Check Graph 1: Hourly CPU Average ---
    g1_match = _find_graph(graphs, "Hourly CPU Average")
    if g1_match:
        score += 10
        title, targets = g1_match
        feedback_parts.append("Graph 'Hourly CPU Average' found")
        
        # Normalize target string to remove spaces and convert single quotes to double quotes for consistent checking
        target_str = "".join(targets).lower().replace(" ", "").replace("'", '"')
        
        if "summarize(" in target_str and "smartsummarize(" not in target_str and "ec2_instance_1.cpu.utilization" in target_str and '"1h"' in target_str:
            score += 10
            feedback_parts.append("Graph 1 uses correct summarize(), metric, and 1h bucket")
        else:
            feedback_parts.append("Graph 1 missing correct summarize(), metric, or 1h bucket")
            
        if '"avg"' in target_str or '"average"' in target_str:
            score += 5
            feedback_parts.append("Graph 1 uses correct avg aggregation")
        else:
            feedback_parts.append("Graph 1 missing avg aggregation")
    else:
        feedback_parts.append("Graph 'Hourly CPU Average' NOT found")

    # --- Check Graph 2: Daily Temperature Peaks ---
    g2_match = _find_graph(graphs, "Daily Temperature Peaks")
    if g2_match:
        score += 10
        title, targets = g2_match
        feedback_parts.append("Graph 'Daily Temperature Peaks' found")
        
        target_str = "".join(targets).lower().replace(" ", "").replace("'", '"')
        
        if "smartsummarize(" in target_str and "machine_temperature" in target_str and '"1d"' in target_str:
            score += 10
            feedback_parts.append("Graph 2 uses correct smartSummarize(), metric, and 1d bucket")
        else:
            feedback_parts.append("Graph 2 missing correct smartSummarize(), metric, or 1d bucket")
            
        if '"max"' in target_str:
            score += 5
            feedback_parts.append("Graph 2 uses correct max aggregation")
        else:
            feedback_parts.append("Graph 2 missing max aggregation")
    else:
        feedback_parts.append("Graph 'Daily Temperature Peaks' NOT found")

    # --- Check Graph 3: 6-Hour Network Volume ---
    g3_match = _find_graph(graphs, "6-Hour Network Volume")
    if g3_match:
        score += 10
        title, targets = g3_match
        feedback_parts.append("Graph '6-Hour Network Volume' found")
        
        target_str = "".join(targets).lower().replace(" ", "").replace("'", '"')
        
        if "summarize(" in target_str and "network.bytes_in" in target_str and '"6h"' in target_str:
            score += 10
            feedback_parts.append("Graph 3 uses correct summarize(), metric, and 6h bucket")
        else:
            feedback_parts.append("Graph 3 missing correct summarize(), metric, or 6h bucket")
            
        if '"sum"' in target_str:
            score += 10
            feedback_parts.append("Graph 3 uses correct sum aggregation")
        else:
            feedback_parts.append("Graph 3 missing sum aggregation")
    else:
        feedback_parts.append("Graph '6-Hour Network Volume' NOT found")

    passed = score >= 60
    return {"passed": passed, "score": score, "feedback": " | ".join(feedback_parts)}