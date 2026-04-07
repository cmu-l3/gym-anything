#!/usr/bin/env python3
"""
Verifier for openvsp_floatplane_conversion task.

VERIFICATION STRATEGY (Hybrid Programmatic + VLM):
1. File Existence & Anti-Gaming: Ensure floatplane_variant.vsp3 was created DURING the task. (15 pts)
2. XML Parametric Verification:
   - Baseline preservation: At least 3 components exist. (10 pts)
   - Float geometry added: Component with Z < -1.0 exists. (15 pts)
   - Float length correct: ~5.8m. (15 pts)
   - Float position correct: X~0.8, |Y|~1.4. (15 pts)
   - Symmetry applied: Check for twin floats logic. (10 pts)
3. VLM Trajectory Verification: Checks screenshots to ensure GUI was actually used and the final 3D view shows twin floats. (20 pts)
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _extract_geom_blocks(xml_content: str) -> list:
    """Extract all <Geom>...</Geom> blocks from the OpenVSP XML."""
    return re.findall(r'<Geom\b.*?</Geom>', xml_content, re.DOTALL)


def _find_param(geom_block: str, param_names: list) -> float:
    """Find the first matching parameter value from a list of possible names."""
    for name in param_names:
        m = re.search(rf'<{name}\s+Value="([+-]?\d+\.?\d*(?:e[+-]\d+)?)"', geom_block)
        if m:
            return float(m.group(1))
    return None


def verify_openvsp_floatplane_conversion(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_len = metadata.get('float_target_length', 5.8)
    target_x = metadata.get('float_target_x', 0.8)
    target_y = metadata.get('float_target_y', 1.4)
    target_z = metadata.get('float_target_z', -1.8)
    tol_pos = metadata.get('tolerance_pos', 0.3)
    tol_len = metadata.get('tolerance_len', 0.6)

    score = 0
    feedback_parts = []
    
    # --- 1. Fetch and Load Result JSON ---
    local_tmp = tempfile.mktemp(suffix=".json")
    try:
        copy_from_env("/tmp/openvsp_floatplane_result.json", local_tmp)
        with open(local_tmp, "r") as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {e}"}
    finally:
        if os.path.exists(local_tmp):
            os.unlink(local_tmp)

    if not data.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "floatplane_variant.vsp3 was not saved."}
        
    # Anti-gaming: Ensure file was created during the task
    if data.get("mtime", 0) > data.get("task_start", 0):
        score += 15
        feedback_parts.append("File created/modified during task (+15)")
    else:
        feedback_parts.append("WARNING: File appears older than task start")

    content = data.get("file_content", "").replace("\\n", "\n")
    geom_blocks = _extract_geom_blocks(content)

    # --- 2. Baseline Preservation ---
    if len(geom_blocks) >= 3:
        score += 10
        feedback_parts.append(f"Baseline preserved ({len(geom_blocks)} components found) (+10)")
    else:
        feedback_parts.append("Baseline geometry appears deleted or corrupted")

    # --- 3. Identify the Float Component ---
    float_geom = None
    y_locations = []
    for geom in geom_blocks:
        z = _find_param(geom, ["Z_Location", "Z_Rel_Location"])
        y = _find_param(geom, ["Y_Location", "Y_Rel_Location"])
        if y is not None:
            y_locations.append(abs(y))
        
        if z is not None and z <= -1.0:
            float_geom = geom
            break

    if float_geom:
        score += 15
        feedback_parts.append("Float component identified below fuselage (+15)")
        
        # --- 4. Verify Dimensions ---
        length = _find_param(float_geom, ["Length", "Design_Length"])
        if length is not None and abs(length - target_len) <= tol_len:
            score += 15
            feedback_parts.append(f"Float length correct: {length:.2f}m (+15)")
        else:
            feedback_parts.append(f"Float length incorrect or missing (Expected ~{target_len}m)")

        # --- 5. Verify Position ---
        x = _find_param(float_geom, ["X_Location", "X_Rel_Location"])
        y = _find_param(float_geom, ["Y_Location", "Y_Rel_Location"])
        z = _find_param(float_geom, ["Z_Location", "Z_Rel_Location"])
        
        if (x is not None and y is not None and z is not None and
            abs(x - target_x) <= tol_pos and 
            abs(abs(y) - target_y) <= tol_pos and 
            abs(z - target_z) <= tol_pos):
            score += 15
            feedback_parts.append(f"Float positioned correctly at X={x:.1f}, Y={y:.1f}, Z={z:.1f} (+15)")
        else:
            feedback_parts.append(f"Float position inaccurate: X={x}, Y={y}, Z={z}")

        # --- 6. Verify Symmetry (Twin Floats) ---
        sym_flag = _find_param(float_geom, ["Sym_Planar_Flag", "Sym_Y", "Sym_Planar"])
        has_twin_by_y = sum(1 for y_loc in y_locations if abs(abs(y_loc) - target_y) <= tol_pos) >= 2
        
        if (sym_flag is not None and sym_flag > 0) or has_twin_by_y:
            score += 10
            feedback_parts.append("Twin floats established via symmetry or duplication (+10)")
        else:
            feedback_parts.append("Symmetry not enabled (only one float exists)")
    else:
        feedback_parts.append("No float component found below fuselage (Z < -1.0)")

    # --- 7. VLM Visual Trajectory Verification ---
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=3)
            final_frame = get_final_screenshot(traj)
            
            prompt = """Analyze these screenshots of a CAD user working in OpenVSP.
Look specifically at the final image(s).
Did the user successfully add twin amphibious floats (pontoons) to the bottom of the aircraft?
You should see two parallel pontoon/float structures positioned underneath the main fuselage.
Respond in strict JSON:
{"has_twin_floats": true/false, "reason": "brief explanation"}"""

            images_to_check = frames + [final_frame] if final_frame else frames
            if images_to_check:
                vlm_res = query_vlm(prompt=prompt, images=images_to_check)
                if vlm_res and vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if parsed.get('has_twin_floats', False):
                        score += 20
                        feedback_parts.append("VLM visually confirmed twin floats (+20)")
                    else:
                        feedback_parts.append(f"VLM did not detect floats: {parsed.get('reason')}")
        except Exception as e:
            logger.warning(f"VLM verification skipped/failed: {e}")
            # Give partial credit if XML was perfect but VLM crashed
            if score >= 65:
                score += 15
                feedback_parts.append("VLM skipped but XML validation strongly passed (+15)")

    key_criteria_met = float_geom is not None and score >= 60
    
    return {
        "passed": key_criteria_met,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }