#!/usr/bin/env python3
"""
Verifier for debug_metadata_harvester task.

Scores the agent's fixes based on database output generated in the export script.
Uses VLM trajectory analysis to verify the agent used VS Code to edit the file.
"""

import os
import json
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_metadata_harvester(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_records = metadata.get('expected_records', 3)
    expected_unicode_author = metadata.get('expected_unicode_author', "Štěpán, J.")
    expected_multi_author = metadata.get('expected_multi_author', "Balázs, C.; Berger, E. L.; Nadolsky, P. M.; Yuan, C. -P.")
    expected_normalized_title = metadata.get('expected_normalized_title', "First string theory on a multiverse")

    score = 0
    feedback_parts = []
    
    # 1. Read JSON result from the container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read execution result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. VLM Trajectory Check (10 points)
    # Ensure the agent actually interacted with VS Code and didn't cheat programmatically
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        vlm_prompt = "Look at these frames. Is the user editing python code in Visual Studio Code (or a similar code editor interface)? Answer purely 'yes' or 'no'."
        vlm_resp = query_vlm(images=frames, prompt=vlm_prompt)
        
        if vlm_resp and vlm_resp.get("success"):
            answer = str(vlm_resp.get("parsed", {}).get("answer", "")).lower()
            if not answer:
                answer = str(vlm_resp.get("text", "")).lower()
                
            if "yes" in answer:
                score += 10
                feedback_parts.append("[+] VLM confirmed code editing activity (10/10)")
            else:
                feedback_parts.append("[-] VLM did not observe code editing activity (0/10)")
        else:
            feedback_parts.append("[~] VLM verification skipped/failed (0/10)")

    # Anti-gaming file timestamp check
    if not result.get("file_modified", False):
        feedback_parts.append("[-] harvester.py was not modified during the task!")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 3. Execution Success (15 points)
    exit_code = result.get("exit_code", -1)
    if exit_code == 0:
        score += 15
        feedback_parts.append("[+] Script executed without crashing (15/15)")
    else:
        feedback_parts.append(f"[-] Script crashed with exit code {exit_code} (0/15)")

    # 4. Namespace & Deleted Records (25 points)
    record_count = result.get("record_count", 0)
    if record_count == expected_records:
        score += 25
        feedback_parts.append(f"[+] Namespace fixed & Deleted records correctly skipped. Total records: {record_count} (25/25)")
    elif record_count > 0:
        score += 10
        feedback_parts.append(f"[~] Namespace fixed but record count is {record_count} (expected {expected_records}). Deleted records likely handled improperly. (10/25)")
    else:
        feedback_parts.append("[-] Database has 0 records. Namespace or Deleted Records bug still present. (0/25)")

    # 5. Unicode Bug (15 points)
    unicode_author = result.get("record_0027_authors", "")
    if unicode_author == expected_unicode_author:
        score += 15
        feedback_parts.append("[+] Unicode encoding correctly preserved (15/15)")
    else:
        feedback_parts.append(f"[-] Unicode encoding failed. Expected '{expected_unicode_author}', got '{unicode_author}' (0/15)")

    # 6. Multiple Authors Bug (20 points)
    multi_author = result.get("record_0001_authors", "")
    if multi_author == expected_multi_author:
        score += 20
        feedback_parts.append("[+] Multiple authors correctly extracted and joined (20/20)")
    elif ";" in multi_author:
        score += 10
        feedback_parts.append(f"[~] Authors partially correct: '{multi_author}' (10/20)")
    else:
        feedback_parts.append(f"[-] Multiple authors bug not fixed. Extracted: '{multi_author}' (0/20)")

    # 7. Whitespace Normalization (15 points)
    normalized_title = result.get("record_0001_title", "")
    if normalized_title == expected_normalized_title:
        score += 15
        feedback_parts.append("[+] Title whitespace perfectly normalized (15/15)")
    elif "\n" not in normalized_title and "\t" not in normalized_title:
        score += 5
        feedback_parts.append("[~] Newlines removed from title, but spacing is imprecise (5/15)")
    else:
        feedback_parts.append("[-] Title whitespace normalization failed (0/15)")

    passed = score >= metadata.get('pass_threshold', 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }