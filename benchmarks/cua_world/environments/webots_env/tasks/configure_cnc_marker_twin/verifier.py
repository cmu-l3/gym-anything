#!/usr/bin/env python3
import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def extract_block(content, def_name, node_type):
    """Safely extracts the contents of a Webots DEF block without nested brace assumptions."""
    pattern = re.compile(rf'DEF\s+{def_name}\s+{node_type}\s*\{{([^}}]*)\}}', re.DOTALL)
    m = pattern.search(content)
    return m.group(1) if m else None

def get_field_val(block, field_name):
    """Extracts a numeric parameter field from a node block."""
    m = re.search(rf'{field_name}\s+([\d.\-]+)', block)
    return float(m.group(1)) if m else None

def get_field_str(block, field_name):
    """Extracts a string or multi-component line from a node block."""
    m = re.search(rf'{field_name}\s+(.+?)(?=\n|$)', block)
    return m.group(1).strip() if m else None

def parse_color(color_str):
    """Converts a space-separated RGB string to a float list."""
    if not color_str:
        return []
    try:
        return [float(p) for p in color_str.split()]
    except Exception:
        return []

def verify_configure_cnc_marker_twin(traj, env_info, task_info):
    """
    Verifies that the CNC digital twin linear joints and pen node are correctly
    configured to physical machine specs and saved to the expected path.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve initial export result
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

    if not result.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Target file /home/ga/Desktop/cnc_digital_twin.wbt was not found. Save using File > Save World As."
        }

    # Retrieve the saved WBT file to parse settings
    wbt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
    wbt_file.close()
    wbt_content = ""
    try:
        copy_from_env("/home/ga/Desktop/cnc_digital_twin.wbt", wbt_file.name)
        with open(wbt_file.name, 'r', errors='replace') as f:
            wbt_content = f.read()
    except Exception as e:
        logger.error(f"Failed to read WBT file: {e}")
    finally:
        if os.path.exists(wbt_file.name):
            os.unlink(wbt_file.name)

    score = 10
    feedback_parts = ["File created"]

    # 1. Verify X-Axis Limits (0.0 to 0.4)
    block_x = extract_block(wbt_content, 'X_LIMITS', 'JointParameters')
    if block_x is not None:
        min_x = get_field_val(block_x, 'minStop')
        max_x = get_field_val(block_x, 'maxStop')
        
        # In Webots, 0.0 is the default and omitted from saves
        if min_x is None: min_x = 0.0
        if max_x is None: max_x = 0.0

        if min_x == 0.0 and max_x == 0.4:
            score += 20
            feedback_parts.append("X limits correct")
        else:
            feedback_parts.append(f"X limits wrong (min:{min_x}, max:{max_x})")
    else:
        feedback_parts.append("DEF X_LIMITS block not found")

    # 2. Verify Y-Axis Limits (0.0 to 0.3)
    block_y = extract_block(wbt_content, 'Y_LIMITS', 'JointParameters')
    if block_y is not None:
        min_y = get_field_val(block_y, 'minStop')
        max_y = get_field_val(block_y, 'maxStop')
        
        if min_y is None: min_y = 0.0
        if max_y is None: max_y = 0.0

        if min_y == 0.0 and max_y == 0.3:
            score += 20
            feedback_parts.append("Y limits correct")
        else:
            feedback_parts.append(f"Y limits wrong (min:{min_y}, max:{max_y})")
    else:
        feedback_parts.append("DEF Y_LIMITS block not found")

    # 3. Verify Marking Pen (write=TRUE, inkColor=1 0 0, leadSize=0.002)
    block_pen = extract_block(wbt_content, 'MARKING_PEN', 'Pen')
    if block_pen is not None:
        # Check write flag (Default is TRUE, might be omitted)
        write_val = get_field_str(block_pen, 'write')
        if write_val is None: write_val = 'TRUE'
        
        if write_val == 'TRUE':
            score += 15
            feedback_parts.append("Pen write=TRUE")
        else:
            feedback_parts.append(f"Pen write={write_val}")

        # Check ink color (Must be pure red, default is white)
        ink_color_str = get_field_str(block_pen, 'inkColor')
        if ink_color_str is None: ink_color_str = '1 1 1'
        
        color_arr = parse_color(ink_color_str)
        if len(color_arr) >= 3 and color_arr[0] == 1.0 and color_arr[1] == 0.0 and color_arr[2] == 0.0:
            score += 20
            feedback_parts.append("Pen color correct")
        else:
            feedback_parts.append(f"Pen color wrong ({ink_color_str})")

        # Check lead size (Default is 0.002, might be omitted)
        lead_size = get_field_val(block_pen, 'leadSize')
        if lead_size is None: lead_size = 0.002
        
        if lead_size == 0.002:
            score += 15
            feedback_parts.append("Pen leadSize correct")
        else:
            feedback_parts.append(f"Pen leadSize wrong ({lead_size})")
    else:
        feedback_parts.append("DEF MARKING_PEN block not found")

    passed = (score >= 70)
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }