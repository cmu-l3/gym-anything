#!/usr/bin/env python3
"""
Verifier for openvsp_mdao_desvar_setup task.

Verifies that the agent correctly assigned parameter bounds in the OpenVSP model.
Since OpenVSP v3 saves design parameters with `LowerBound` and `UpperBound` attributes
in its XML (.vsp3 file), we can parse the XML tree to verify the state.

Scoring (100 points total):
  - Wing Span bounds [55.0, 65.0] (15 pts)
  - Wing Root Chord bounds [10.0, 14.0] (15 pts)
  - Wing Tip Chord bounds [2.0, 4.0] (15 pts)
  - Tail Span bounds [16.0, 22.0] (15 pts)
  - Tail Root Chord bounds [3.5, 5.5] (15 pts)
  - Summary Report contains all expected numbers (15 pts)
  - VLM Trajectory Verification: Agent actually used OpenVSP UI to edit bounds (10 pts)

Pass Threshold: 60 pts
"""

import json
import os
import re
import xml.etree.ElementTree as ET
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add path for gym_anything
import sys
sys.path.insert(0, "/workspace")
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot


def _parse_vsp_bounds(xml_content: str):
    """
    Parses OpenVSP XML and extracts all parameter bounds organized by component type.
    Returns: {"wing": {tag_name: (lower, upper)}, "tail": {tag_name: (lower, upper)}}
    """
    wing_bounds = {}
    tail_bounds = {}
    
    try:
        root = ET.fromstring(xml_content)
        for geom in root.findall('.//Geom'):
            name_el = geom.find('Name')
            if name_el is None or not name_el.text:
                continue
                
            geom_name = name_el.text.lower()
            target_dict = None
            if 'wing' in geom_name:
                target_dict = wing_bounds
            elif 'tail' in geom_name or 'horz' in geom_name:
                target_dict = tail_bounds
                
            if target_dict is not None:
                for el in geom.iter():
                    tag = el.tag.lower()
                    lb = el.get('LowerBound')
                    ub = el.get('UpperBound')
                    if lb is not None and ub is not None:
                        try:
                            target_dict[tag] = (float(lb), float(ub))
                        except ValueError:
                            pass
    except ET.ParseError as e:
        logger.error(f"Failed to parse vsp3 XML: {e}")
        
    return wing_bounds, tail_bounds


def _check_bounds(target_dict: dict, keyword: str, expected_bounds: tuple) -> bool:
    """Checks if a parameter containing `keyword` in its tag has the expected bounds."""
    for tag, bounds in target_dict.items():
        if keyword in tag:
            # Check with a small floating point tolerance
            if abs(bounds[0] - expected_bounds[0]) < 1e-4 and abs(bounds[1] - expected_bounds[1]) < 1e-4:
                return True
    return False


def verify_openvsp_mdao_desvar_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Use a temporary file to copy the JSON result from the container
    local_tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json").name
    try:
        copy_from_env("/tmp/openvsp_mdao_desvar_setup_result.json", local_tmp)
        with open(local_tmp, "r") as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(local_tmp):
            os.unlink(local_tmp)

    score = 0
    feedback_parts = []
    
    # 1. Parse XML Model (75 pts total)
    model_exists = data.get("model_exists", False)
    model_content = data.get("model_content", "")
    
    if not model_exists:
        feedback_parts.append("❌ Target model eCRM001_mdao.vsp3 not found.")
    else:
        feedback_parts.append("✅ Target model saved.")
        wing_bounds, tail_bounds = _parse_vsp_bounds(model_content)
        
        # Wing Span
        if _check_bounds(wing_bounds, "span", (55.0, 65.0)):
            score += 15
            feedback_parts.append("✅ Wing Span bounds correct (+15)")
        else:
            feedback_parts.append("❌ Wing Span bounds incorrect")
            
        # Wing Root Chord
        if _check_bounds(wing_bounds, "root_chord", (10.0, 14.0)) or _check_bounds(wing_bounds, "rootchord", (10.0, 14.0)):
            score += 15
            feedback_parts.append("✅ Wing Root Chord bounds correct (+15)")
        else:
            feedback_parts.append("❌ Wing Root Chord bounds incorrect")
            
        # Wing Tip Chord
        if _check_bounds(wing_bounds, "tip_chord", (2.0, 4.0)) or _check_bounds(wing_bounds, "tipchord", (2.0, 4.0)):
            score += 15
            feedback_parts.append("✅ Wing Tip Chord bounds correct (+15)")
        else:
            feedback_parts.append("❌ Wing Tip Chord bounds incorrect")
            
        # Tail Span
        if _check_bounds(tail_bounds, "span", (16.0, 22.0)):
            score += 15
            feedback_parts.append("✅ Tail Span bounds correct (+15)")
        else:
            feedback_parts.append("❌ Tail Span bounds incorrect")
            
        # Tail Root Chord
        if _check_bounds(tail_bounds, "root_chord", (3.5, 5.5)) or _check_bounds(tail_bounds, "rootchord", (3.5, 5.5)):
            score += 15
            feedback_parts.append("✅ Tail Root Chord bounds correct (+15)")
        else:
            feedback_parts.append("❌ Tail Root Chord bounds incorrect")

    # 2. Check Report (15 pts)
    report_exists = data.get("report_exists", False)
    report_content = data.get("report_content", "")
    
    if report_exists:
        # Check if expected numerical values are in the text
        expected_nums = ["55", "65", "10", "14", "2", "4", "16", "22", "3.5", "5.5"]
        found_nums = []
        for n in expected_nums:
            if re.search(r'\b' + n + r'(?:\.0)?\b', report_content):
                found_nums.append(n)
                
        if len(found_nums) >= 8:
            score += 15
            feedback_parts.append("✅ Report contains all/most required bound values (+15)")
        elif len(found_nums) >= 4:
            score += 7
            feedback_parts.append("⚠️ Report contains some bound values (+7)")
        else:
            feedback_parts.append("❌ Report missing bound values")
    else:
        feedback_parts.append("❌ desvar_summary.txt report not found")

    # 3. VLM Trajectory Verification (10 pts)
    # Check if the agent actually used the OpenVSP UI to set bounds
    if query_vlm and traj:
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images:
            prompt = (
                "You are evaluating an agent using OpenVSP CAD software. "
                "Did the agent open the parameter editing windows, such as the 'Variable Manager', "
                "or modify the 'Lower' and 'Upper' bound fields in any of the component geometry tabs? "
                "Reply 'YES' if you see evidence of bound configuration fields or the Variable Manager window. "
                "Reply 'NO' otherwise."
            )
            try:
                vlm_resp = query_vlm(prompt=prompt, images=images)
                resp_text = vlm_resp.get("answer", "").upper()
                if "YES" in resp_text:
                    score += 10
                    feedback_parts.append("✅ VLM verified UI interaction for bounds (+10)")
                else:
                    feedback_parts.append("❌ VLM did not observe bound UI interactions")
            except Exception as e:
                logger.error(f"VLM check failed: {e}")
                feedback_parts.append("⚠️ VLM verification skipped due to error")

    # Determine pass/fail
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }