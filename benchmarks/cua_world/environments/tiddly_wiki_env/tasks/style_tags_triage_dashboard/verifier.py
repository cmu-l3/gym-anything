#!/usr/bin/env python3
"""Verifier for style_tags_triage_dashboard task."""

import json
import tempfile
import os
import re

def verify_style_tags_dashboard(traj, env_info, task_info):
    """Verify that tags were styled correctly and the dashboard was created with filters."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result from container
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

    # 1. Bug Tag Styling (15 pts)
    bug = result.get("bug", {})
    if bug.get("exists"):
        pts = 0
        if bug.get("color", "").lower() == "#d73a4a":
            pts += 7.5
        if bug.get("icon", "") == "$:/core/images/warning":
            pts += 7.5
        score += pts
        if pts == 15:
            feedback_parts.append("Bug tag fully styled")
        elif pts > 0:
            feedback_parts.append("Bug tag partially styled")
        else:
            feedback_parts.append("Bug tag missing correct styling")
    else:
        feedback_parts.append("FAIL: 'bug' tag tiddler not found")

    # 2. Enhancement Tag Styling (15 pts)
    enh = result.get("enhancement", {})
    if enh.get("exists"):
        pts = 0
        if enh.get("color", "").lower() == "#a2eeef":
            pts += 7.5
        if enh.get("icon", "") == "$:/core/images/star-filled":
            pts += 7.5
        score += pts
        if pts == 15:
            feedback_parts.append("Enhancement tag fully styled")
        elif pts > 0:
            feedback_parts.append("Enhancement tag partially styled")
        else:
            feedback_parts.append("Enhancement tag missing correct styling")
    else:
        feedback_parts.append("FAIL: 'enhancement' tag tiddler not found")

    # 3. Documentation Tag Styling (15 pts)
    doc = result.get("documentation", {})
    if doc.get("exists"):
        pts = 0
        if doc.get("color", "").lower() == "#0075ca":
            pts += 7.5
        if doc.get("icon", "") == "$:/core/images/info-button":
            pts += 7.5
        score += pts
        if pts == 15:
            feedback_parts.append("Documentation tag fully styled")
        elif pts > 0:
            feedback_parts.append("Documentation tag partially styled")
        else:
            feedback_parts.append("Documentation tag missing correct styling")
    else:
        feedback_parts.append("FAIL: 'documentation' tag tiddler not found")

    # Dashboard Verification
    dash = result.get("dashboard", {})
    dash_exists = dash.get("exists", False)
    
    if not dash_exists:
        feedback_parts.append("FAIL: 'Triage Dashboard' tiddler not found")
    else:
        # 4. Dashboard Tab Integration (15 pts)
        if "$:/tags/SideBar" in dash.get("tags", ""):
            score += 15
            feedback_parts.append("Dashboard has SideBar tag")
        else:
            feedback_parts.append("FAIL: Dashboard missing SideBar tag")

        # 5. Dashboard Caption (10 pts)
        if dash.get("caption", "") == "Triage":
            score += 10
            feedback_parts.append("Dashboard caption is correct")
        else:
            feedback_parts.append("FAIL: Dashboard caption incorrect or missing")

        # 6. Dashboard Headers (10 pts)
        h_pts = 0
        if dash.get("has_h_critical"): h_pts += 3.3
        if dash.get("has_h_enhancement"): h_pts += 3.3
        if dash.get("has_h_documentation"): h_pts += 3.4
        score += int(h_pts)
        if h_pts >= 9:
            feedback_parts.append("All headers found")
        else:
            feedback_parts.append("Some/all headers missing")

        # 7. Dashboard Filter Logic (20 pts)
        dash_text = dash.get("text", "")
        # Remove whitespace to easily match filter logic variations
        text_clean = re.sub(r'\s+', '', dash_text)
        
        has_crit_filter = "tag[bug]tag[critical]" in text_clean or "tag[critical]tag[bug]" in text_clean
        has_enh_filter = "tag[enhancement]" in text_clean
        has_doc_filter = "tag[documentation]" in text_clean
        
        f_pts = 0
        if has_crit_filter: f_pts += 8
        if has_enh_filter: f_pts += 6
        if has_doc_filter: f_pts += 6
        score += f_pts
        if f_pts == 20:
            feedback_parts.append("All dashboard filters correctly implemented")
        elif f_pts > 0:
            feedback_parts.append("Filters partially implemented")
        else:
            feedback_parts.append("FAIL: Filter logic missing or incorrect")

    # Evaluate pass/fail
    # Must achieve 70 points AND have at least partially fulfilled dashboard criteria
    passed = score >= 70 and dash_exists

    # Anti-gaming check (informational)
    if not result.get("gui_save_detected", False):
        feedback_parts.append("NOTE: No GUI save logged (possible direct file edit)")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }