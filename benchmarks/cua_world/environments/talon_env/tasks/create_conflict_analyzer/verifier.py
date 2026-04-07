#!/usr/bin/env python3
"""
Verifier for Talon Command Conflict Analyzer task.
Uses multi-signal verification to prevent gaming: File existence, code logic inspection, output parsing, and visual verification.
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_conflict_analyzer(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available."}

    # Extract results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # ---------------------------------------------------------
    # 1. Code Logic Validation (Python Script) - 30 Points Total
    # ---------------------------------------------------------
    analyzer_exists = result.get('analyzer_exists', False)
    code = result.get('analyzer_content', '')
    
    if analyzer_exists:
        score += 5
        feedback_parts.append("Analyzer script exists (+5)")
        
        # Verify it actually parses files (not hardcoded output)
        has_io = any(kw in code for kw in ['open', 'read', 'readlines'])
        has_parsing = any(kw in code for kw in ['split', 'strip', 're.', 'replace', 'endswith'])
        has_logic = any(kw in code for kw in ['==', ' in ', 'set(', 'dict(', 'append', 'duplicate', 'conflict', 'overlap'])
        
        if has_io and has_parsing:
            score += 15
            feedback_parts.append("Script contains file parsing logic (+15)")
        else:
            feedback_parts.append("Script lacks realistic file I/O or parsing logic")
            
        if has_logic:
            score += 10
            feedback_parts.append("Script contains overlap/conflict detection logic (+10)")
    else:
        feedback_parts.append("Analyzer script missing")

    # ---------------------------------------------------------
    # 2. Talon Command Validation - 10 Points Total
    # ---------------------------------------------------------
    talon_exists = result.get('talon_exists', False)
    talon_code = result.get('talon_content', '')
    
    if talon_exists:
        score += 5
        feedback_parts.append("Talon commands file exists (+5)")
        
        # Must have valid talon syntax: A dash (or context match) and a command string `phrase: action`
        has_context_or_dash = "-" in talon_code or re.search(r"^[a-zA-Z\.]+:", talon_code, re.MULTILINE)
        has_command = re.search(r"^[a-zA-Z\s]+:\s*(.+)$", talon_code, re.MULTILINE)
        
        if has_context_or_dash and has_command:
            score += 5
            feedback_parts.append("Talon file has valid syntax (+5)")
    else:
        feedback_parts.append("Talon commands file missing")

    # ---------------------------------------------------------
    # 3. Report Output Validation - 54 Points Total
    # ---------------------------------------------------------
    report_exists = result.get('report_exists', False)
    report_created = result.get('report_created_during_task', False)
    report_text = result.get('report_content', '').lower()
    
    if report_exists and report_created:
        score += 5
        feedback_parts.append("Fresh conflict report generated (+5)")
        
        # Conflict 1: "go back" across browser_general and web_browsing
        if "go back" in report_text and "web_browsing" in report_text and "browser_general" in report_text:
            score += 11
            feedback_parts.append("Detected 'go back' overlap (+11)")
            
        # Conflict 2: "save file" across text_editing, code_editing, global_shortcuts
        save_file_refs = sum(1 for f in ["text_editing", "code_editing", "global_shortcuts"] if f in report_text)
        if "save file" in report_text and save_file_refs >= 2:
            score += 11
            feedback_parts.append("Detected 'save file' duplication (+11)")
            
        # Conflict 3: "copy that" duplicate inside global_shortcuts
        if "copy that" in report_text and "global_shortcuts" in report_text:
            score += 11
            feedback_parts.append("Detected 'copy that' same-file duplicate (+11)")
            
        # Conflict 4: "select all" duplicate in text_editing and global_shortcuts
        if "select all" in report_text and "text_editing" in report_text and "global_shortcuts" in report_text:
            score += 11
            feedback_parts.append("Detected 'select all' duplicate (+11)")
            
        # Conflict 5: "find next" across code_editing and text_editing
        if "find next" in report_text and "code_editing" in report_text and "text_editing" in report_text:
            score += 5
            feedback_parts.append("Detected 'find next' overlap (+5)")
            
    elif report_exists and not report_created:
        feedback_parts.append("Report exists but was not created during this task (anti-gaming)")
    else:
        feedback_parts.append("Conflict report missing")

    # ---------------------------------------------------------
    # 4. VLM Verification (Trajectory checking) - 6 Points
    # ---------------------------------------------------------
    # Agent should have used an editor and executed a script
    query_vlm = env_info.get('query_vlm')
    from gym_anything.vlm import sample_trajectory_frames
    
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """You are verifying an AI coding task. The agent had to write a Python script in a text editor/IDE and execute it.
            Look at the screenshots. Can you see evidence of:
            1. The agent using a text editor (like Notepad, VS Code) to write Python code?
            2. The agent executing the script (e.g., in a terminal, PowerShell window, or via Talon)?
            
            Return JSON:
            {"used_editor": true/false, "executed_script": true/false}
            """
            vlm_res = query_vlm(prompt=prompt, images=frames)
            
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('used_editor') and parsed.get('executed_script'):
                    score += 6
                    feedback_parts.append("VLM verified editor usage and script execution (+6)")
                elif parsed.get('used_editor'):
                    score += 3
                    feedback_parts.append("VLM verified editor usage (+3)")

    # ---------------------------------------------------------
    # Final Result
    # ---------------------------------------------------------
    # Pass threshold: 60 points + core file exists
    passed = (score >= 60) and analyzer_exists and (report_exists and report_created)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }