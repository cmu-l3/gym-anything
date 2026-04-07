#!/usr/bin/env python3
"""
Verifier for Implement Directory Monitor Service task.

Verification Strategy (Multi-Criteria):
1. NuGet Package Installed (10 pts) - Checks csproj for WindowsServices package.
2. Windows Service Configured (10 pts) - Checks Program.cs for AddWindowsService or UseWindowsService.
3. Build Succeeds (15 pts) - Checks if LogMonitorService.exe exists.
4. File Movement (15 pts) - Checks if hidden test logs were dynamically moved to archive.
5. Accurate Log Parsing (30 pts) - Checks if error_summary.txt contains correct 404/500 counts for hidden logs.
6. VLM Trajectory (20 pts) - Checks if the agent actually used Visual Studio IDE to write the code.
"""

import json
import tempfile
import os
import re
import logging
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating screenshots from an agent taking a coding test in Visual Studio 2022.
The agent was asked to create a C# Worker Service, install a NuGet package, and write code to monitor a directory.

Review these chronological trajectory frames and assess:
1. Did the agent open and use Visual Studio 2022?
2. Is there evidence of writing C# code (e.g., viewing Worker.cs or Program.cs)?
3. Did the agent interact with NuGet Package Manager or the .csproj file to install packages?

Respond STRICTLY in JSON format:
{
    "used_visual_studio": true/false,
    "wrote_code": true/false,
    "managed_nuget": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of what is visible"
}
"""

def _vlm_query(query_vlm, prompt, images):
    if not query_vlm or not images:
        return None
    try:
        res = query_vlm(prompt=prompt, images=images)
        if res.get("success"):
            return res.get("parsed", {})
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
    return None

def verify_monitor_service(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Extract task result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Users\\Docker\\Documents\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    # 1. NuGet Package Check (10 pts)
    csproj = result.get("csproj_content", "") or ""
    if "Microsoft.Extensions.Hosting.WindowsServices" in csproj:
        score += 10
        feedback.append("[✓] NuGet package WindowsServices referenced.")
    else:
        feedback.append("[ ] Missing NuGet package in .csproj.")

    # 2. Windows Service Configuration Check (10 pts)
    program_cs = result.get("program_cs_content", "") or ""
    if "UseWindowsService" in program_cs or "AddWindowsService" in program_cs:
        score += 10
        feedback.append("[✓] Windows Service configured in Program.cs.")
    else:
        feedback.append("[ ] Windows Service registration missing in Program.cs.")

    # 3. Build Check (15 pts)
    exe_found = result.get("exe_found", False)
    build_config = result.get("build_config", "None")
    if exe_found:
        if build_config == "Release":
            score += 15
            feedback.append("[✓] Executable built successfully (Release).")
        else:
            score += 10
            feedback.append("[~] Executable built, but in Debug mode instead of Release.")
    else:
        feedback.append("[ ] Executable not found. Build failed or not attempted.")

    # 4. File Movement Check (15 pts)
    # The dynamic test dropped 'test_access_alpha.log' and 'test_access_beta.log'
    alpha_moved = result.get("test_alpha_moved", False)
    beta_moved = result.get("test_beta_moved", False)
    
    if alpha_moved and beta_moved:
        score += 15
        feedback.append("[✓] Service successfully moved files to archive folder.")
    elif alpha_moved or beta_moved:
        score += 7
        feedback.append("[~] Service partially moved files to archive.")
    else:
        feedback.append("[ ] Files were not moved to archive by the service.")

    # 5. Accurate Log Parsing (30 pts)
    summary = result.get("summary_content", "") or ""
    alpha_matched = False
    beta_matched = False
    
    # Test Alpha: 404=2, 500=1
    alpha_pattern = r'test_access_alpha\.log\s*:\s*404\s*=\s*2\s*,\s*500\s*=\s*1'
    if re.search(alpha_pattern, summary, re.IGNORECASE):
        alpha_matched = True
        
    # Test Beta: 404=0, 500=2
    beta_pattern = r'test_access_beta\.log\s*:\s*404\s*=\s*0\s*,\s*500\s*=\s*2'
    if re.search(beta_pattern, summary, re.IGNORECASE):
        beta_matched = True

    if alpha_matched and beta_matched:
        score += 30
        feedback.append("[✓] Log parsing accurately counted 404s and 500s for dynamic test files.")
    elif alpha_matched or beta_matched:
        score += 15
        feedback.append("[~] Log parsing partially accurate or format slightly off.")
    else:
        feedback.append("[ ] Log parsing counts incorrect or format did not match expected 'FileName: 404=X, 500=Y'.")

    # 6. VLM Trajectory Check (20 pts)
    query_vlm = env_info.get("query_vlm")
    frames = sample_trajectory_frames(traj, n=6)
    vlm_result = _vlm_query(query_vlm, VLM_PROMPT, frames)
    
    if vlm_result:
        vs_used = vlm_result.get("used_visual_studio", False)
        coded = vlm_result.get("wrote_code", False)
        
        if vs_used and coded:
            score += 20
            feedback.append("[✓] VLM verified active Visual Studio IDE usage and coding.")
        else:
            feedback.append("[ ] VLM could not confirm Visual Studio usage/coding from trajectory.")
    else:
        # Fallback if VLM fails but logic works
        if score >= 50:
            score += 20
            feedback.append("[?] VLM skipped/failed, awarding trajectory points based on programmatic success.")

    # Final Evaluation
    passed = score >= 75 and exe_found and (alpha_matched or beta_matched)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }