#!/usr/bin/env python3
"""
Verifier for reflected_ceiling_plan task.
Verifies DXF structure, layer existence/colors, and geometric entities.
"""

import json
import os
import sys
import tempfile
import logging
import math

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def verify_reflected_ceiling_plan(traj, env_info, task_info):
    """
    Verify the Reflected Ceiling Plan task.
    
    Criteria:
    1. File exists and is valid DXF (10 pts)
    2. Layers exist with correct names and colors (20 pts)
    3. Room outline is correct dimensions (20 pts)
    4. Ceiling grid is present (20 pts)
    5. Lighting fixtures are correct (30 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    score = 0
    feedback_parts = []
    
    # Retrieve Metadata
    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Documents/LibreCAD/reflected_ceiling_plan.dxf')
    
    # 1. Get Result JSON
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)

    # 2. Check File Existence & Anti-Gaming
    if not task_result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
        
    if not task_result.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "File exists but was not modified during the task."}
        
    score += 10
    feedback_parts.append("DXF file created.")

    # 3. Retrieve and Parse DXF
    temp_dxf = tempfile.NamedTemporaryFile(delete=False, suffix='.dxf')
    try:
        copy_from_env(expected_path, temp_dxf.name)
        
        # Try importing ezdxf
        try:
            import ezdxf
        except ImportError:
            # Fallback if ezdxf is missing (though env setup implies it's there)
            return {"passed": False, "score": score, "feedback": "Verification failed: ezdxf library missing."}

        try:
            doc = ezdxf.readfile(temp_dxf.name)
            msp = doc.modelspace()
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Invalid DXF file: {e}"}

        # --- CRITERION 2: LAYERS (20 pts) ---
        layers = doc.layers
        layer_specs = {
            "ROOM": 7,        # White/Black
            "CEILING-GRID": 8, # Gray
            "LIGHTING": 2     # Yellow
        }
        
        layer_score = 0
        for name, color in layer_specs.items():
            if name in layers:
                layer_score += 3
                # Check color (allow some flexibility if close, but spec was exact)
                l = layers.get(name)
                if l.dxf.color == color:
                    layer_score += 3.66  # (20 total / 3 layers = ~6.66 per layer)
                else:
                    feedback_parts.append(f"Layer '{name}' color mismatch (Expected {color}, got {l.dxf.color}).")
            else:
                feedback_parts.append(f"Layer '{name}' missing.")
        
        # Cap and add layer score
        layer_score = min(20, int(layer_score))
        score += layer_score
        if layer_score == 20:
            feedback_parts.append("All layers correct.")

        # --- CRITERION 3: ROOM OUTLINE (20 pts) ---
        # Look for lines/polylines on ROOM layer
        room_entities = msp.query('LINE LWPOLYLINE[layer=="ROOM"]')
        room_correct = False
        
        # Calculate bounding box of ROOM layer entities
        if len(room_entities) > 0:
            bbox = ezdxf.bbox.extents(room_entities)
            width = bbox.extmax.x - bbox.extmin.x
            height = bbox.extmax.y - bbox.extmin.y
            
            # Allow small tolerance
            if abs(width - 6000) < 50 and abs(height - 4800) < 50:
                room_correct = True
            else:
                feedback_parts.append(f"Room dimensions incorrect: {width:.0f}x{height:.0f} (Expected 6000x4800).")
        else:
            feedback_parts.append("No geometry found on ROOM layer.")
            
        if room_correct:
            score += 20
            feedback_parts.append("Room outline correct.")

        # --- CRITERION 4: CEILING GRID (20 pts) ---
        grid_entities = msp.query('LINE[layer=="CEILING-GRID"]')
        # Expecting vertical lines (9) + horizontal lines (7) = 16 lines roughly
        if len(grid_entities) >= 10:
            score += 20
            feedback_parts.append("Ceiling grid present.")
        elif len(grid_entities) > 0:
            score += 10
            feedback_parts.append("Partial ceiling grid found.")
        else:
            feedback_parts.append("No ceiling grid found.")

        # --- CRITERION 5: LIGHTING FIXTURES (30 pts) ---
        light_entities = msp.query('LINE LWPOLYLINE[layer=="LIGHTING"]')
        
        # We expect 6 fixtures. Each fixture is a square (4 lines or 1 polyline) + 2 diagonals.
        # Minimal entities: 6 * (1 polyline + 2 lines) = 18 entities OR 6 * 6 lines = 36 lines.
        # Let's check for density around target coordinates.
        
        targets = metadata.get('fixture_coords', [])
        found_fixtures = 0
        
        # Extract all points from lighting layer
        points = []
        for e in light_entities:
            if e.dxftype() == 'LINE':
                points.append(e.dxf.start)
                points.append(e.dxf.end)
            elif e.dxftype() == 'LWPOLYLINE':
                points.extend(e.points())
        
        # Check targets
        for tx, ty in targets:
            # Check if there are points within 450mm radius (sq is 600 wide, radius ~424)
            # We look for geometry centered roughly here
            nearby_points = [p for p in points if math.hypot(p[0]-tx, p[1]-ty) < 500]
            if len(nearby_points) >= 4: # At least a square's worth of points
                found_fixtures += 1
        
        fixture_points = min(30, found_fixtures * 5)
        score += fixture_points
        
        if found_fixtures >= 6:
            feedback_parts.append("All lighting fixtures positioned correctly.")
        else:
            feedback_parts.append(f"Found {found_fixtures}/6 lighting fixtures.")

    except Exception as e:
        logger.error(f"DXF verification error: {e}")
        feedback_parts.append(f"Verification error: {e}")
    finally:
        if os.path.exists(temp_dxf.name):
            os.unlink(temp_dxf.name)

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts)
    }