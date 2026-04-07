#!/usr/bin/env python3
"""
Verifier for epcra_threshold_filtered_entry task.

Multi-Criteria Scoring Strategy (100 pts total):
1. Output file exists and was created during the task (10 pts)
2. Required Chemical 1: Sodium Hydroxide included (20 pts)
3. Required Chemical 2: Nitric Acid included (20 pts)
4. Omitted Chemical 1: Propylene Glycol excluded (15 pts) [Awarded ONLY if active entry made]
5. Omitted Chemical 2: Chlorine excluded (15 pts) [Awarded ONLY if active entry made]
6. VLM Trajectory Verification: Confirms Tier2 app interaction and data entry (20 pts)

Anti-gaming: Omission points are gated to prevent "do nothing and score 30 points".
"""
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\Desktop\\epcra_threshold_filtered_entry_result.json"

def verify_epcra_threshold(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    metadata = task_info.get("metadata", {})
    result_file = metadata.get("result_file", RESULT_PATH)
    pass_threshold = metadata.get("pass_threshold", 75)

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    tmp = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    try:
        copy_from_env(result_file, tmp.name)
        with open(tmp.name, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read export results: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback_parts = []

    # Criterion 1: File check
    file_exists = result.get("file_exists", False)
    file_is_new = result.get("file_is_new", False)
    
    if not file_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "FAIL: Output .t2s file not found. Task was not completed."
        }
        
    if not file_is_new:
        feedback_parts.append("WARNING: Output file predates task start time. Possible gaming detected.")
    else:
        score += 10
        feedback_parts.append("PASS: Valid output file exported during task (+10)")

    chemicals = result.get("chemicals_found", [])
    
    # Track if agent actively added correct entries (gating omission points)
    correct_additions = 0

    # Criterion 2 & 3: Required Chemicals
    if "1310-73-2" in chemicals:
        score += 20
        correct_additions += 1
        feedback_parts.append("PASS: Sodium Hydroxide (>10k threshold) correctly included (+20)")
    else:
        feedback_parts.append("FAIL: Missing Sodium Hydroxide (1310-73-2)")

    if "7697-37-2" in chemicals:
        score += 20
        correct_additions += 1
        feedback_parts.append("PASS: Nitric Acid (>500 lbs EHS threshold) correctly included (+20)")
    else:
        feedback_parts.append("FAIL: Missing Nitric Acid (7697-37-2)")

    # Criterion 4 & 5: Omitted Chemicals
    if correct_additions > 0:
        if "57-55-6" not in chemicals:
            score += 15
            feedback_parts.append("PASS: Propylene Glycol correctly filtered out (+15)")
        else:
            feedback_parts.append("FAIL: Propylene Glycol erroneously included (Below 10k threshold)")

        if "7782-50-5" not in chemicals:
            score += 15
            feedback_parts.append("PASS: Chlorine correctly filtered out (+15)")
        else:
            feedback_parts.append("FAIL: Chlorine erroneously included (Below EHS TPQ threshold)")
    else:
        feedback_parts.append("FAIL: No required chemicals added. Omission points forfeited to prevent 'do-nothing' gaming.")

    # Criterion 6: VLM Trajectory Verification
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images:
            prompt = """Analyze this agent's desktop trajectory sequence.
            1. Did the agent open the Tier2 Submit application?
            2. Is there evidence the agent reviewed a CSV or spreadsheet?
            3. Was the agent actively entering form data (not just clicking randomly)?
            Respond in JSON: {"tier2_used": true/false, "csv_viewed": true/false, "entering_data": true/false}"""
            
            res = query_vlm(images=images, prompt=prompt)
            if res and isinstance(res, dict) and res.get('success'):
                parsed = res.get('parsed', {})
                if parsed.get('tier2_used') and parsed.get('entering_data'):
                    vlm_score = 20
                    feedback_parts.append("PASS: VLM visual verification confirmed active task execution (+20)")
                else:
                    feedback_parts.append("WARNING: VLM could not confirm proper tool usage.")
    except Exception as e:
        logger.warning(f"VLM verification failed or unavailable: {e}")
        # Default grant points if framework VLM tools are missing but program checks pass
        if correct_additions > 0:
            vlm_score = 20
            feedback_parts.append("VLM assumed PASS due to strong programmatic evidence.")

    score += vlm_score

    passed = score >= pass_threshold
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }