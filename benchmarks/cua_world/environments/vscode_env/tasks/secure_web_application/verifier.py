#!/usr/bin/env python3
"""
Verifier for the secure_web_application task.

Verifies remediation of 6 critical/high vulnerabilities in an Express application.
Uses AST/Regex-based checks on the modified source files.

Scoring Breakdown (100 total, 60 to pass):
- V1: SQL Injection (15 pts)
- V2: Stored XSS (15 pts)
- V3: Path Traversal (15 pts)
- V4: Plaintext Passwords (15 pts)
- V5: Insecure Session (10 pts)
- V6: Missing Input Validation (10 pts)
- Syntax Validity & Real Edits (10 pts)
- VLM Trajectory Verification (10 pts)
"""

import sys
import os
import json
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_security_remediation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve exported JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/security_remediation_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            export_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load exported data: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    files = export_data.get("files", {})
    syntax_checks = export_data.get("syntax_checks", {})
    mtime_checks = export_data.get("mtime_checks", {})
    
    score = 0
    feedback_parts = []
    
    # Check if files were actually modified during task
    modified_files = [path for path, data in mtime_checks.items() if data.get("modified_during_task")]
    if not modified_files:
        return {"passed": False, "score": 0, "feedback": "No files were modified during the task."}

    # -------------------------------------------------------------------------
    # SYNTAX CHECK (10 pts)
    # -------------------------------------------------------------------------
    invalid_files = [path for path, data in syntax_checks.items() if not data.get("valid")]
    if invalid_files:
        feedback_parts.append(f"Syntax errors in: {', '.join(invalid_files)}")
    else:
        score += 10
        feedback_parts.append("All JS files have valid syntax (+10)")

    # -------------------------------------------------------------------------
    # V1: SQL Injection (15 pts)
    # -------------------------------------------------------------------------
    auth_js = files.get("routes/auth.js", "")
    if auth_js:
        # Check that we are no longer concatenating req.body inside SQL strings
        bad_concat = re.search(r"['\"]\s*\+\s*req\.body\.(username|password)|req\.body\.(username|password)\s*\+\s*['\"]", auth_js)
        # Check for presence of parameterization (VALUES (?, ?) or username = ?)
        good_params = re.search(r"VALUES\s*\(\s*\?|\s*=\s*\?", auth_js)
        
        if good_params and not bad_concat:
            score += 15
            feedback_parts.append("V1 SQLi Fixed (+15)")
        else:
            feedback_parts.append("V1 SQLi Not Fixed")
    else:
        feedback_parts.append("V1 SQLi Not Fixed (file missing)")

    # -------------------------------------------------------------------------
    # V2: Stored XSS (15 pts)
    # -------------------------------------------------------------------------
    notes_ejs = files.get("views/notes.ejs", "")
    if notes_ejs:
        still_unescaped = re.search(r"<%-\s*note\.content\s*%>", notes_ejs)
        escaped = re.search(r"<%=\s*note\.content\s*%>", notes_ejs)
        
        if escaped and not still_unescaped:
            score += 15
            feedback_parts.append("V2 Stored XSS Fixed (+15)")
        else:
            feedback_parts.append("V2 Stored XSS Not Fixed")
    else:
        feedback_parts.append("V2 Stored XSS Not Fixed (file missing)")

    # -------------------------------------------------------------------------
    # V3: Path Traversal (15 pts)
    # -------------------------------------------------------------------------
    files_js = files.get("routes/files.js", "")
    if files_js:
        # Looking for path.resolve / path.normalize AND a boundary check
        has_resolve = re.search(r"path\.(resolve|normalize)", files_js)
        has_boundary_check = re.search(r"startsWith\s*\(\s*uploadsDir\s*\)|indexOf\s*\(\s*['\"]\0['\"]\s*\)|includes\s*\(\s*['\"]\.\.['\"]\s*\)", files_js)
        
        if has_resolve and has_boundary_check:
            score += 15
            feedback_parts.append("V3 Path Traversal Fixed (+15)")
        else:
            feedback_parts.append("V3 Path Traversal Not Fixed")
    else:
        feedback_parts.append("V3 Path Traversal Not Fixed (file missing)")

    # -------------------------------------------------------------------------
    # V4: Plaintext Passwords (15 pts)
    # -------------------------------------------------------------------------
    if auth_js:
        has_bcrypt = re.search(r"bcrypt|argon2", auth_js)
        has_hash = re.search(r"\.hash", auth_js)
        has_compare = re.search(r"\.compare", auth_js)
        
        if has_bcrypt and has_hash and has_compare:
            score += 15
            feedback_parts.append("V4 Password Hashing Fixed (+15)")
        else:
            feedback_parts.append("V4 Password Hashing Not Fixed")
    else:
        feedback_parts.append("V4 Password Hashing Not Fixed")

    # -------------------------------------------------------------------------
    # V5: Insecure Session (10 pts)
    # -------------------------------------------------------------------------
    app_js = files.get("app.js", "")
    if app_js:
        has_httpOnly = re.search(r"httpOnly\s*:\s*true", app_js)
        has_sameSite = re.search(r"sameSite\s*:\s*['\"](?:strict|lax)['\"]", app_js)
        
        if has_httpOnly and has_sameSite:
            score += 10
            feedback_parts.append("V5 Secure Session Fixed (+10)")
        else:
            feedback_parts.append("V5 Secure Session Not Fixed")
    else:
        feedback_parts.append("V5 Secure Session Not Fixed (file missing)")

    # -------------------------------------------------------------------------
    # V6: Missing Input Validation (10 pts)
    # -------------------------------------------------------------------------
    api_js = files.get("routes/api.js", "")
    if api_js:
        # Looking for manual checks (typeof, length, if (!title)) or validation libs
        has_checks = re.search(r"typeof\s+(title|content)|(title|content)\.length|if\s*\(\s*!(title|content)\s*\)", api_js)
        has_lib = re.search(r"express-validator|validator|joi|zod", api_js)
        
        if has_checks or has_lib:
            score += 10
            feedback_parts.append("V6 Input Validation Fixed (+10)")
        else:
            feedback_parts.append("V6 Input Validation Not Fixed")
    else:
        feedback_parts.append("V6 Input Validation Not Fixed (file missing)")

    # -------------------------------------------------------------------------
    # VLM Trajectory Verification (10 pts)
    # -------------------------------------------------------------------------
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = (
                "You are auditing an agent's trajectory for a security remediation task. "
                "Look at these screenshots. Does it show the VS Code editor open with JavaScript code or Markdown? "
                "Is there visual evidence that the agent actually edited code? "
                "Respond in JSON format: {'agent_edited_code': true/false}"
            )
            vlm_response = query_vlm(images=frames, prompt=prompt)
            if vlm_response.get('success'):
                parsed = vlm_response.get('parsed', {})
                if parsed.get('agent_edited_code', False):
                    score += 10
                    feedback_parts.append("VLM confirms agent edited code (+10)")
                else:
                    feedback_parts.append("VLM did not detect active code editing")
            else:
                feedback_parts.append("VLM query failed, ignoring trajectory check")
    else:
        # If VLM is completely disabled, award points to prevent penalty
        score += 10
        feedback_parts.append("VLM not available (auto +10)")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }