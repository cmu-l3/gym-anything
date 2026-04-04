#!/usr/bin/env python3
"""
Verifier for Anchor Text Profile Audit task.

Verification Strategy:
1. Programmatic Check (70%):
   - Valid CSV export exists (created during task)
   - CSV contains specific "Anchor" column
   - CSV contains target domain URLs
   - Report file exists with meaningful content
2. VLM Verification (30%):
   - Uses trajectory frames to verify the agent navigated the specific menus
     (Bulk Export > Links > All Inlinks) or performed the analysis steps.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_anchor_text_profile_audit(traj, env_info, task_info):
    """
    Verify the anchor text profile audit task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load programmatic result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: Data Export (40 points) ---
    csv_found = result.get("inlinks_csv_found", False)
    has_anchor = result.get("has_anchor_col", False)
    has_domain = result.get("has_target_domain", False)
    row_count = result.get("row_count", 0)

    if csv_found and has_anchor:
        if row_count >= 50:
            if has_domain:
                score += 40
                feedback_parts.append("Correct Inlinks CSV exported with data (40/40)")
            else:
                score += 30
                feedback_parts.append("Inlinks CSV exported but target domain not confirmed (30/40)")
        elif row_count > 0:
            score += 20
            feedback_parts.append(f"Inlinks CSV exported but insufficient rows ({row_count}) (20/40)")
        else:
            score += 10
            feedback_parts.append("Inlinks CSV exported but empty (10/40)")
    elif result.get("new_csv_count", 0) > 0:
        score += 5
        feedback_parts.append("A CSV was exported, but not identified as Inlinks report (5/40)")
    else:
        feedback_parts.append("No new CSV export found (0/40)")

    # --- Criterion 2: Analysis Report (30 points) ---
    report_exists = result.get("report_exists", False)
    report_size = result.get("report_size_bytes", 0)
    has_keywords = result.get("report_has_keywords", False)
    has_numbers = result.get("report_has_numbers", False)

    if report_exists:
        if report_size >= 400 and has_keywords and has_numbers:
            score += 30
            feedback_parts.append("Comprehensive report written (30/30)")
        elif report_size >= 200:
            score += 20
            feedback_parts.append("Report written but lacks detail/keywords (20/30)")
        else:
            score += 10
            feedback_parts.append("Report file exists but is too short (10/30)")
    else:
        feedback_parts.append("No analysis report found (0/30)")

    # --- Criterion 3: VLM Trajectory Verification (30 points) ---
    # We check if the agent actually used the tool interface
    vlm_score = 0
    
    # Sample frames from the trajectory
    frames = sample_trajectory_frames(traj, n=6)
    
    prompt = """
    Analyze these screenshots of an agent using Screaming Frog SEO Spider.
    The goal was to crawl a site and export "Inlinks" data.
    
    Look for:
    1. A populated crawl list (URLs visible in the main table).
    2. Interaction with the top menu, specifically "Bulk Export".
    3. Interaction with "Links" or "All Inlinks" submenus.
    4. A "Save As" dialog box.
    
    Answer JSON:
    {
        "crawl_data_visible": true/false,
        "export_menu_interaction": true/false,
        "save_dialog_visible": true/false,
        "confidence": "low/medium/high"
    }
    """
    
    try:
        vlm_resp = query_vlm(images=frames, prompt=prompt)
        if vlm_resp.get('success'):
            parsed = vlm_resp.get('parsed', {})
            
            if parsed.get('crawl_data_visible'):
                vlm_score += 10
            if parsed.get('export_menu_interaction') or parsed.get('save_dialog_visible'):
                vlm_score += 20
                
            feedback_parts.append(f"Visual workflow verification ({vlm_score}/30)")
        else:
            # Fallback if VLM fails: check if app was running from programmatic result
            if result.get("sf_running"):
                vlm_score += 15
                feedback_parts.append("VLM failed, fallback to app running check (15/30)")
            else:
                feedback_parts.append("VLM failed and app not running (0/30)")
    except Exception:
         if result.get("sf_running"):
                vlm_score += 15
                feedback_parts.append("VLM error, fallback to app running check (15/30)")

    score += vlm_score

    # Final threshold
    passed = score >= 60 and csv_found and report_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }