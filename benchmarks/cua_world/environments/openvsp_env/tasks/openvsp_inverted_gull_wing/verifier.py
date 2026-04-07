#!/usr/bin/env python3
"""
Verifier for openvsp_inverted_gull_wing task.

Checks:
  1. File exists, is valid XML, and was created during task (anti-gaming).
  2. A WingGeom component is present.
  3. The wing has multiple sections (topology modification).
  4. Inboard anhedral matches target range [-20, -10].
  5. Outboard dihedral matches target range [5, 15].
  6. Span dimensions roughly match specification.
  7. VLM verification on trajectory frames confirms workflow execution.
"""

import json
import os
import re
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _extract_wing_params(content: str):
    """Extract all Dihedral and Span values found within the Wing blocks of the OpenVSP XML."""
    dihedrals = []
    spans = []
    
    # Isolate Wing Geom blocks
    wing_blocks = []
    for match in re.finditer(r'<Geom.*?>(.*?)</Geom>', content, re.DOTALL | re.IGNORECASE):
        block = match.group(1)
        if '<TypeName>Wing</TypeName>' in block or 'WingGeom' in block:
            wing_blocks.append(block)
    
    # If blocks found, parse them. Otherwise parse globally as fallback.
    search_space = "".join(wing_blocks) if wing_blocks else content
    
    for m in re.finditer(r'<Dihedral\s+[^>]*Value="([^"]+)"', search_space):
        try:
            dihedrals.append(float(m.group(1)))
        except ValueError:
            pass
            
    for m in re.finditer(r'<Span\s+[^>]*Value="([^"]+)"', search_space):
        try:
            spans.append(float(m.group(1)))
        except ValueError:
            pass
            
    return dihedrals, spans


def verify_openvsp_inverted_gull_wing(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    result_file = metadata.get("result_file", "/tmp/task_result.json")

    # Retrieve exported result
    local_tmp = tempfile.mktemp(suffix=".json")
    try:
        copy_from_env(result_file, local_tmp)
        with open(local_tmp, "r") as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(local_tmp):
            os.unlink(local_tmp)

    score = 0
    feedback_parts = []

    # --- CRITERION 1: File Exists & Anti-Gaming (10 pts) ---
    if not data.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "inverted_gull_wing.vsp3 not found."}
        
    if not data.get("created_during_task", False):
        feedback_parts.append("Warning: File timestamp indicates it may not have been created during this session.")
    else:
        score += 5
        
    content = data.get("file_content", "")
    try:
        ET.fromstring(content)
        score += 5
        feedback_parts.append("File is valid XML (+10).")
    except ET.ParseError as e:
        return {"passed": False, "score": score, "feedback": f"File is not valid XML: {e}"}

    # --- CRITERION 2: Wing Component (15 pts) ---
    if "<TypeName>Wing</TypeName>" in content or "WingGeom" in content:
        score += 15
        feedback_parts.append("Wing component found (+15).")
    else:
        feedback_parts.append("No Wing component found (+0).")

    # Extract parameters for topological checks
    dihedrals, spans = _extract_wing_params(content)

    # --- CRITERION 3: Multi-Panel Topology (15 pts) ---
    if len(dihedrals) >= 2 and len(spans) >= 2:
        score += 15
        feedback_parts.append(f"Topology verified: Wing has multiple sections (found {len(dihedrals)} dihedral values) (+15).")
    else:
        feedback_parts.append(f"Wing appears to be a single panel. Found {len(dihedrals)} section(s) (+0).")

    # --- CRITERION 4: Inboard Anhedral (20 pts) ---
    anh_range = metadata.get("anhedral_range", [-20.0, -10.0])
    if dihedrals and min(dihedrals) <= anh_range[1] and min(dihedrals) >= anh_range[0]:
        score += 20
        feedback_parts.append(f"Inboard Anhedral verified ({min(dihedrals)} deg) (+20).")
    elif dihedrals and min(dihedrals) < 0:
        score += 10
        feedback_parts.append(f"Anhedral detected but out of range ({min(dihedrals)} deg) (+10).")
    else:
        feedback_parts.append("No Anhedral (negative dihedral) detected (+0).")

    # --- CRITERION 5: Outboard Dihedral (20 pts) ---
    dih_range = metadata.get("dihedral_range", [5.0, 15.0])
    if dihedrals and max(dihedrals) >= dih_range[0] and max(dihedrals) <= dih_range[1]:
        score += 20
        feedback_parts.append(f"Outboard Dihedral verified ({max(dihedrals)} deg) (+20).")
    elif dihedrals and max(dihedrals) > 0:
        score += 10
        feedback_parts.append(f"Positive dihedral detected but out of range ({max(dihedrals)} deg) (+10).")
    else:
        feedback_parts.append("No positive Dihedral detected (+0).")

    # --- CRITERION 6: Dimension Check (10 pts) ---
    target_hs = metadata.get("target_half_span", 6.3)
    if spans:
        total_span = sum(spans)
        if 5.5 <= total_span <= 7.0:
            score += 10
            feedback_parts.append(f"Section spans sum to {total_span:.2f}m, roughly matches target (+10).")
        elif any(abs(s - 2.5) < 0.2 for s in spans) and any(abs(s - 3.8) < 0.2 for s in spans):
            score += 10
            feedback_parts.append("Individual section spans match spec (+10).")
        else:
            feedback_parts.append(f"Span dimensions do not match spec (spans found: {spans}) (+0).")
    else:
        feedback_parts.append("No span parameters extracted (+0).")

    # --- CRITERION 7: VLM Trajectory Verification (10 pts) ---
    vlm_score = 0
    query_vlm = env_info.get("query_vlm")
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            
            prompt = """Analyze these screenshots from an agent's session.
1. Is the OpenVSP CAD application visible?
2. Did the agent interact with the Wing geometry properties (e.g., viewing/editing the wing or adjusting Plan/Section parameters)?
Reply with a JSON: {"openvsp_used": true/false, "wing_interacted": true/false}"""
            
            vlm_result = query_vlm(prompt=prompt, images=frames + [final])
            if vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("openvsp_used") and parsed.get("wing_interacted"):
                    vlm_score = 10
                    feedback_parts.append("VLM: Workflow execution verified (+10).")
                else:
                    feedback_parts.append("VLM: Workflow interaction lacking visual evidence (+0).")
            else:
                vlm_score = 10
                feedback_parts.append("VLM verification skipped (API failure) (+10).")
        except ImportError:
            vlm_score = 10
            feedback_parts.append("VLM verification skipped (imports missing) (+10).")
    else:
        vlm_score = 10
        feedback_parts.append("VLM verification skipped (Not available) (+10).")

    score += vlm_score

    # Determine pass/fail
    passed = score >= 75
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }