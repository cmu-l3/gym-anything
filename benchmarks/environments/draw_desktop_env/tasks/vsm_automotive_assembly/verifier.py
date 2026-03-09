#!/usr/bin/env python3
import json
import os
import sys

def verify_vsm_automotive_assembly(traj, env_info, task_info):
    """
    Verifies the VSM Automotive Assembly task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    # 1. Load result from container
    local_result_path = "task_result.json"
    try:
        copy_from_env("/tmp/task_result.json", local_result_path)
        with open(local_result_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(local_result_path):
            os.remove(local_result_path)

    # 2. Scoring Logic
    score = 0
    feedback = []

    # A. File Existence (Critical)
    if not result.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "VSM file (acme_vsm.drawio) not found."}
    
    if not result.get("file_modified"):
        feedback.append("Warning: File was not modified during the task.")
    else:
        score += 10 # Created file

    if result.get("png_exists"):
        score += 10 # Exported PNG
    else:
        feedback.append("PNG export missing.")

    # B. Content Analysis
    analysis = result.get("analysis", {})
    entities = analysis.get("entities", {})
    metrics = analysis.get("found_metrics", {})
    
    # B1. Entities (Supplier, Customer, Processes)
    if entities.get("supplier"): score += 5
    if entities.get("customer"): score += 5
    
    # Processes (max 15 pts)
    # Expecting Stamping, Welding, Assembly. Roughly 5 pts each.
    # The heuristic in export script counts matched keywords.
    proc_count = entities.get("processes", 0)
    if proc_count >= 3:
        score += 15
        feedback.append("All major process steps found.")
    elif proc_count > 0:
        score += 5 * proc_count
        feedback.append(f"Found {proc_count}/3 major process groups.")
    else:
        feedback.append("No process step names found.")

    # B2. Metrics Data (max 20 pts)
    # Cycle times
    ct_count = metrics.get("cycle_times", 0)
    if ct_count >= 4:
        score += 10
        feedback.append("Cycle times correct.")
    elif ct_count > 0:
        score += 5
        feedback.append("Some cycle times missing.")
        
    # Inventories
    inv_count = metrics.get("inventories", 0)
    if inv_count >= 4:
        score += 10
        feedback.append("Inventory counts correct.")
    elif inv_count > 0:
        score += 5
        feedback.append("Some inventory counts missing.")

    # B3. Calculations (Lead Time & Processing Time) (max 20 pts)
    if metrics.get("lead_time_calc"):
        score += 10
        feedback.append("Total Lead Time (23.6) found.")
    else:
        feedback.append("Total Lead Time calculation missing or incorrect (expected ~23.6).")

    if metrics.get("processing_time_calc"):
        score += 10
        feedback.append("Total Processing Time (187) found.")
    else:
        feedback.append("Total Processing Time calculation missing (expected 187).")

    # B4. VSM Structure (Shapes/Edges) (max 15 pts)
    shapes = analysis.get("shapes_count", 0)
    edges = analysis.get("edges_count", 0)
    
    if shapes >= 10 and edges >= 5:
        score += 15
        feedback.append(f"Diagram complexity good ({shapes} shapes, {edges} edges).")
    elif shapes >= 5:
        score += 5
        feedback.append("Diagram too simple.")
    
    # 3. Final Determination
    # Pass threshold: 60/100
    # Must have file, basic entities, and at least one calc or good data coverage
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }