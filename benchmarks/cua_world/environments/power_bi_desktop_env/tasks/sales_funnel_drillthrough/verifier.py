#!/usr/bin/env python3
"""
Verifier for sales_funnel_drillthrough task.

Scoring (100 points total):
1. File saved & valid (10 pts)
2. Pages named correctly (10 pts)
3. Funnel visual present (15 pts)
4. Stacked/Clustered Bar chart present (15 pts)
5. Table visual present (10 pts)
6. Card visual present (10 pts)
7. Drill-through configured (10 pts)
8. DAX Measures found (20 pts)

Pass Threshold: 60 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_sales_funnel_drillthrough(traj, env_info, task_info):
    """Verify sales funnel report creation, visuals, and DAX measures."""
    
    # 1. Setup - retrieve result from VM
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    try:
        copy_from_env("C:/Users/Docker/Desktop/sales_funnel_result.json", temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve task result: {e}"}

    try:
        with open(temp_file.name, 'r', encoding='utf-8-sig', errors='replace') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result file corrupted or invalid JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Scoring Logic
    score = 0
    feedback_parts = []
    
    # --- File Existence (10 pts) ---
    if result.get('file_exists') and result.get('file_size_bytes', 0) > 10000:
        score += 10
        feedback_parts.append("File saved successfully.")
    else:
        feedback_parts.append("File missing or empty.")
        # If file missing, fail immediately
        return {"passed": False, "score": 0, "feedback": "Sales_Funnel_Report.pbix not found on Desktop."}

    # --- Page Names (10 pts) ---
    # Expected: "Pipeline Summary" and "Category Drillthrough"
    page_names = [n.lower() for n in result.get('page_names', [])]
    has_summary = any("pipeline" in n for n in page_names)
    has_drill = any("drillthrough" in n or "drill-through" in n for n in page_names)
    
    if has_summary and has_drill:
        score += 10
        feedback_parts.append("Page names correct.")
    elif has_summary or has_drill:
        score += 5
        feedback_parts.append("One page name correct.")
    else:
        feedback_parts.append(f"Page names incorrect (found: {result.get('page_names')}).")

    # --- Visuals Checks (50 pts total) ---
    visuals = [v.lower() for v in result.get('visual_types', [])]
    layout_text = result.get('full_layout_search', '').lower()
    
    # Funnel (15 pts)
    if 'funnel' in visuals or 'funnel' in layout_text:
        score += 15
        feedback_parts.append("Funnel chart found.")
    else:
        feedback_parts.append("Funnel chart missing.")

    # Stacked Bar (15 pts) - accepts clustered or stacked variants
    has_bar = any(x in layout_text for x in ['stackedbar', 'clusteredbar', 'bar']) or \
              any('bar' in v for v in visuals)
    if has_bar:
        score += 15
        feedback_parts.append("Bar chart found.")
    else:
        feedback_parts.append("Bar chart missing.")

    # Table (10 pts)
    has_table = any(x in layout_text for x in ['tableex', 'table']) or 'tableex' in visuals
    if has_table:
        score += 10
        feedback_parts.append("Table visual found.")
    else:
        feedback_parts.append("Table visual missing.")
        
    # Card (10 pts)
    if 'card' in visuals or 'card' in layout_text:
        score += 10
        feedback_parts.append("Card visual found.")
    else:
        feedback_parts.append("Card visual missing.")

    # --- Drill-through Config (10 pts) ---
    # We rely on the heuristic from export_result.ps1
    if result.get('drillthrough_configured'):
        score += 10
        feedback_parts.append("Drill-through configuration detected.")
    else:
        feedback_parts.append("Drill-through configuration NOT detected.")

    # --- DAX Measures (20 pts) ---
    measures = result.get('measures_found', [])
    if "Avg_Order_Value" in measures:
        score += 10
        feedback_parts.append("Measure 'Avg_Order_Value' found.")
    else:
        feedback_parts.append("Measure 'Avg_Order_Value' missing.")
        
    if "Total_Transactions" in measures:
        score += 10
        feedback_parts.append("Measure 'Total_Transactions' found.")
    else:
        feedback_parts.append("Measure 'Total_Transactions' missing.")

    # 3. Final Verification
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }