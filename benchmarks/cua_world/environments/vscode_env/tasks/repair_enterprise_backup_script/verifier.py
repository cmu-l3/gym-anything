#!/usr/bin/env python3
"""
Verifier for repair_enterprise_backup_script task.

Combines robust regex static analysis of the submitted Bash scripts 
to check if the 5 specific vulnerabilities/bugs were mitigated, 
with VLM-based trajectory analysis to ensure anti-gaming.
"""

import os
import json
import re
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# =============================================================================
# VLM PROMPT
# =============================================================================

VLM_PROMPT = """You are verifying an agent's trajectory for a debugging task. 
The agent was asked to fix a set of bash scripts and run a pytest suite in VS Code.

Look at these trajectory frames and determine:
1. Is there evidence the agent edited the bash scripts (.sh files) in the editor?
2. Did the agent execute tests in the terminal (e.g. `pytest tests/test_backup.py` or run bash scripts)?

Return a JSON object:
{
    "edited_scripts": true/false,
    "executed_tests": true/false,
    "reasoning": "brief explanation"
}
"""

def verify_backup_script(traj, env_info, task_info):
    """
    Verify that the 5 Bash footguns were mitigated.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    sources = result.get("sources", {})
    score = 0
    feedback_parts = []
    
    # ── Bug 1: Silent Pipeline Failure (lib/db_backup.sh) ──────────
    db_src = sources.get("lib/db_backup.sh", "")
    has_pipefail = bool(re.search(r'set\s+-.*o\s+pipefail', db_src))
    has_pipestatus = 'PIPESTATUS' in db_src
    
    if has_pipefail or has_pipestatus:
        score += 15
        feedback_parts.append("[+] Pipeline failure mitigated (pipefail/PIPESTATUS used)")
    else:
        feedback_parts.append("[-] Pipeline failure unmitigated (missing pipefail)")

    # ── Bug 2: Unsafe Filename Iteration (lib/fs_backup.sh) ────────
    fs_src = sources.get("lib/fs_backup.sh", "")
    # Original bug: `for file in $(ls "$UPLOAD_DIR"); do`
    # Ensure they removed $(ls ...) or `ls ...`
    still_has_ls = bool(re.search(r'\$\(\s*ls\b', fs_src)) or bool(re.search(r'`\s*ls\b', fs_src))
    # Ensure they still have some copy mechanism
    has_cp = 'cp ' in fs_src

    if not still_has_ls and has_cp:
        score += 15
        feedback_parts.append("[+] Unsafe filename iteration fixed")
    else:
        feedback_parts.append("[-] Still uses unquoted/$(ls) subshell for iteration")

    # ── Bug 3: Subshell Variable Loss (lib/fs_backup.sh) ───────────
    # Original bug: `find ... | while read -r f; do ... TOTAL_SIZE=... done`
    still_has_pipe_while = bool(re.search(r'\|\s*while', fs_src))
    has_process_sub = bool(re.search(r'<\s*<\s*\(', fs_src))
    has_lastpipe = 'lastpipe' in fs_src
    has_redirect = bool(re.search(r'>>\s*\S+', fs_src)) # Using a temp file

    if 'TOTAL_SIZE=' in fs_src and (has_process_sub or has_lastpipe or has_redirect or not still_has_pipe_while):
        score += 15
        feedback_parts.append("[+] Subshell variable loss mitigated")
    else:
        feedback_parts.append("[-] Variable still lost in piped while subshell")

    # ── Bug 4: Stale Lockfile Prevention (lib/common.sh) ───────────
    common_src = sources.get("lib/common.sh", "")
    # Original bug: `if [ -f "$PID_FILE" ]; then exit 1; fi`
    # Fix requires verifying the PID: kill -0, ps, or /proc/
    checks_running = 'kill -0' in common_src or 'ps -p' in common_src or 'ps -e' in common_src or '/proc/' in common_src
    
    if checks_running:
        score += 15
        feedback_parts.append("[+] Stale lockfile check implemented (liveness verification)")
    else:
        feedback_parts.append("[-] Lockfile check still blocks on stale PID file")

    # ── Bug 5: Incomplete Cleanup on Error (backup_manager.sh) ─────
    mgr_src = sources.get("backup_manager.sh", "")
    # Fix requires setting a trap for cleanup
    has_trap = bool(re.search(r'trap\s+.*(?:EXIT|ERR|SIGINT|INT)', mgr_src, re.IGNORECASE))
    
    if has_trap:
        score += 15
        feedback_parts.append("[+] Cleanup trap defined for script termination")
    else:
        feedback_parts.append("[-] No trap implemented for guaranteed staging cleanup")


    # =========================================================================
    # VLM Trajectory Verification (Anti-Gaming) - 25 points
    # =========================================================================
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        if final_img:
            frames.append(final_img)

        if frames:
            vlm_resp = query_vlm(prompt=VLM_PROMPT, images=frames)
            
            if vlm_resp and vlm_resp.get("success"):
                parsed = vlm_resp.get("parsed", {})
                
                if parsed.get("edited_scripts"):
                    vlm_score += 15
                    feedback_parts.append("[+] VLM confirmed script editing")
                else:
                    feedback_parts.append("[-] VLM did not observe script editing")
                    
                if parsed.get("executed_tests"):
                    vlm_score += 10
                    feedback_parts.append("[+] VLM confirmed test execution")
                else:
                    feedback_parts.append("[-] VLM did not observe test execution")
            else:
                feedback_parts.append("[?] VLM query failed or returned no data")
    else:
        feedback_parts.append("[?] VLM verification skipped (not available)")
        vlm_score = 25 # Grant points if framework lacks VLM

    score += vlm_score

    # Determine passing status
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }