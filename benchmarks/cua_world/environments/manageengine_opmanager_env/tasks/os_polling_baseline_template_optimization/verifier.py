#!/usr/bin/env python3
"""
Verifier for os_polling_baseline_template_optimization task.

Verification Strategy (Hybrid DB + VLM):
1. Programmatic DB Check (20 pts): Compares the initial and final PostgreSQL dumps of the 
   template tables. Deleting default monitors removes INSERT statements, meaning the 
   count of "Windows" and "Linux" associations will decrease.
2. VLM Trajectory Process Check (40 pts): Analyzes the agent's screen trajectory to verify 
   that it actually navigated to Device Templates, opened the Windows template, and 
   opened the Linux template to modify them.
3. VLM Final State Check (40 pts): Evaluates the final screens to confirm the agent successfully 
   reduced the monitors down to just CPU and Memory Utilization.

Pass threshold: 60 points (requires both DB modification evidence AND visual confirmation).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ================================================================
# VLM PROMPTS
# ================================================================

VLM_TRAJECTORY_PROMPT = """You are analyzing a sequence of screenshots from an agent configuring ManageEngine OpManager.
The agent was tasked with navigating to "Settings > Discovery > Device Templates" and editing the generic "Windows" and "Linux" device templates to remove all performance monitors except CPU and Memory.

Look at the chronological sequence of screenshots.
Assess the following:
1. Did the agent navigate to the Device Templates section?
2. Is there visual evidence the agent opened the "Windows" template editor?
3. Is there visual evidence the agent opened the "Linux" template editor?
4. Did the agent actively interact with the "Monitors" or "Performance Monitors" tab to delete items?

Respond ONLY in valid JSON format:
{
    "navigated_to_templates": true/false,
    "opened_windows_template": true/false,
    "opened_linux_template": true/false,
    "deleted_monitors": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation"
}
"""

VLM_FINAL_STATE_PROMPT = """You are analyzing the final actions of an agent configuring device templates in OpManager.
The goal was to strip the "Windows" and "Linux" templates so that ONLY "CPU Utilization" and "Memory Utilization" remain in the Performance Monitors tab.

Review the screenshots carefully (especially the later ones showing the template edit screens or save confirmations).
Assess the following:
1. Did the agent successfully save the changes for the Windows template?
2. Did the agent successfully save the changes for the Linux template?
3. From what is visible, does it appear the agent correctly left ONLY CPU and Memory monitors (meaning they deleted the extraneous ones like Disk Reads, Network Traffic, etc.)?

Respond ONLY in valid JSON format:
{
    "windows_saved": true/false,
    "linux_saved": true/false,
    "only_cpu_and_memory_left": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation"
}
"""

# ================================================================
# VERIFIER LOGIC
# ================================================================

def verify_os_polling_baseline(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    result_json_path = metadata.get('result_json', '/tmp/template_optimization_result.json')
    initial_sql_path = metadata.get('initial_sql_dump', '/tmp/initial_templates_export.sql')
    final_sql_path = metadata.get('final_sql_dump', '/tmp/final_templates_export.sql')

    score = 0
    feedback_parts = []

    # 1. Check basic JSON result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_json_path, temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to read result JSON: {e}")
        result_data = {"db_modified": False}
    finally:
        os.unlink(temp_result.name)

    # 2. Check Database Dumps for Modification (Anti-gaming & programmatic proof)
    temp_initial = tempfile.NamedTemporaryFile(delete=False, suffix='.sql')
    temp_final = tempfile.NamedTemporaryFile(delete=False, suffix='.sql')
    db_modification_valid = False
    
    try:
        copy_from_env(initial_sql_path, temp_initial.name)
        copy_from_env(final_sql_path, temp_final.name)
        
        with open(temp_initial.name, 'r', encoding='utf-8', errors='ignore') as f:
            initial_text = f.read()
            initial_windows_count = initial_text.lower().count('windows')
            initial_linux_count = initial_text.lower().count('linux')
            
        with open(temp_final.name, 'r', encoding='utf-8', errors='ignore') as f:
            final_text = f.read()
            final_windows_count = final_text.lower().count('windows')
            final_linux_count = final_text.lower().count('linux')
            
        # If monitors were deleted, the number of DB associations (INSERT statements containing the template name)
        # must be strictly less than the initial state.
        windows_reduced = final_windows_count < initial_windows_count
        linux_reduced = final_linux_count < initial_linux_count
        
        if windows_reduced and linux_reduced:
            db_modification_valid = True
            score += 20
            feedback_parts.append("DB Check: Associations for Windows and Linux templates successfully reduced (+20)")
        elif windows_reduced or linux_reduced:
            score += 10
            feedback_parts.append("DB Check: Partial reduction in template associations detected (+10)")
        else:
            feedback_parts.append("DB Check: No reduction in template associations detected (0/20)")
            
    except Exception as e:
        logger.warning(f"Failed to process SQL dumps: {e}")
        feedback_parts.append("DB Check: Could not verify SQL dumps")
    finally:
        os.unlink(temp_initial.name)
        os.unlink(temp_final.name)

    # 3. VLM Trajectory Verification
    if query_vlm:
        # Import dynamic frame sampling
        try:
            from gym_anything.vlm import sample_trajectory_frames
            # Sample 8 frames evenly across the trajectory
            frames = sample_trajectory_frames(traj, n=8)
            
            # Trajectory Process Check
            traj_result = query_vlm(prompt=VLM_TRAJECTORY_PROMPT, images=frames)
            if traj_result and traj_result.get("success"):
                parsed = traj_result.get("parsed", {})
                
                if parsed.get("navigated_to_templates"):
                    score += 10
                if parsed.get("opened_windows_template"):
                    score += 10
                if parsed.get("opened_linux_template"):
                    score += 10
                if parsed.get("deleted_monitors"):
                    score += 10
                    
                feedback_parts.append(f"VLM Trajectory: Templates navigated={parsed.get('navigated_to_templates')}, "
                                      f"Windows opened={parsed.get('opened_windows_template')}, "
                                      f"Linux opened={parsed.get('opened_linux_template')}, "
                                      f"Monitors deleted={parsed.get('deleted_monitors')}")
            else:
                feedback_parts.append("VLM Trajectory: Failed to parse VLM response.")

            # Final State Check (Focus heavily on the last few frames)
            final_frames = frames[-3:] if len(frames) >= 3 else frames
            final_result = query_vlm(prompt=VLM_FINAL_STATE_PROMPT, images=final_frames)
            if final_result and final_result.get("success"):
                parsed_final = final_result.get("parsed", {})
                
                if parsed_final.get("windows_saved") and parsed_final.get("linux_saved"):
                    score += 20
                    feedback_parts.append("VLM Final: Confirmed changes saved for both templates (+20)")
                elif parsed_final.get("windows_saved") or parsed_final.get("linux_saved"):
                    score += 10
                    feedback_parts.append("VLM Final: Confirmed changes saved for one template (+10)")
                    
                if parsed_final.get("only_cpu_and_memory_left"):
                    score += 20
                    feedback_parts.append("VLM Final: Confirmed strictly CPU and Memory monitors left (+20)")
            else:
                feedback_parts.append("VLM Final: Failed to parse VLM response.")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            feedback_parts.append(f"VLM error: {str(e)}")
    else:
        feedback_parts.append("VLM function not available. Cannot fully verify visual states.")

    # Determine final pass/fail
    passed = score >= 60 and db_modification_valid
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }