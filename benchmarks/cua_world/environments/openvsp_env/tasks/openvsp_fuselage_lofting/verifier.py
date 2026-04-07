#!/usr/bin/env python3
"""
Verifier for openvsp_fuselage_lofting task.

Checks that the agent created a multi-section fuselage and a wing:
  1. File exists and is valid XML (8 pts)
  2. FuseGeom component present (12 pts)
  3. >= 5 cross sections configured in fuselage (12 pts)
  4. Fuselage length in range [6.0, 11.0] m (13 pts)
  5. Max XSec width in range [0.60, 1.30] m (13 pts)
  6. Max XSec height in range [0.70, 1.40] m (10 pts)
  7. At least one circular XSec found (7 pts)
  8. WingGeom component present (10 pts)
  9. Wing span in range [11.0, 19.0] m (10 pts)
  10. Saved after task start time (anti-gaming) (5 pts)

Pass threshold: 55 points.
"""

import json
import os
import re
import tempfile
import xml.etree.ElementTree as ET


def _get_component_blocks(content: str, comp_type: str) -> list[str]:
    """Extract full XML string blocks for a specific component type."""
    pattern = rf'<{comp_type}\b.*?</{comp_type}>'
    return re.findall(pattern, content, flags=re.DOTALL | re.IGNORECASE)


def _find_param_values(content: str, tags: list[str]) -> list[float]:
    """Find float values assigned to the listed parameters within a string."""
    vals = []
    for tag in tags:
        # Match <TagName ... Value="1.23" ... >
        pattern = rf'<{tag}\b[^>]*?Value="([^"]+)"'
        for m in re.finditer(pattern, content, flags=re.IGNORECASE):
            try:
                vals.append(float(m.group(1)))
            except ValueError:
                pass
    return vals


def _check_circular(fuse_block: str) -> bool:
    """Check if any cross-section in the fuselage block is essentially circular."""
    if 'Circle' in fuse_block or 'Circle_Diameter' in fuse_block:
        return True
    
    # Check width vs height for all cross sections to see if they match (ellipses set as circles)
    xsecs = re.split(r'<XSec\b', fuse_block, flags=re.IGNORECASE)
    for xsec in xsecs[1:]:
        ws = _find_param_values(xsec, ['Width', 'Ellipse_Width'])
        hs = _find_param_values(xsec, ['Height', 'Ellipse_Height'])
        if ws and hs:
            # Check if width and height are close and not near-zero
            if abs(ws[0] - hs[0]) < 0.05 and ws[0] > 0.10:
                return True
    return False


def verify_openvsp_fuselage_lofting(trajectory, env_info, task_info):
    result_file = task_info.get("metadata", {}).get(
        "result_file", "/tmp/openvsp_fuselage_lofting_result.json"
    )

    local_tmp = tempfile.mktemp(suffix=".json")
    try:
        env_info["copy_from_env"](result_file, local_tmp)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result file not found — export script may not have run: {e}",
        }

    with open(local_tmp, "r") as f:
        data = json.load(f)
    os.unlink(local_tmp)

    score = 0
    feedback_parts = []

    # --- Check 1: File Exists & Valid XML (8 pts) ---
    if not data.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "male_uav.vsp3 not found at /home/ga/Documents/OpenVSP/male_uav.vsp3.",
        }

    content = data.get("file_content", "")
    content = content.replace("\\n", "\n").replace("\\t", "\t")

    try:
        ET.fromstring(content)
        score += 8
        feedback_parts.append("File is valid XML (+8).")
    except ET.ParseError as e:
        feedback_parts.append(f"File is not valid XML: {e} (+0).")

    # --- Check 10: Anti-gaming Timestamp (5 pts) ---
    mtime = data.get("mtime", 0)
    task_start = data.get("task_start", 0)
    if mtime >= task_start and task_start > 0:
        score += 5
        feedback_parts.append("File created/modified during task (+5).")
    else:
        feedback_parts.append("File modification time predates task start (+0).")

    # --- Fuselage Component Checks ---
    fuse_blocks = _get_component_blocks(content, 'FuseGeom')
    if not fuse_blocks:
        fuse_blocks = _get_component_blocks(content, 'FuselageGeom')  # fallback generic name
    
    if fuse_blocks:
        score += 12
        feedback_parts.append("FuseGeom component found (+12).")
        
        # Analyze the most complex fuselage (if they accidentally made duplicates)
        best_fuse = max(fuse_blocks, key=lambda b: len(re.findall(r'<XSec\b', b, re.IGNORECASE)))
        
        # Check 3: XSec count (12 pts)
        xsec_count = len(re.findall(r'<XSec\b', best_fuse, re.IGNORECASE))
        if xsec_count >= 5:
            score += 12
            feedback_parts.append(f"Found {xsec_count} cross-sections in Fuselage (+12).")
        elif xsec_count > 0:
            score += 6
            feedback_parts.append(f"Found {xsec_count} cross-sections (needed 5+) (+6).")
            
        # Check 4: Fuselage Length (13 pts)
        lengths = _find_param_values(best_fuse, ['Length', 'Design_Length'])
        fuse_len = max(lengths) if lengths else 0.0
        if 6.0 <= fuse_len <= 11.0:
            score += 13
            feedback_parts.append(f"Fuselage length {fuse_len:.2f} m is in range [6.0, 11.0] (+13).")
        else:
            feedback_parts.append(f"Fuselage length {fuse_len:.2f} m is outside target range (+0).")
            
        # Check 5 & 6: Max Width and Height (13 pts & 10 pts)
        widths = _find_param_values(best_fuse, ['Width', 'Ellipse_Width', 'Circle_Diameter'])
        heights = _find_param_values(best_fuse, ['Height', 'Ellipse_Height', 'Circle_Diameter'])
        
        max_w = max(widths) if widths else 0.0
        max_h = max(heights) if heights else 0.0
        
        if 0.60 <= max_w <= 1.30:
            score += 13
            feedback_parts.append(f"Max fuselage width {max_w:.2f} m is in range [0.60, 1.30] (+13).")
        else:
            feedback_parts.append(f"Max fuselage width {max_w:.2f} m outside target range (+0).")
            
        if 0.70 <= max_h <= 1.40:
            score += 10
            feedback_parts.append(f"Max fuselage height {max_h:.2f} m is in range [0.70, 1.40] (+10).")
        else:
            feedback_parts.append(f"Max fuselage height {max_h:.2f} m outside target range (+0).")
            
        # Check 7: Circular XSec Presence (7 pts)
        if _check_circular(best_fuse):
            score += 7
            feedback_parts.append("Circular cross-section detected (+7).")
        else:
            feedback_parts.append("No circular cross-section configured (+0).")
            
    else:
        feedback_parts.append("No Fuselage component found (+0).")

    # --- Wing Component Checks ---
    wing_blocks = _get_component_blocks(content, 'WingGeom')
    if wing_blocks:
        score += 10
        feedback_parts.append("WingGeom component found (+10).")
        best_wing = max(wing_blocks, key=len)
        
        # Check 9: Wing span (10 pts)
        spans = _find_param_values(best_wing, ['TotalSpan', 'Span'])
        span_val = max(spans) if spans else 0.0
        
        if 11.0 <= span_val <= 19.0:
            score += 10
            feedback_parts.append(f"Wing span {span_val:.2f} m is in range [11.0, 19.0] (+10).")
        else:
            feedback_parts.append(f"Wing span {span_val:.2f} m outside target range (+0).")
    else:
        feedback_parts.append("No Wing component found (+0).")

    # Final Pass Evaluation
    passed = score >= 55
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }