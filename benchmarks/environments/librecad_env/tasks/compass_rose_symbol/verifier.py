#!/usr/bin/env python3
"""
Verifier for compass_rose_symbol task.

Verification Strategy:
1. Programmatic DXF Parsing (Primary):
   - Uses `ezdxf` to parse the output file.
   - Checks for specific geometric entities (circles, lines) with correct coordinates.
   - Verifies layer assignment.
2. Anti-gaming:
   - Checks file modification timestamps.
   - Checks file size.
3. VLM Verification (Supplementary):
   - Checks visual appearance for radial symmetry and compass shape.
"""

import json
import os
import math
import tempfile
import logging
from typing import Dict, Any, List, Tuple

# Import VLM utils provided by framework
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames
except ImportError:
    # Mock for local testing
    def query_vlm(*args, **kwargs): return {"success": False}
    def get_final_screenshot(*args): return None
    def sample_trajectory_frames(*args, **kwargs): return []

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compass_rose_symbol(traj, env_info, task_info):
    """
    Verify the compass rose drawing.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_layer = metadata.get('layer_name', 'COMPASS_ROSE')
    tol = metadata.get('tolerance_units', 3.0)

    score = 0
    max_score = 100
    feedback_parts = []
    
    # ================================================================
    # 1. Retrieve Task Result JSON
    # ================================================================
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # ================================================================
    # 2. Check File Existence & Integrity (Anti-gaming)
    # ================================================================
    if not task_result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output DXF file not found"}
    
    if not task_result.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "File was not modified during the task (anti-gaming check failed)"}

    if task_result.get('output_size_bytes', 0) < 500:
        return {"passed": False, "score": 0, "feedback": "File is too small to be a valid DXF drawing"}

    score += 8 # Valid file exists
    feedback_parts.append("Valid DXF file found")

    # ================================================================
    # 3. Retrieve and Parse DXF File
    # ================================================================
    temp_dxf = tempfile.NamedTemporaryFile(delete=False, suffix='.dxf')
    try:
        copy_from_env(task_result['output_path'], temp_dxf.name)
        
        # We need ezdxf installed in the verifier environment (host side)
        # If not available, we can't perform geometric checks
        try:
            import ezdxf
            doc = ezdxf.readfile(temp_dxf.name)
            msp = doc.modelspace()
            entities = list(msp)
        except ImportError:
            return {"passed": False, "score": score, "feedback": "Verifier Error: ezdxf library not installed on host"}
        except Exception as e:
             return {"passed": False, "score": score, "feedback": f"Failed to parse DXF file: {e}"}

    finally:
        if os.path.exists(temp_dxf.name):
            os.unlink(temp_dxf.name)

    # ================================================================
    # 4. Geometric Verification
    # ================================================================
    
    # Helper geometry functions
    def dist(p1, p2):
        return math.sqrt((p1[0]-p2[0])**2 + (p1[1]-p2[1])**2)
    
    def is_near(val, target, tolerance=tol):
        return abs(val - target) <= tolerance

    def is_point_near(p, target, tolerance=tol):
        return dist((p[0], p[1]), target) <= tolerance

    # --- Check Layer (7 pts) ---
    layers = [layer.dxf.name for layer in doc.layers]
    if expected_layer in layers:
        score += 7
        feedback_parts.append(f"Layer '{expected_layer}' exists")
    else:
        feedback_parts.append(f"Layer '{expected_layer}' missing")

    # --- Check Circles (22 pts total) ---
    circles = [e for e in entities if e.dxftype() == 'CIRCLE']
    outer_circle = False
    inner_circle = False
    
    for c in circles:
        r = c.dxf.radius
        center = (c.dxf.center.x, c.dxf.center.y)
        if is_near(r, 100) and is_point_near(center, (0,0)):
            outer_circle = True
        if is_near(r, 20) and is_point_near(center, (0,0)):
            inner_circle = True
            
    if outer_circle:
        score += 12
        feedback_parts.append("Outer circle (r=100) correct")
    else:
        feedback_parts.append("Outer circle missing or incorrect")
        
    if inner_circle:
        score += 10
        feedback_parts.append("Inner circle (r=20) correct")
    else:
        feedback_parts.append("Inner circle missing or incorrect")

    # --- Check Lines (40 pts total) ---
    lines = [e for e in entities if e.dxftype() == 'LINE']
    
    # Target endpoints for lines starting/ending near (0,0)
    cardinal_targets = {
        "North": (0, 100), "East": (100, 0), "South": (0, -100), "West": (-100, 0)
    }
    
    ordinal_len = 70
    # cos(45) = sin(45) ≈ 0.7071
    offset = ordinal_len * math.cos(math.radians(45)) # ≈ 49.497
    ordinal_targets = {
        "NE": (offset, offset), "NW": (-offset, offset), 
        "SW": (-offset, -offset), "SE": (offset, -offset)
    }
    
    found_cardinals = 0
    found_ordinals = 0
    
    def check_line(target_pt):
        for l in lines:
            s = (l.dxf.start.x, l.dxf.start.y)
            e = (l.dxf.end.x, l.dxf.end.y)
            # Check if one end is origin and other is target
            if (is_point_near(s, (0,0)) and is_point_near(e, target_pt)) or \
               (is_point_near(e, (0,0)) and is_point_near(s, target_pt)):
                return True
        return False

    for name, pt in cardinal_targets.items():
        if check_line(pt):
            found_cardinals += 1
            score += 5 # 5 pts per cardinal line
    
    for name, pt in ordinal_targets.items():
        if check_line(pt):
            found_ordinals += 1
            score += 5 # 5 pts per ordinal line

    if found_cardinals == 4:
        feedback_parts.append("All 4 cardinal lines correct")
    else:
        feedback_parts.append(f"Found {found_cardinals}/4 cardinal lines")

    if found_ordinals == 4:
        feedback_parts.append("All 4 ordinal lines correct")
    else:
        feedback_parts.append(f"Found {found_ordinals}/4 ordinal lines")

    # --- Check Text (10 pts) ---
    text_entities = [e for e in entities if e.dxftype() in ('TEXT', 'MTEXT')]
    n_found = False
    for t in text_entities:
        content = t.dxf.text if t.dxftype() == 'TEXT' else t.text
        # Position check: roughly above (0,0) in Y positive
        try:
            pos_y = t.dxf.insert.y
            if "N" in content.upper() and pos_y > 80:
                n_found = True
                break
        except:
            continue
            
    if n_found:
        score += 10
        feedback_parts.append("'N' label found")
    else:
        feedback_parts.append("'N' label missing or misplaced")

    # --- Check Entity Layer Assignment (8 pts) ---
    # At least 80% of geometric entities should be on the correct layer
    geom_entities = [e for e in entities if e.dxftype() in ('LINE', 'CIRCLE', 'TEXT', 'MTEXT')]
    if geom_entities and expected_layer in layers:
        on_layer_count = sum(1 for e in geom_entities if e.dxf.layer == expected_layer)
        ratio = on_layer_count / len(geom_entities)
        if ratio >= 0.8:
            score += 8
            feedback_parts.append("Entities correctly assigned to layer")
        elif ratio >= 0.5:
            score += 4
            feedback_parts.append("Some entities on correct layer")
        else:
            feedback_parts.append("Entities not on 'COMPASS_ROSE' layer")
    elif not geom_entities:
         feedback_parts.append("No geometric entities found")
    
    # ================================================================
    # 5. VLM Verification (5 pts)
    # ================================================================
    # Visual check using final screenshot
    vlm_score = 0
    final_screenshot = get_final_screenshot(traj)
    
    if final_screenshot and score >= 40: # Only run VLM if basic geometry exists
        prompt = """
        Analyze this technical drawing screenshot. 
        Does it show a "compass rose" symbol?
        I expect to see:
        1. Two concentric circles in the center.
        2. Radiating lines forming a star pattern (North, South, East, West).
        3. A letter "N" at the top.
        
        Return JSON: {"is_compass_rose": true/false, "confidence": 0-1}
        """
        try:
            result = query_vlm(prompt, images=[final_screenshot])
            parsed = result.get('parsed', {})
            if parsed.get('is_compass_rose', False):
                vlm_score = 5
                score += vlm_score
                feedback_parts.append("Visual verification passed")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if programmatic score is high, give these points
            if score >= 80:
                score += 5
                feedback_parts.append("VLM skipped, assuming visual correctness based on geometry")

    # Final Score Calculation
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }