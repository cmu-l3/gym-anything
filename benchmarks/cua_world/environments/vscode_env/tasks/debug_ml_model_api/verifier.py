#!/usr/bin/env python3
"""
Verifier for Debug ML Model API task.

Criteria:
1. Type coercion (BMI float preserved) - 20 pts
2. Matrix Shape (API handles row vector properly) - 20 pts
3. Preprocessing logic correct (Scaler + OHE match ground truth) - 20 pts
4. Performance/Memory (Global model load) - 20 pts
5. VLM Trajectory (Agent actively used VSCode for ML tasks) - 20 pts
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """
You are verifying an agent's completion of a coding task.
The agent was asked to fix bugs in a FastAPI application serving a machine learning model.

Look at the provided trajectory frames from the desktop.
1. Is Visual Studio Code visible and being used?
2. Does the agent appear to be editing Python code related to machine learning (e.g., pandas, sklearn, fastAPI, schemas)?
3. Is there evidence of running tests or interacting with the terminal to debug the application?

Respond in JSON format:
{
    "vscode_used": true/false,
    "editing_python": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation"
}
"""

def verify_ml_api(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/ml_api_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse test results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Ensure they actually did work
    if not result.get("files_modified", False):
        return {"passed": False, "score": 0, "feedback": "Files were not modified during the task. (0/100)"}

    # 1. Type Coercion (20 pts)
    if result.get("bmi_float_preserved"):
        score += 20
        feedback_parts.append("✅ Pydantic Type Truncation fixed (bmi is float)")
    else:
        feedback_parts.append("❌ Pydantic schema still truncates floats")

    # 2. Matrix Shape (20 pts)
    if result.get("shape_correct"):
        score += 20
        feedback_parts.append("✅ Matrix Reshaping fixed (API survived shape requirements)")
    else:
        feedback_parts.append("❌ Numpy reshape error persists")

    # 3. Preprocessing (20 pts)
    if result.get("preprocessing_correct"):
        score += 20
        feedback_parts.append("✅ Preprocessing logic matches training (Scaler + OHE correct)")
    else:
        feedback_parts.append("❌ Preprocessing output probability did not match expected truth (Scaler or OHE missing/incorrect)")

    # 4. Global Load (20 pts)
    if result.get("model_loaded_globally"):
        score += 20
        feedback_parts.append("✅ Memory Leak fixed (model loaded outside route handler)")
    else:
        feedback_parts.append("❌ joblib.load() is still inside the prediction route")

    # 5. VLM Trajectory Verification (20 pts)
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            vlm_res = query_vlm(prompt=VLM_PROMPT, images=frames)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("vscode_used") and parsed.get("editing_python"):
                    score += 20
                    feedback_parts.append("✅ VLM confirmed visual trajectory of coding")
                else:
                    feedback_parts.append("❌ VLM did not observe active coding in VS Code")
            else:
                feedback_parts.append("⚠️ VLM verification failed")
    else:
        # Give benefit of doubt if VLM unvailable but code is perfect
        if score == 80:
            score += 20
        feedback_parts.append("⚠️ VLM missing")

    if result.get("errors"):
        feedback_parts.append(f"Test Logs: {result['errors'][0]}")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }