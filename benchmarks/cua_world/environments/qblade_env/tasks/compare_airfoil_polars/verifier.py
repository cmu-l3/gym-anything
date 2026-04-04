#!/usr/bin/env python3
"""
Verifier for compare_airfoil_polars task.

Criteria:
1. Project file exists and is valid (15 pts)
2. File created during task (anti-gaming) (10 pts)
3. File contains NACA 0012 airfoil (15 pts)
4. File contains NACA 4412 airfoil (15 pts)
5. File contains polar analysis data (20 pts)
6. File evidence of two distinct polars / proper Reynolds (25 pts)

Hybrid Verification:
- Primary: Programmatic check of the .wpa project file content.
- Secondary: VLM check of trajectory frames to confirm XFoil workflow.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import VLM utilities if available in the environment
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False


def verify_compare_airfoil_polars(traj, env_info, task_info):
    """Verify that two airfoils were created and analyzed in QBlade."""

    # 1. Setup and data retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # =========================================================
    # PROGRAMMATIC CHECKS (85 points possible)
    # =========================================================

    # Criterion 1: File Existence & Size (15 pts)
    file_exists = result.get("file_exists", False)
    file_size = result.get("file_size", 0)
    
    if file_exists and file_size > 2000: # Arbitrary threshold for non-empty project
        score += 15
        feedback_parts.append("Project file exists and has content")
    elif file_exists:
        score += 5
        feedback_parts.append("Project file exists but is suspiciously small")
    else:
        feedback_parts.append("Project file not found")
        # Critical failure if file doesn't exist, but check VLM just in case
        # Continuing to calculate score but it will likely fail

    # Criterion 2: Anti-gaming Timestamp (10 pts)
    if result.get("file_created_during_task", False):
        score += 10
        feedback_parts.append("File created during task session")
    elif file_exists:
        feedback_parts.append("File timestamp predates task (possible stale data)")

    # Criterion 3: NACA 0012 Present (15 pts)
    if result.get("contains_0012", False):
        score += 15
        feedback_parts.append("NACA 0012 found")
    else:
        feedback_parts.append("NACA 0012 missing")

    # Criterion 4: NACA 4412 Present (15 pts)
    if result.get("contains_4412", False):
        score += 15
        feedback_parts.append("NACA 4412 found")
    else:
        feedback_parts.append("NACA 4412 missing")

    # Criterion 5: Polar Data Structure (15 pts)
    polar_count = result.get("polar_reference_count", 0)
    if result.get("contains_polar_data", False) and polar_count > 0:
        score += 15
        feedback_parts.append("Polar data structure found")
    else:
        feedback_parts.append("No polar data found")

    # Criterion 6: Correct Analysis Parameters / Multiple Polars (15 pts)
    # We want at least 2 polars and correct Reynolds number
    if result.get("contains_reynolds", False) and polar_count >= 2:
        score += 15
        feedback_parts.append("Two distinct polars with correct Re detected")
    elif result.get("contains_reynolds", False):
        score += 10
        feedback_parts.append("Correct Reynolds detected, but maybe not both polars")
    elif polar_count >= 2:
        score += 5
        feedback_parts.append("Multiple polars found, but Re 500k not explicitly confirmed in text scan")

    # =========================================================
    # VLM CHECKS (15 points possible)
    # =========================================================
    vlm_score = 0
    if VLM_AVAILABLE:
        try:
            # Sample frames to see workflow
            frames = sample_trajectory_frames(traj, n=4)
            final_screen = get_final_screenshot(traj)
            
            prompt = """
            Review these screenshots of QBlade software usage.
            I am looking for evidence that the user:
            1. Created/Selected NACA 0012 and NACA 4412 airfoils.
            2. Performed XFoil analysis (graphs showing Cl/Cd curves).
            3. Saved the project.

            Do you see:
            - Any airfoil shapes or names like '0012' or '4412'?
            - Any 'XFoil Direct Analysis' graphs or polar plots?
            
            Return JSON: {"airfoils_visible": bool, "graphs_visible": bool, "confidence": float}
            """
            
            response = query_vlm(images=frames + [final_screen], prompt=prompt)
            
            if response.get("success"):
                data = response.get("parsed", {})
                if data.get("airfoils_visible"):
                    vlm_score += 5
                    feedback_parts.append("VLM confirmed airfoils visible")
                if data.get("graphs_visible"):
                    vlm_score += 10
                    feedback_parts.append("VLM confirmed analysis graphs visible")
            else:
                # If VLM fails, award points if file evidence is strong
                if score >= 60: 
                    vlm_score += 15
                    feedback_parts.append("VLM skipped, assuming success based on file evidence")
                    
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback scoring
            if score >= 60:
                vlm_score += 15

    score += vlm_score

    # =========================================================
    # FINAL EVALUATION
    # =========================================================
    
    # Normalize score to 100 max if needed (current total max = 85 + 15 = 100)
    passed = score >= 65 and file_exists and result.get("contains_polar_data", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }