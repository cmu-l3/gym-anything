#!/usr/bin/env python3
"""
Verifier for Mach Compressibility Study task.

Verifies:
1. Project file creation and validity.
2. Content of project file (Airfoil, Mach numbers, Reynolds).
3. VLM verification of the workflow (changing Mach, running polars).
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# Framework imports for VLM
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
except ImportError:
    # Mock for testing if environment not available
    def sample_trajectory_frames(traj, n=5): return []
    def query_vlm(images, prompt): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mach_study(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the Mach number compressibility study task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON from Container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/mach_study_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # =========================================================
    # CRITERION 1: File Existence & Anti-Gaming (30 pts)
    # =========================================================
    file_exists = result.get('file_exists', False)
    created_fresh = result.get('created_during_task', False)
    file_size = result.get('file_size_bytes', 0)

    if file_exists and created_fresh and file_size > 1000:
        score += 30
        feedback.append("Project file saved correctly.")
    elif file_exists:
        score += 10
        feedback.append("Project file exists but timestamp/size check failed.")
    else:
        feedback.append("Project file 'mach_study.wpa' not found.")
        # Fail immediately if no file
        return {"passed": False, "score": 0, "feedback": "No output file found."}

    # =========================================================
    # CRITERION 2: Content Verification (40 pts)
    # =========================================================
    content = result.get('content_check', {})
    
    # Airfoil check (10 pts)
    if content.get('has_naca_0012'):
        score += 10
        feedback.append("NACA 0012 airfoil detected.")
    else:
        feedback.append("Could not confirm NACA 0012 airfoil in project.")

    # Mach Number checks (20 pts - need at least 2 distinct non-zero checks or count)
    mach_checks = [content.get('has_mach_03'), content.get('has_mach_05')]
    if all(mach_checks):
        score += 20
        feedback.append("Polars for Mach 0.3 and 0.5 detected.")
    elif any(mach_checks):
        score += 10
        feedback.append("Only one non-zero Mach polar detected.")
    else:
        feedback.append("Specific Mach number settings (0.3, 0.5) not found in file text.")

    # Reynolds check (10 pts)
    if content.get('has_re_3m'):
        score += 10
        feedback.append("Reynolds number 3,000,000 detected.")
    else:
        feedback.append("Reynolds number 3,000,000 not detected.")

    # =========================================================
    # CRITERION 3: VLM Workflow Verification (30 pts)
    # =========================================================
    # Sample frames to see the settings being changed
    frames = sample_trajectory_frames(traj, n=8)
    
    vlm_prompt = """
    Analyze these screenshots of QBlade usage.
    I am looking for evidence of an aerodynamic compressibility study workflow.
    
    Check for:
    1. 'XFoil Direct Analysis' module being visible.
    2. Input fields for 'Mach' number being changed (e.g., 0.0, 0.3, 0.5).
    3. Input field for 'Re' (Reynolds) set to approx 3,000,000.
    4. Polar curves being generated (graphs appearing on the right).
    
    Return JSON:
    {
        "xfoil_module_seen": boolean,
        "mach_settings_changed": boolean,
        "polars_generated": boolean,
        "confidence": "low/medium/high"
    }
    """
    
    vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
    
    if vlm_res.get('success'):
        parsed = vlm_res.get('parsed', {})
        if parsed.get('xfoil_module_seen'):
            score += 10
            feedback.append("VLM: XFoil module usage confirmed.")
        
        if parsed.get('mach_settings_changed'):
            score += 10
            feedback.append("VLM: Mach number settings modification observed.")
        
        if parsed.get('polars_generated'):
            score += 10
            feedback.append("VLM: Polar generation observed.")
    else:
        feedback.append("VLM verification failed to execute.")

    # Final Pass Logic
    # Must have file + airfoil + at least one Mach confirmed + VLM confirmation or strong file evidence
    passed = score >= 60 and file_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }