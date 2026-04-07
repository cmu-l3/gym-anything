#!/usr/bin/env python3
"""
Verifier for openvsp_twin_fuselage_conversion task.

Programmatically verifies that the agent correctly applied geometric transformations
and planform scaling to the OpenVSP model.

Checks performed on the XML (.vsp3) structure:
  1. Fuselage Y_Location == 14.0 and XZ Planar Symmetry Enabled
  2. Vertical Tail Y_Location == 14.0 and XZ Planar Symmetry Enabled
  3. Horizontal Tail Y_Location == 14.0, XZ Planar Symmetry Enabled, Span == 25.0
  4. Main Wing Span == 75.0, Root_Chord == 10.0 (Y_Location should remain ~0.0)

File modification timestamp is checked to prevent gaming with pre-existing files.
"""

import json
import os
import re
import tempfile


def _get_parm_value(comp_text: str, parm_name: str) -> float:
    """Extract a numeric parameter value from a component's XML block."""
    # Pattern 1: <Name>ParmName</Name> ... <Value>14.0</Value>
    m1 = re.search(rf'<Name>{parm_name}</Name>\s*<Value>([^<]+)</Value>', comp_text)
    if m1:
        try:
            return float(m1.group(1))
        except ValueError:
            pass
            
    # Pattern 2: <ParmName Value="14.0"/>
    m2 = re.search(rf'<{parm_name}\s+Value="([^"]+)"', comp_text)
    if m2:
        try:
            return float(m2.group(1))
        except ValueError:
            pass

    # Pattern 3: <ParmName>14.0</ParmName> (for flags)
    m3 = re.search(rf'<{parm_name}>([^<]+)</{parm_name}>', comp_text)
    if m3:
        try:
            return float(m3.group(1))
        except ValueError:
            pass

    return None


def _find_component(components: list, include_strs: list, exclude_strs: list = None) -> str:
    """Find a component block matching substrings in its <Name> field."""
    for comp in components:
        name_match = re.search(r'<Name>(.*?)</Name>', comp)
        if not name_match:
            continue
        name = name_match.group(1).lower()
        
        if any(inc in name for inc in include_strs):
            if exclude_strs and any(exc in name for exc in exclude_strs):
                continue
            return comp
    return None


def verify_openvsp_twin_fuselage_conversion(trajectory, env_info, task_info):
    result_file = "/tmp/openvsp_twin_fuselage_result.json"

    # Safely pull result file from VM
    local_tmp = tempfile.mktemp(suffix=".json")
    try:
        env_info["copy_from_env"](result_file, local_tmp)
        with open(local_tmp, "r") as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result file not found or corrupted: {e}"
        }
    finally:
        if os.path.exists(local_tmp):
            os.unlink(local_tmp)

    score = 0
    feedback_parts = []

    # --- Pre-check: File existence & timestamp anti-gaming ---
    if not data.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Target model twin_fuselage_launcher.vsp3 not found. Agent may not have saved correctly."
        }

    if data.get("mtime", 0) < data.get("task_start", 0):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Model file modification time is older than task start. Invalid submission."
        }

    content = data.get("file_content", "")
    score += 10
    feedback_parts.append("File exists and was modified during task (+10)")

    # Split into component blocks
    # <Component> ... </Component>
    components = re.findall(r'<Component>.*?</Component>', content, re.DOTALL)
    if not components:
        return {
            "passed": False,
            "score": 10,
            "feedback": "Valid file found, but no OpenVSP <Component> blocks detected in XML."
        }

    # Find the specific components based on eCRM-001 typical naming
    comp_fuse = _find_component(components, ["fuse", "body"])
    comp_vtail = _find_component(components, ["vertical", "v_tail", "vtail"])
    comp_htail = _find_component(components, ["horizontal", "h_tail", "htail"])
    comp_wing = _find_component(components, ["wing"], exclude_strs=["tail", "horizontal", "vertical"])

    # --- 1. Fuselage Checks (20 pts total) ---
    if comp_fuse:
        y_loc = _get_parm_value(comp_fuse, "Y_Location")
        sym = _get_parm_value(comp_fuse, "Sym_Planar_Flag")
        
        y_ok = y_loc is not None and abs(y_loc - 14.0) <= 0.5
        sym_ok = sym is not None and sym >= 1.0  # OpenVSP uses 1, 2, or 3 for enabled symmetry types
        
        if y_ok: score += 10
        if sym_ok: score += 10
        feedback_parts.append(f"Fuselage: Y={y_loc} ({'OK' if y_ok else 'FAIL'}), Sym={sym} ({'OK' if sym_ok else 'FAIL'})")
    else:
        feedback_parts.append("Fuselage component not found")

    # --- 2. Vertical Tail Checks (15 pts total) ---
    if comp_vtail:
        y_loc = _get_parm_value(comp_vtail, "Y_Location")
        sym = _get_parm_value(comp_vtail, "Sym_Planar_Flag")
        
        y_ok = y_loc is not None and abs(y_loc - 14.0) <= 0.5
        sym_ok = sym is not None and sym >= 1.0
        
        if y_ok and sym_ok: 
            score += 15
            feedback_parts.append(f"Vertical Tail correctly positioned and mirrored (+15)")
        else:
            feedback_parts.append(f"Vertical Tail: Y={y_loc}, Sym={sym}")
    else:
        feedback_parts.append("Vertical Tail component not found")

    # --- 3. Horizontal Tail Checks (15 pts total: 10 pos + 5 span) ---
    if comp_htail:
        y_loc = _get_parm_value(comp_htail, "Y_Location")
        sym = _get_parm_value(comp_htail, "Sym_Planar_Flag")
        span = _get_parm_value(comp_htail, "Span") or _get_parm_value(comp_htail, "TotalSpan") or _get_parm_value(comp_htail, "Total_Span")
        
        y_ok = y_loc is not None and abs(y_loc - 14.0) <= 0.5
        sym_ok = sym is not None and sym >= 1.0
        span_ok = span is not None and abs(span - 25.0) <= 1.0
        
        if y_ok and sym_ok: score += 10
        if span_ok: score += 5
        feedback_parts.append(f"Horizontal Tail: Y={y_loc}, Sym={sym}, Span={span}")
    else:
        feedback_parts.append("Horizontal Tail component not found")

    # --- 4. Main Wing Checks (30 pts total: 15 span + 15 chord) ---
    if comp_wing:
        span = _get_parm_value(comp_wing, "Span") or _get_parm_value(comp_wing, "TotalSpan") or _get_parm_value(comp_wing, "Total_Span")
        root_chord = _get_parm_value(comp_wing, "Root_Chord") or _get_parm_value(comp_wing, "RootChord")
        
        span_ok = span is not None and abs(span - 75.0) <= 2.0
        chord_ok = root_chord is not None and abs(root_chord - 10.0) <= 0.5
        
        if span_ok: 
            score += 15
            feedback_parts.append("Main Wing Span is ~75.0 (+15)")
        else:
            feedback_parts.append(f"Main Wing Span is {span} (Expected 75.0)")
            
        if chord_ok: 
            score += 15
            feedback_parts.append("Main Wing Root Chord is ~10.0 (+15)")
        else:
            feedback_parts.append(f"Main Wing Root Chord is {root_chord} (Expected 10.0)")
    else:
        feedback_parts.append("Main Wing component not found")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }