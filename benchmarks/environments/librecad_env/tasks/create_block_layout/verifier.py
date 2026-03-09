#!/usr/bin/env python3
"""
Verifier for create_block_layout task in LibreCAD.
Parses the output DXF file to verify block definition, geometry, and grid insertions.
"""

import json
import os
import math
import tempfile
import logging
import sys

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import ezdxf (available in the librecad_env)
try:
    import ezdxf
    EZDXF_AVAILABLE = True
except ImportError:
    logger.error("ezdxf module not found. Verification capabilities limited.")
    EZDXF_AVAILABLE = False

def verify_create_block_layout(traj, env_info, task_info):
    """
    Verify the LibreCAD block layout task.
    
    Criteria:
    1. Valid DXF file created during task (10 pts)
    2. Layer 'FIXTURES' exists (10 pts)
    3. Block 'DISPLAY_FIXTURE' defined (20 pts)
    4. Block contains correct geometry (Rect + Circle) (25 pts)
    5. Block insertions present (6 instances) (20 pts)
    6. Insertions are on correct layer (10 pts)
    7. Grid positions are approximately correct (5 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Initialize scoring
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Get result metadata
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)

    # Check file existence and timestamp
    output_exists = task_result.get("output_exists", False)
    created_during_task = task_result.get("file_created_during_task", False)
    output_path = task_result.get("output_path", "")
    
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Output DXF file not found."}
    
    if not created_during_task:
        feedback_parts.append("WARNING: File timestamp suggests it was not created during this task session.")
        # We penalize but continue checking in case the timestamp logic was flaky (e.g. system time drift)
        # However, strictly this should be 0. We'll deduct points later.
    else:
        score += 10
        feedback_parts.append("Valid output file created.")

    # 2. Parse DXF file
    if not EZDXF_AVAILABLE:
        return {"passed": False, "score": score, "feedback": "Verification failed: ezdxf library missing in environment."}

    temp_dxf = tempfile.NamedTemporaryFile(delete=False, suffix='.dxf')
    doc = None
    try:
        copy_from_env(output_path, temp_dxf.name)
        # Load DXF (ignore minor errors)
        doc = ezdxf.readfile(temp_dxf.name)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to parse DXF file: {str(e)}"}
    finally:
        if os.path.exists(temp_dxf.name):
            os.unlink(temp_dxf.name)

    if not doc:
        return {"passed": False, "score": score, "feedback": "DXF file could not be read."}

    # CRITERION 2: Layer 'FIXTURES' exists (10 pts)
    layer_names = [layer.dxf.name.upper() for layer in doc.layers]
    if "FIXTURES" in layer_names:
        score += 10
        feedback_parts.append("Layer 'FIXTURES' found.")
    else:
        feedback_parts.append(f"Layer 'FIXTURES' missing. Found: {layer_names[:5]}...")

    # CRITERION 3: Block 'DISPLAY_FIXTURE' defined (20 pts)
    block_name_target = "DISPLAY_FIXTURE"
    block_def = None
    
    # Search blocks (case-insensitive)
    for name in doc.blocks.names():
        if name.upper() == block_name_target:
            block_def = doc.blocks[name]
            break
            
    if block_def:
        score += 20
        feedback_parts.append(f"Block '{block_name_target}' definition found.")
        
        # CRITERION 4: Block Geometry (25 pts)
        # Expecting Rectangle (4 lines or polyline) and Circle
        lines = list(block_def.query("LINE"))
        polylines = list(block_def.query("LWPOLYLINE")) + list(block_def.query("POLYLINE"))
        circles = list(block_def.query("CIRCLE"))
        
        has_rect = False
        # Check for rectangle geometry
        if len(lines) >= 4:
            has_rect = True # Loose check: 4 lines
        for pl in polylines:
            # Check for closed polyline or enough points
            if pl.is_closed or len(list(pl.points())) >= 4:
                has_rect = True
        
        has_circle = len(circles) >= 1
        
        if has_rect and has_circle:
            score += 25
            feedback_parts.append("Block geometry correct (Rectangle + Circle).")
        elif has_rect:
            score += 15
            feedback_parts.append("Block geometry partial: Rectangle found, Circle missing.")
        elif has_circle:
            score += 10
            feedback_parts.append("Block geometry partial: Circle found, Rectangle missing.")
        else:
            feedback_parts.append("Block geometry empty or incorrect.")
            
    else:
        feedback_parts.append(f"Block '{block_name_target}' NOT defined.")

    # CRITERION 5: Block Insertions (20 pts)
    msp = doc.modelspace()
    inserts = []
    for entity in msp:
        if entity.dxftype() == "INSERT":
            if entity.dxf.name.upper() == block_name_target:
                inserts.append(entity)
    
    insert_count = len(inserts)
    if insert_count >= 6:
        score += 20
        feedback_parts.append(f"Found {insert_count} block insertions (Target: 6).")
    elif insert_count >= 1:
        score += 10
        feedback_parts.append(f"Found {insert_count} block insertions (Target: 6). Partial credit.")
    else:
        feedback_parts.append("No block insertions found.")

    # CRITERION 6: Insertions on FIXTURES layer (10 pts)
    if insert_count > 0:
        inserts_on_layer = sum(1 for i in inserts if i.dxf.layer.upper() == "FIXTURES")
        if inserts_on_layer == insert_count:
            score += 10
            feedback_parts.append("All insertions are on 'FIXTURES' layer.")
        elif inserts_on_layer > 0:
            score += 5
            feedback_parts.append(f"{inserts_on_layer}/{insert_count} insertions on correct layer.")
        else:
            feedback_parts.append("Insertions are on wrong layer.")

    # CRITERION 7: Grid Positions (5 pts)
    # Target grid:
    # (1000, 1000), (3500, 1000), (6000, 1000)
    # (1000, 3000), (3500, 3000), (6000, 3000)
    expected_positions = [
        (1000, 1000), (3500, 1000), (6000, 1000),
        (1000, 3000), (3500, 3000), (6000, 3000)
    ]
    tolerance = 300 # Allow some manual placement drift
    
    matched_positions = 0
    if insert_count > 0:
        actual_positions = [(i.dxf.insert.x, i.dxf.insert.y) for i in inserts]
        
        for tx, ty in expected_positions:
            for ax, ay in actual_positions:
                dist = math.sqrt((tx - ax)**2 + (ty - ay)**2)
                if dist < tolerance:
                    matched_positions += 1
                    break
        
        if matched_positions >= 5: # Allow 1 miss
            score += 5
            feedback_parts.append("Grid arrangement matches expected pattern.")
        else:
            feedback_parts.append(f"Grid arrangement mismatched. Matched {matched_positions}/6 positions.")

    # Final result
    passed = score >= 60 and block_def is not None and insert_count >= 4
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }