#!/usr/bin/env python3
"""
Verifier for airport_network_resilience task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_airport_network_resilience(traj, env_info, task_info):
    """
    Verify the airport network analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result JSON
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    files = result.get("files", {})
    analysis = result.get("analysis", {})
    
    score = 0
    feedback = []

    # ----------------------------------------------------------------
    # Criterion 1: Centrality Analysis (25 pts)
    # ----------------------------------------------------------------
    c_file = files.get("centrality", {})
    if c_file.get("exists") and c_file.get("new"):
        score += 5
        feedback.append("Centrality CSV created (+5)")
        
        # Check Content
        if analysis.get("centrality_rows", 0) >= 30:
            score += 5
            feedback.append("Centrality CSV has sufficient rows (+5)")
        else:
            feedback.append(f"Centrality CSV incomplete ({analysis.get('centrality_rows')} rows)")

        # Check ATL rank (Ground Truth: ATL is busiest/most central)
        atl_rank = analysis.get("atl_rank", -1)
        if 1 <= atl_rank <= 5:
            score += 10
            feedback.append(f"ATL identified as top hub (Rank {atl_rank}) (+10)")
        elif atl_rank > 0:
            score += 5
            feedback.append(f"ATL found but not top 5 (Rank {atl_rank}) (+5)")
        else:
            feedback.append("ATL not found in top 30 centrality list (0)")
            
        # Check columns
        cols = analysis.get("centrality_cols") or []
        required = ["betweenness", "degree"] # partial match acceptable
        if any("between" in c.lower() for c in cols):
             score += 5
             feedback.append("Betweenness column present (+5)")
    else:
        feedback.append("Centrality CSV missing or old (0)")

    # ----------------------------------------------------------------
    # Criterion 2: Community Detection (20 pts)
    # ----------------------------------------------------------------
    m_file = files.get("communities", {})
    if m_file.get("exists") and m_file.get("new"):
        score += 5
        feedback.append("Community CSV created (+5)")
        
        # Check coverage
        rows = analysis.get("community_rows", 0)
        if rows > 700: # USairports has ~755 nodes
            score += 10
            feedback.append(f"Communities cover all airports ({rows} nodes) (+10)")
        elif rows > 100:
            score += 5
            feedback.append("Communities cover subset of airports (+5)")
            
        # Check modularity (should have multiple communities)
        count = analysis.get("community_count", 0)
        if 3 <= count <= 100:
            score += 5
            feedback.append(f"Reasonable community count ({count}) (+5)")
    else:
        feedback.append("Community CSV missing (0)")

    # ----------------------------------------------------------------
    # Criterion 3: Resilience Simulation (25 pts)
    # ----------------------------------------------------------------
    r_file = files.get("resilience", {})
    if r_file.get("exists") and r_file.get("new"):
        score += 5
        feedback.append("Resilience CSV created (+5)")
        
        # Check steps
        rows = analysis.get("resilience_rows", 0)
        if rows == 11: # 0 to 10
            score += 10
            feedback.append("Simulation has exactly 11 steps (+10)")
        elif rows > 5:
            score += 5
            feedback.append("Simulation has partial steps (+5)")
            
        # Check trend
        trend = analysis.get("resilience_trend", "none")
        if trend == "decreasing":
            score += 10
            feedback.append("Network connectivity decreases as expected (+10)")
        else:
            feedback.append(f"Unexpected resilience trend: {trend} (0)")
    else:
        feedback.append("Resilience CSV missing (0)")

    # ----------------------------------------------------------------
    # Criterion 4: Visualization (20 pts)
    # ----------------------------------------------------------------
    p_file = files.get("network_plot", {})
    if p_file.get("exists") and p_file.get("new"):
        size_kb = p_file.get("size", 0) / 1024
        if size_kb > 50:
            score += 20
            feedback.append(f"Network visualization created ({int(size_kb)}KB) (+20)")
        elif size_kb > 0:
            score += 10
            feedback.append("Network visualization file exists but is small (+10)")
    else:
        feedback.append("Network visualization missing (0)")

    # ----------------------------------------------------------------
    # Criterion 5: Script (10 pts)
    # ----------------------------------------------------------------
    s_file = files.get("script", {})
    if s_file.get("new") and analysis.get("script_content_check"):
        score += 10
        feedback.append("R script modified and contains igraph code (+10)")
    elif s_file.get("new"):
        score += 5
        feedback.append("R script modified but content check failed (+5)")
    else:
        feedback.append("R script not modified (0)")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }