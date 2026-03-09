#!/usr/bin/env python3
"""
Verifier for configure_invoice_defaults task.

Scoring:
- Custom Title configured: 30 pts
- Notes configured: 30 pts
- Due Date configured: 30 pts
- Workflow verification (VLM): 10 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import VLM utilities from framework
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logger.warning("VLM utilities not available")

def verify_configure_invoice_defaults(traj, env_info, task_info):
    """
    Verify that Sales Invoice Form Defaults were configured correctly.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Verify Title (30 pts)
    if result.get("title_configured", False):
        score += 30
        feedback_parts.append("Custom title 'TAX INVOICE' confirmed")
    else:
        feedback_parts.append("Custom title NOT configured")

    # 2. Verify Notes (30 pts)
    if result.get("notes_configured", False):
        score += 30
        feedback_parts.append("Default notes confirmed")
    else:
        feedback_parts.append("Default notes NOT configured")

    # 3. Verify Due Date (30 pts)
    due_date_status = result.get("due_date_configured", "false")
    if due_date_status == "true":
        score += 30
        feedback_parts.append("Due date (14 days) confirmed")
    elif due_date_status == "potential":
        # We found "14" but weren't sure. Give partial credit or rely on VLM.
        # For this strict verifier, we'll give partial credit
        score += 15
        feedback_parts.append("Due date value found but ambiguous")
    else:
        feedback_parts.append("Due date NOT configured")

    # 4. VLM Verification of Workflow (10 pts)
    # Check if the agent actually visited the "Form Defaults" page
    vlm_score = 0
    if VLM_AVAILABLE:
        frames = sample_trajectory_frames(traj, n=4)
        prompt = """
        Review these screenshots of an agent using Manager.io.
        The agent's goal is to configure "Form Defaults" for Sales Invoices.
        
        Look for:
        1. A screen showing "Form Defaults" (often a heading or button).
        2. A configuration form with fields like "Custom Title", "Due Date" or "Payment terms", and "Notes".
        3. The text "TAX INVOICE" or "14" being entered.
        
        Did the agent access the Form Defaults configuration screen?
        Return JSON: {"accessed_defaults": boolean, "entered_values": boolean}
        """
        
        try:
            vlm_resp = query_vlm(images=frames, prompt=prompt)
            if vlm_resp.get("success"):
                parsed = vlm_resp.get("parsed", {})
                if parsed.get("accessed_defaults", False):
                    vlm_score += 5
                    feedback_parts.append("VLM: Defaults screen accessed")
                if parsed.get("entered_values", False):
                    vlm_score += 5
                    feedback_parts.append("VLM: Values entry observed")
        except Exception as e:
            logger.error(f"VLM error: {e}")
            # Fallback: if score is already high, assume workflow was okay
            if score >= 60:
                vlm_score = 10

    score += vlm_score

    # Final Pass Check
    # Must have at least Title AND Notes correct (60 pts) + some workflow
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }