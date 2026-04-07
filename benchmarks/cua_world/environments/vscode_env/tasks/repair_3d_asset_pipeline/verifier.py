#!/usr/bin/env python3
"""
Verifier for repair_3d_asset_pipeline task.

Checks whether the agent fixed 5 critical bugs in process_models.py
by evaluating the output of the agent's script against a hidden dataset.
"""

import os
import json
import base64
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Ground Truth definition for the hidden dataset
# hidden_skybox.obj: v 100 200 300; v 150 250 350; vt 1.5 0.5; f 1/1/1 2/1/1 1/1/1
# hidden_ground.obj: v -10 -5 -10; v -5 -1 -5; vt 0.5 0.5; f 1/1/1 2/1/1 1/1/1

def verify_asset_pipeline(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/asset_pipeline_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    script_modified = result.get("script_modified", False)
    exec_exit_code = result.get("exec_exit_code", -1)
    
    if script_modified:
        score += 10
        feedback.append("[+] Script was modified during task (10/10)")
    else:
        feedback.append("[-] Script was NOT modified (0/10)")

    if exec_exit_code == 0:
        score += 10
        feedback.append("[+] Script executed successfully on hidden dataset (10/10)")
    else:
        error_msg = ""
        try:
            err_b64 = result.get("exec_error_b64", "")
            if err_b64:
                error_msg = base64.b64decode(err_b64).decode('utf-8').strip().split('\n')[-1]
        except:
            pass
        feedback.append(f"[-] Script crashed during execution: {error_msg} (0/10)")

    # Parse Output JSON
    output_json = None
    try:
        json_b64 = result.get("output_json_b64", "")
        if json_b64:
            output_json = json.loads(base64.b64decode(json_b64).decode('utf-8'))
    except Exception as e:
        feedback.append(f"[-] Output assets.json could not be parsed: {e}")

    # Evaluate Bug Fixes based on hidden dataset output
    bug_aggregation_fixed = False
    bug_whitespace_fixed = False
    bug_bounds_fixed = False
    bug_indices_fixed = False
    bug_uvs_fixed = False

    if output_json is not None:
        # BUG 5: Aggregation (Should be a list of 2 items)
        if isinstance(output_json, list) and len(output_json) == 2:
            bug_aggregation_fixed = True
            score += 15
            feedback.append("[+] Aggregation bug fixed: JSON contains all models (15/15)")
        else:
            length = len(output_json) if isinstance(output_json, list) else 0
            feedback.append(f"[-] Aggregation bug remains: Expected 2 models in array, found {length} (0/15)")

        # Map models by name to evaluate specific geometric bugs
        models = {}
        if isinstance(output_json, list):
            for m in output_json:
                if isinstance(m, dict) and "name" in m:
                    models[m["name"]] = m

        skybox = models.get("hidden_skybox.obj", {})
        ground = models.get("hidden_ground.obj", {})

        # Need at least skybox to test remaining bugs
        if skybox:
            # BUG 1: Whitespace split bug
            if skybox.get("vertex_count") == 2:
                bug_whitespace_fixed = True
                score += 15
                feedback.append("[+] Whitespace parsing bug fixed: parsed all vertices (15/15)")
            else:
                feedback.append("[-] Whitespace parsing bug remains: vertex count incorrect (0/15)")

            # BUG 2: Bounding box float('inf') bug
            bounds = skybox.get("bounds", {})
            min_b = bounds.get("min", [0,0,0])
            # If bug remains, min_bounds initialized to 0.0 will stay 0.0 because 0.0 < 100.0
            if min_b == [100.0, 200.0, 300.0]:
                bug_bounds_fixed = True
                score += 15
                feedback.append("[+] Bounding box bug fixed: positive space min bounds correct (15/15)")
            else:
                feedback.append(f"[-] Bounding box bug remains: min bounds {min_b} incorrect (0/15)")

            # BUG 3: 0-Based Indices bug
            indices = skybox.get("indices", [])
            if indices and indices[0] == [0, 1, 0]:
                bug_indices_fixed = True
                score += 15
                feedback.append("[+] Indices bug fixed: 0-based indexing correctly applied (15/15)")
            elif indices and indices[0] == [1, 2, 1]:
                feedback.append("[-] Indices bug remains: 1-based indexing outputted (0/15)")
            else:
                feedback.append("[-] Indices bug remains: index structure incorrect (0/15)")

            # BUG 4: UV bounds bug (> 1.0)
            if skybox.get("has_valid_uvs") is False:
                bug_uvs_fixed = True
                score += 10
                feedback.append("[+] UV bounds bug fixed: properly flags UVs > 1.0 (10/10)")
            else:
                feedback.append("[-] UV bounds bug remains: failed to flag UVs > 1.0 (0/10)")
        else:
            feedback.append("[-] Could not evaluate logic fixes because hidden_skybox.obj was not parsed.")
    else:
        feedback.append("[-] Evaluation skipped due to missing or invalid assets.json")

    # VLM Trajectory Verification
    vlm_score = 0
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final_img = get_final_screenshot(traj)
            if final_img:
                frames.append(final_img)
            
            prompt = """
            You are auditing a coding task in VS Code.
            Look at the trajectory frames. 
            Did the user actively edit Python code in the editor, modifying the script's logic?
            Look for active typing, selection, or moving around the file.
            Respond strictly with JSON: {"actively_edited_code": true/false}
            """
            vlm_res = query_vlm(prompt=prompt, images=frames)
            if vlm_res and vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("actively_edited_code"):
                    vlm_score = 10
                    score += 10
                    feedback.append("[+] VLM verified active code editing trajectory (10/10)")
                else:
                    feedback.append("[-] VLM did not detect active code editing (0/10)")
            else:
                feedback.append("[?] VLM verification failed or unavailable (0/10)")
        except Exception as e:
            feedback.append(f"[?] VLM verification error: {e} (0/10)")
    else:
        feedback.append("[?] VLM not configured (0/10)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback),
        "details": {
            "bug_aggregation_fixed": bug_aggregation_fixed,
            "bug_whitespace_fixed": bug_whitespace_fixed,
            "bug_bounds_fixed": bug_bounds_fixed,
            "bug_indices_fixed": bug_indices_fixed,
            "bug_uvs_fixed": bug_uvs_fixed
        }
    }