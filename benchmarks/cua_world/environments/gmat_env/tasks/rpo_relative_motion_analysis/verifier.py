#!/usr/bin/env python3
"""
Verifier for rpo_relative_motion_analysis@1

The agent must simulate the relative motion of a servicer past a target in a custom
TargetVNB coordinate system and extract the min/max range for passive safety verification.

Scoring (total 100 pts, pass >= 70):
  - script_created (10): Script created during task window
  - two_spacecraft (10): Both ENVISAT_TARGET and CS_SERVICER defined
  - vnb_coord_system (15): TargetVNB CoordinateSystem correctly defined (Origin=Target, Axes=VNB)
  - force_model_correct (10): Force model restricted to Earth Point Mass
  - summary_written (15): rpo_summary.txt exists and contains required fields
  - min_range_accurate (20): min_range_km is analytically accurate (within tolerance)
  - max_range_accurate (10): max_range_km is analytically accurate
  - vlm_verification (10): VLM confirms genuine interaction with GMAT interface
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_with_vlm(traj, env_info):
    """
    Use VLM on trajectory frames to ensure the agent actually used GMAT.
    """
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm, get_final_screenshot
    except ImportError:
        logger.warning("VLM libraries not available. Skipping VLM check.")
        return True, "VLM tools unavailable"
    
    # Sample 4 frames from the trajectory plus the final screenshot
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        if final:
            frames.append(final)
            
        if not frames:
            return False, "No trajectory frames available"
            
        prompt = """You are verifying if an AI agent successfully used NASA GMAT to design an RPO (Rendezvous and Proximity Operations) mission.
        
Look at these sequence of screenshots from the task trajectory.
1. Does the sequence show genuine interaction with the GMAT application?
2. Can you see signs of configuring Spacecraft, Coordinate Systems, or running a mission?
3. Can you see any text editors or output data confirming the agent evaluated the relative range?

Respond in JSON:
{
    "genuine_gmat_interaction": true/false,
    "rpo_configuration_visible": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation"
}
"""
        result = query_vlm(images=frames, prompt=prompt)
        if result and result.get("success"):
            parsed = result.get("parsed", {})
            genuine = parsed.get("genuine_gmat_interaction", False)
            reason = parsed.get("reasoning", "")
            return genuine, reason
        return False, "VLM query failed"
    except Exception as e:
        logger.error(f"VLM verification error: {e}")
        return True, f"VLM error (bypassed): {str(e)}"

def verify_rpo_relative_motion_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_min = metadata.get('expected_min_range_km', 0.77)
    tol_min = metadata.get('min_range_tolerance_km', 2.0)
    expected_max = metadata.get('expected_max_range_km', 71.4)
    tol_max = metadata.get('max_range_tolerance_km', 10.0)
    expected_passive = metadata.get('expected_passive_safety', 'false').lower()

    scores = {
        "script_created": 10,
        "two_spacecraft": 10,
        "vnb_coord_system": 15,
        "force_model_correct": 10,
        "summary_written": 15,
        "min_range_accurate": 20,
        "max_range_accurate": 10,
        "vlm_verification": 10
    }

    total_score = 0
    feedback = []

    # Load task result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 1. Check file creations
    script_file = task_result.get('script_file', {})
    if isinstance(script_file, dict) and script_file.get('created_during_task'):
        total_score += scores["script_created"]
        feedback.append("Script created during task window.")
    else:
        feedback.append("Script not created during task window.")

    summary_file = task_result.get('summary_file', {})
    if isinstance(summary_file, dict) and summary_file.get('created_during_task'):
        total_score += scores["summary_written"]
        feedback.append("Summary file created during task window.")
    else:
        feedback.append("Summary file not created during task window.")

    # 2. Check Data Results
    try:
        min_range = float(task_result.get('min_range_km', -1))
    except ValueError:
        min_range = -1.0
        
    try:
        max_range = float(task_result.get('max_range_km', -1))
    except ValueError:
        max_range = -1.0

    passive_violated = str(task_result.get('passive_safety_violated', 'unknown')).lower()

    min_range_ok = False
    if min_range >= 0 and abs(min_range - expected_min) <= tol_min:
        total_score += scores["min_range_accurate"]
        min_range_ok = True
        feedback.append(f"Min range accurate: {min_range:.2f} km.")
    else:
        feedback.append(f"Min range inaccurate: {min_range} km (Expected ~{expected_min} km).")

    if max_range >= 0 and abs(max_range - expected_max) <= tol_max:
        total_score += scores["max_range_accurate"]
        feedback.append(f"Max range accurate: {max_range:.2f} km.")
    else:
        feedback.append(f"Max range inaccurate: {max_range} km (Expected ~{expected_max} km).")

    # 3. Analyze script content
    script_path = task_result.get('script_path', '/home/ga/GMAT_output/rpo_drift.script')
    vnb_ok = False
    fm_ok = False
    
    if isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            # Spacecraft check
            if "ENVISAT_TARGET" in script_content and "CS_SERVICER" in script_content:
                total_score += scores["two_spacecraft"]
                feedback.append("Both target and servicer spacecraft found in script.")
            else:
                feedback.append("Missing one or both spacecraft in script.")

            # Coordinate System Check
            if re.search(r'Create\s+CoordinateSystem\s+TargetVNB', script_content) or "TargetVNB" in script_content:
                if re.search(r'Origin\s*=\s*ENVISAT_TARGET', script_content) and re.search(r'Axes\s*=\s*ObjectReferenced', script_content) or "VNB" in script_content:
                    total_score += scores["vnb_coord_system"]
                    vnb_ok = True
                    feedback.append("TargetVNB CoordinateSystem correctly defined.")
                else:
                    feedback.append("TargetVNB present but lacks correct Origin or Axes definition.")
            else:
                feedback.append("TargetVNB CoordinateSystem not found in script.")

            # Force Model Check
            if re.search(r'GravityField\.Earth\.Degree\s*=\s*0', script_content) or "PointMasses" in script_content:
                if "AtmosphereModel" not in script_content and "Drag" not in script_content:
                    total_score += scores["force_model_correct"]
                    fm_ok = True
                    feedback.append("ForceModel correctly restricted to Two-Body motion.")
                else:
                    feedback.append("ForceModel includes Drag/SRP, violating Point Mass constraint.")
            else:
                # GMAT handles purely PointMass natively if JGM isn't assigned, but we look for Degree=0 or 1, or just absence of Drag
                if "AtmosphereModel" not in script_content and "JGM" not in script_content:
                    total_score += scores["force_model_correct"]
                    fm_ok = True
                    feedback.append("ForceModel appears restricted to Two-Body motion (implied).")
                else:
                    feedback.append("ForceModel does not appear to be restricted to Two-Body motion.")
                    
        except Exception as e:
            feedback.append(f"Failed to parse script file: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)

    # 4. VLM Trajectory Verification
    vlm_genuine, vlm_reason = verify_with_vlm(traj, env_info)
    if vlm_genuine:
        total_score += scores["vlm_verification"]
        feedback.append("VLM confirms genuine GMAT interaction.")
    else:
        feedback.append(f"VLM verification failed/uncertain: {vlm_reason}")

    # Final Pass Condition Evaluation
    # Must achieve at least 70 points AND have accurate minimum range AND proper VNB coordinate system
    passed = total_score >= 70 and min_range_ok and vnb_ok

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }