#!/usr/bin/env python3
import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_pinvoke_sysinfo(traj, env_info, task_info):
    """
    Verify the P/Invoke SystemDiagnostic task.
    Requires successful code structure, successful build, and correct execution artifacts.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Fetch result JSON from the Windows environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\temp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    task_start = result.get('task_start', 0)
    computer_name_gt = result.get('computer_name_gt', '').strip().upper()
    program_cs = result.get('program_cs', '')
    build_exit_code = result.get('build_exit_code', -1)
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '')
    report_mtime = result.get('report_mtime', 0)

    # 1. Project Creation Check (10 pts)
    if result.get('project_exists'):
        score += 10
        feedback_parts.append("Project created")
    else:
        feedback_parts.append("Project NOT found")

    # 2. Source Code P/Invoke Declarations (30 pts)
    # Allows "kernel32.dll" or "kernel32"
    has_interop = re.search(r"using\s+System\.Runtime\.InteropServices;", program_cs)
    has_getcomp = re.search(r"GetComputerNameW", program_cs) and re.search(r"DllImport[\(\s]*\"kernel32", program_cs, re.IGNORECASE)
    has_getsys = re.search(r"GetSystemDirectoryW", program_cs) and re.search(r"DllImport[\(\s]*\"kernel32", program_cs, re.IGNORECASE)
    has_getpid = re.search(r"GetCurrentProcessId", program_cs) and re.search(r"DllImport[\(\s]*\"kernel32", program_cs, re.IGNORECASE)
    has_gettick = re.search(r"GetTickCount64", program_cs) and re.search(r"DllImport[\(\s]*\"kernel32", program_cs, re.IGNORECASE)

    if has_interop: score += 5
    if has_getcomp: score += 10
    if has_getsys: score += 10
    if has_getpid: score += 5
    if has_gettick: score += 5

    if has_getcomp and has_getsys and has_getpid and has_gettick:
        feedback_parts.append("All P/Invoke definitions found")
    else:
        feedback_parts.append("Missing some or all P/Invoke definitions")

    # 3. Build Check (15 pts) - MUST be 0 to pass task
    build_succeeded = (build_exit_code == 0)
    if build_succeeded:
        score += 15
        feedback_parts.append("Build succeeded")
    else:
        feedback_parts.append(f"Build failed (exit code {build_exit_code})")

    # 4. Report Output Check (max 35 pts)
    report_valid = False
    if report_exists:
        score += 5
        feedback_parts.append("Report file exists")

        # Anti-gaming: Check if file was created after task start
        if report_mtime > task_start:
            score += 5
            feedback_parts.append("Valid timestamp")
        else:
            feedback_parts.append("WARNING: Report file predates task start (possible artifact)")

        # Parse Report Contents
        match_comp = re.search(r"ComputerName:\s*([^\r\n]+)", report_content, re.IGNORECASE)
        match_sys = re.search(r"SystemDirectory:\s*([^\r\n]+)", report_content, re.IGNORECASE)
        match_pid = re.search(r"ProcessId:\s*(\d+)", report_content, re.IGNORECASE)
        match_tick = re.search(r"UptimeMilliseconds:\s*(\d+)", report_content, re.IGNORECASE)

        if match_comp:
            reported_comp = match_comp.group(1).strip().upper()
            if reported_comp and (computer_name_gt in reported_comp or reported_comp in computer_name_gt):
                score += 10
                feedback_parts.append("Valid ComputerName")
            else:
                feedback_parts.append(f"ComputerName mismatch ({reported_comp} vs GT {computer_name_gt})")
        
        if match_sys:
            reported_sys = match_sys.group(1).strip().lower()
            if "windows" in reported_sys:
                score += 8
                feedback_parts.append("Valid SystemDirectory")
            else:
                feedback_parts.append("Invalid SystemDirectory format")

        if match_pid:
            reported_pid = int(match_pid.group(1).strip())
            if 0 < reported_pid < 200000:
                score += 7
                feedback_parts.append("Valid ProcessId")
                
        if match_tick:
            reported_uptime = int(match_tick.group(1).strip())
            if reported_uptime > 10000:  # > 10 seconds
                score += 5
                feedback_parts.append("Valid Uptime")

        if match_comp and match_sys and match_pid and match_tick:
            report_valid = True
    else:
        feedback_parts.append("Report file NOT found")

    # Final Pass Logic: Score >= 60 AND Build Succeeded AND File Exists
    passed = (score >= 60) and build_succeeded and report_exists

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }