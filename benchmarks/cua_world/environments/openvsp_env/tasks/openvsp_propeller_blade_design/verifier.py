#!/usr/bin/env python3
"""
Verifier for openvsp_propeller_blade_design task.

Checks:
1. Output file exists and was saved during the task (anti-gaming).
2. Model is valid XML and contains a Propeller component.
3. Component name matches exactly.
4. Correct number of blades.
5. Diameter within tolerance.
6. Precone within tolerance.
7. VLM verification of trajectory to confirm UI interaction.
"""

import json
import os
import re
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _find_param_values(content: str, tag: str) -> list[float]:
    """Find all Value attributes for elements with the given tag name."""
    pattern = rf'<{tag}\s+Value="([^"]+)"'
    vals = []
    for m in re.finditer(pattern, content):
        try:
            vals.append(float(m.group(1)))
        except ValueError:
            pass
    return vals

def _check_propeller_exists(content: str) -> bool:
    """Check if a Propeller geometry is in the XML."""
    return "<TypeName>Prop</TypeName>" in content or "<TypeName>Propeller</TypeName>" in content

def verify_propeller_design(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    expected_name = metadata.get("expected_name", "HC-B4TN")
    expected_blades = float(metadata.get("expected_blades", 4.0))
    expected_diameter = float(metadata.get("expected_diameter", 2.36))
    diameter_tol = metadata.get("diameter_tolerance_pct", 0.18)
    expected_precone = float(metadata.get("expected_precone", 2.5))
    precone_tol = metadata.get("precone_tolerance_deg", 2.5)

    result_file = "/tmp/openvsp_propeller_result.json"
    
    local_tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env(result_file, local_tmp.name)
        with open(local_tmp.name, "r") as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result file not found — export script failed: {e}"
        }
    finally:
        if os.path.exists(local_tmp.name):
            os.unlink(local_tmp.name)

    score = 0
    feedback_parts = []
    
    # Check 1: File existence and timestamp (Anti-gaming)
    if not data.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "kingair_propeller.vsp3 not found. Agent did not save the file."
        }

    if not data.get("file_created_during_task", False):
        feedback_parts.append("Warning: File timestamp is older than task start time (possible stale file).")
    
    content = data.get("file_content", "").replace("\\n", "\n").replace("\\t", "\t")

    # Validate XML
    try:
        ET.fromstring(content)
        score += 10
        feedback_parts.append("File is valid XML (+10)")
    except ET.ParseError as e:
        return {
            "passed": False,
            "score": 5,
            "feedback": f"File exists but is not valid XML: {e}"
        }

    # Check 2: Propeller component present (20 pts)
    if _check_propeller_exists(content):
        score += 20
        feedback_parts.append("Propeller component found (+20)")
    else:
        feedback_parts.append("No Propeller component found (+0)")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # Check 3: Component Name (10 pts)
    if f"<Name>{expected_name}</Name>" in content:
        score += 10
        feedback_parts.append(f"Name '{expected_name}' matches (+10)")
    else:
        feedback_parts.append(f"Name '{expected_name}' not found (+0)")

    # Check 4: NumBlade = 4 (20 pts)
    blade_vals = _find_param_values(content, "NumBlade") + _find_param_values(content, "Num_Blade")
    if expected_blades in blade_vals:
        score += 20
        feedback_parts.append(f"NumBlade = {expected_blades} correct (+20)")
    elif blade_vals:
        feedback_parts.append(f"NumBlade incorrect (found {blade_vals}) (+0)")
    else:
        feedback_parts.append("NumBlade parameter not found (+0)")

    # Check 5: Diameter (20 pts)
    diameter_vals = _find_param_values(content, "Diameter")
    diam_min = expected_diameter * (1.0 - diameter_tol)
    diam_max = expected_diameter * (1.0 + diameter_tol)
    
    diam_correct = False
    for dv in diameter_vals:
        if diam_min <= dv <= diam_max:
            diam_correct = True
            break
            
    if diam_correct:
        score += 20
        feedback_parts.append(f"Diameter within [{diam_min:.2f}, {diam_max:.2f}] (+20)")
    elif diameter_vals:
        feedback_parts.append(f"Diameter incorrect (found {diameter_vals}) (+0)")
    else:
        feedback_parts.append("Diameter parameter not found (+0)")

    # Check 6: Precone (10 pts)
    precone_vals = _find_param_values(content, "Precone")
    pre_min = expected_precone - precone_tol
    pre_max = expected_precone + precone_tol
    
    precone_correct = False
    for pv in precone_vals:
        if pre_min <= pv <= pre_max:
            precone_correct = True
            break
            
    if precone_correct:
        score += 10
        feedback_parts.append(f"Precone within [{pre_min:.1f}, {pre_max:.1f}] (+10)")
    elif precone_vals:
        feedback_parts.append(f"Precone incorrect (found {precone_vals}) (+0)")
    else:
        feedback_parts.append("Precone parameter not found (+0)")
        
    # Check 7: XSec count (10 pts)
    xsec_count = len(re.findall(r'<XSec\s', content)) + len(re.findall(r'<XSec>', content))
    if xsec_count >= metadata.get("min_xsec", 3):
        score += 10
        feedback_parts.append(f"Sufficient cross-sections defined ({xsec_count}) (+10)")
    else:
        feedback_parts.append(f"Insufficient cross-sections (found {xsec_count}, need >= 3) (+0)")

    # VLM Trajectory Verification
    vlm_bonus = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        query_vlm = env_info.get('query_vlm')
        
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=3)
            final_img = get_final_screenshot(traj)
            if final_img:
                frames.append(final_img)
            
            prompt = (
                "You are reviewing the execution of a 3D modeling task in OpenVSP. "
                "Task: Create a 4-blade propeller model.\n"
                "Look at these trajectory frames and the final screenshot.\n"
                "Is there visual evidence that the user interacted with the Propeller geometry tool "
                "or that a propeller (especially a 4-blade one) is visible in the 3D view? "
                "Answer ONLY with a valid JSON object: {\"propeller_visible\": true/false}"
            )
            vlm_res = query_vlm(prompt=prompt, images=frames)
            
            if vlm_res and vlm_res.get("success"):
                vlm_parsed = vlm_res.get("parsed", {})
                if vlm_parsed.get("propeller_visible"):
                    vlm_bonus = 10
                    feedback_parts.append("VLM visual confirmation of propeller (+10 bonus)")
                else:
                    feedback_parts.append("VLM could not confirm propeller visually.")
    except Exception as e:
        logger.warning(f"VLM verification failed or unavailable: {e}")

    total_score = min(100, score + vlm_bonus)
    passed = total_score >= 60

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback_parts)
    }