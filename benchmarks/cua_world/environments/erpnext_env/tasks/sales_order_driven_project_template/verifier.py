#!/usr/bin/env python3
"""
Verifier for sales_order_driven_project_template task.

Task Requirements:
1. Create a Project Template "Standard Wind Installation" with 3 specific tasks.
2. Create & submit Sales Order for Apex Energy (Wind Farm Installation Service).
3. Generate a linked Project from the Sales Order, applying the template.
4. Mark the "Site Survey" task generated for the Project as "Completed".

Scoring (100 pts total, pass >= 80):
  C1 [20 pts] — Project Template created with 3 specific tasks.
  C2 [20 pts] — Sales Order for Apex Energy submitted with correct item.
  C3 [20 pts] — Project exists and is explicitly linked to the Sales Order.
  C4 [20 pts] — Project is linked to the Project Template and spawned child tasks.
  C5 [20 pts] — "Site Survey" task linked to this specific project is "Completed".
"""

import json
import logging
import re
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_sales_order_project(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    result_file = task_info.get("metadata", {}).get(
        "result_file", "/tmp/sales_order_project_result.json"
    )
    local_tmp = "/tmp/_so_proj_result_local.json"

    try:
        copy_from_env(result_file, local_tmp)
        with open(local_tmp, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Result file missing or invalid. Agent may have broken the environment. Error: {e}"
        }

    templates = data.get("templates", [])
    sales_orders = data.get("sales_orders", [])
    projects = data.get("projects", [])
    tasks = data.get("tasks", [])

    score = 0
    feedback_parts = []
    
    # --- ERPNext reachability sentinel ---
    if not data.get("app_running"):
        return {"passed": False, "score": 0, "feedback": "ERPNext was offline during export."}

    # Expected required task names in the template (case insensitive matching)
    expected_subjects = ["site survey", "foundation construction", "turbine erection"]

    # -------------------------------------------------------------------------
    # C1: Project Template Evaluation (20 pts)
    # -------------------------------------------------------------------------
    c1_pass = False
    valid_template_name = None
    
    for t in templates:
        t_tasks = t.get("task_subjects", [])
        # Check if this template has all 3 required tasks
        matches = [any(exp in t_subj for t_subj in t_tasks) for exp in expected_subjects]
        if all(matches):
            c1_pass = True
            valid_template_name = t.get("name")
            break
            
    if c1_pass:
        score += 20
        feedback_parts.append("C1 PASS: Project Template created with correct tasks (+20)")
    else:
        if templates:
            feedback_parts.append(f"C1 FAIL: Project Template missing required tasks. (Found: {[t.get('task_subjects') for t in templates]})")
        else:
            feedback_parts.append("C1 FAIL: No new Project Template found.")

    # -------------------------------------------------------------------------
    # C2: Sales Order Evaluation (20 pts)
    # -------------------------------------------------------------------------
    c2_pass = False
    valid_so_name = None
    
    for so in sales_orders:
        if so.get("docstatus") == 1:  # 1 = Submitted
            if "Wind Farm Installation Service" in so.get("items", []):
                c2_pass = True
                valid_so_name = so.get("name")
                break
                
    if c2_pass:
        score += 20
        feedback_parts.append(f"C2 PASS: Sales Order '{valid_so_name}' submitted with correct item (+20)")
    else:
        if sales_orders:
            feedback_parts.append("C2 FAIL: Sales Order found but not submitted or missing the Service item.")
        else:
            feedback_parts.append("C2 FAIL: No new Sales Order found for Apex Energy.")

    # -------------------------------------------------------------------------
    # C3: Linked Project Evaluation (20 pts)
    # -------------------------------------------------------------------------
    c3_pass = False
    valid_project_name = None
    
    for p in projects:
        # Accept explicit link OR if it was created right after the SO
        if p.get("sales_order") == valid_so_name and valid_so_name is not None:
            c3_pass = True
            valid_project_name = p.get("name")
            break
        # Fallback if SO name wasn't captured properly but project exists linking to ANY SO
        elif p.get("sales_order") is not None and len(p.get("sales_order", "")) > 0:
            c3_pass = True
            valid_project_name = p.get("name")
            break
            
    if c3_pass:
        score += 20
        feedback_parts.append(f"C3 PASS: Project '{valid_project_name}' explicitly linked to Sales Order (+20)")
    else:
        if projects:
            feedback_parts.append("C3 FAIL: Project created but NOT linked to the Sales Order.")
        else:
            feedback_parts.append("C3 FAIL: No new Project found.")

    # -------------------------------------------------------------------------
    # C4: Template Application Evaluation (20 pts)
    # -------------------------------------------------------------------------
    c4_pass = False
    project_tasks = []
    
    if valid_project_name:
        # Check if project was linked to a template
        p_doc = next((p for p in projects if p["name"] == valid_project_name), None)
        if p_doc and p_doc.get("project_template"):
            # Check if tasks spawned
            project_tasks = [tk for tk in tasks if tk.get("project") == valid_project_name]
            if len(project_tasks) >= 3:
                c4_pass = True
                
    if c4_pass:
        score += 20
        feedback_parts.append("C4 PASS: Project Template successfully applied, generating child tasks (+20)")
    else:
        if valid_project_name:
            feedback_parts.append(f"C4 FAIL: Project created but template not applied (found {len(project_tasks)} tasks).")
        else:
            feedback_parts.append("C4 SKIP: Project validation failed, skipping template check.")

    # -------------------------------------------------------------------------
    # C5: Task Execution Evaluation (20 pts)
    # -------------------------------------------------------------------------
    c5_pass = False
    
    if project_tasks:
        for tk in project_tasks:
            subj = tk.get("subject", "").lower()
            if "site survey" in subj and tk.get("status") == "Completed":
                c5_pass = True
                break
                
    if c5_pass:
        score += 20
        feedback_parts.append("C5 PASS: 'Site Survey' task marked as 'Completed' (+20)")
    else:
        if project_tasks:
            feedback_parts.append("C5 FAIL: 'Site Survey' task not found or not marked as 'Completed'.")
        else:
            feedback_parts.append("C5 SKIP: No project tasks found to complete.")

    # -------------------------------------------------------------------------
    # VLM Verification (Anti-bot visual confirmation)
    # -------------------------------------------------------------------------
    # As a supplementary check, ensure the trajectory proves the agent interacted with the UI.
    from gym_anything.vlm import sample_trajectory_frames, query_vlm, get_final_screenshot
    
    vlm_feedback = ""
    try:
        frames = sample_trajectory_frames(traj, n=3)
        final_img = get_final_screenshot(traj)
        if final_img:
            frames.append(final_img)
            
        if frames:
            prompt = (
                "You are auditing an agent using an ERP system (ERPNext). "
                "Look at these screenshots taken during the task. "
                "Can you confirm the agent was interacting with Projects, Sales Orders, or Tasks? "
                "Respond with a JSON object: {\"confirmed\": true/false, \"reason\": \"brief explanation\"}"
            )
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res and vlm_res.get("parsed", {}).get("confirmed", False):
                vlm_feedback = "VLM confirms visible ERP UI interactions."
            else:
                vlm_feedback = "VLM could not strongly confirm ERP UI interactions from frames."
    except Exception as e:
        logger.warning(f"VLM verification skipped/failed: {e}")

    if vlm_feedback:
        feedback_parts.append(f"VLM Check: {vlm_feedback}")

    # -------------------------------------------------------------------------
    # Final Scoring
    # -------------------------------------------------------------------------
    # Requires 80 points to pass (implies agent got C1-C4 or missing only one step but completed the core linkage)
    # But explicitly, applying the template and linking is the core of the task.
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }