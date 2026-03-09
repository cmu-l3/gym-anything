#!/usr/bin/env python3
"""
Verifier for pressure_gauge_face task.
Uses ezdxf to parse the output DXF file and verify geometry, layers, and text.
"""

import json
import os
import sys
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import ezdxf, install if missing (standard pattern for verifiers)
try:
    import ezdxf
    from ezdxf.document import Drawing
except ImportError:
    try:
        import subprocess
        subprocess.check_call([sys.executable, "-m", "pip", "install", "ezdxf"])
        import ezdxf
        from ezdxf.document import Drawing
    except Exception as e:
        logger.error(f"Failed to install ezdxf: {e}")
        ezdxf = None

def normalize_angle(angle_deg):
    """Normalize angle to 0-360 range."""
    return angle_deg % 360

def verify_pressure_gauge_face(traj, env_info, task_info):
    """
    Verifies the pressure gauge face DXF drawing.
    
    Criteria:
    1. File exists and is a valid DXF created during the task.
    2. Required layers exist (PLATE, TICKS, LABELS, DANGER).
    3. PLATE layer: Contains outer circle (r=50) and hole (r=3).
    4. TICKS layer: Contains ~21 lines starting at r=40.
    5. LABELS layer: Contains numbers 0, 100.
    6. DANGER layer: Contains an arc spanning approx 80-100 PSI range.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    if not ezdxf:
        return {"passed": False, "score": 0, "feedback": "Verification failed: ezdxf library unavailable"}

    # Retrieve result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Check basic file existence
    if not result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "No output file found at expected path."}
    
    if not result.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output file was not created/modified during the task window."}

    # Retrieve DXF file
    dxf_path = result.get("output_path")
    temp_dxf = tempfile.NamedTemporaryFile(delete=False, suffix='.dxf')
    try:
        copy_from_env(dxf_path, temp_dxf.name)
        doc = ezdxf.readfile(temp_dxf.name)
        msp = doc.modelspace()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid or unreadable DXF file: {e}"}
    finally:
        if os.path.exists(temp_dxf.name):
            os.unlink(temp_dxf.name)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Criterion 1: Layers (15 pts)
    # ---------------------------------------------------------
    required_layers = {"PLATE", "TICKS", "LABELS", "DANGER"}
    found_layers = {layer.dxf.name.upper() for layer in doc.layers}
    # Allow case-insensitive matching
    missing_layers = [l for l in required_layers if l not in found_layers]
    
    if not missing_layers:
        score += 15
        feedback_parts.append("All layers created.")
    else:
        # Partial credit
        score += int(15 * (len(required_layers) - len(missing_layers)) / len(required_layers))
        feedback_parts.append(f"Missing layers: {', '.join(missing_layers)}.")

    # ---------------------------------------------------------
    # Criterion 2: Plate Geometry (20 pts)
    # ---------------------------------------------------------
    plate_entities = msp.query(f'*[layer=="PLATE" or layer=="plate"]')
    circles = [e for e in plate_entities if e.dxftype() == 'CIRCLE']
    
    has_outer = False
    has_hole = False
    
    for c in circles:
        r = c.dxf.radius
        center = c.dxf.center
        dist_from_origin = math.hypot(center.x, center.y)
        
        # Check proximity to origin
        if dist_from_origin < 1.0:
            if 49.0 <= r <= 51.0:
                has_outer = True
            elif 2.5 <= r <= 3.5:
                has_hole = True
                
    if has_outer:
        score += 10
        feedback_parts.append("Outer border correct.")
    else:
        feedback_parts.append("Outer border (R=50) not found on PLATE layer.")
        
    if has_hole:
        score += 10
        feedback_parts.append("Mounting hole correct.")
    else:
        feedback_parts.append("Mounting hole (R=3) not found on PLATE layer.")

    # ---------------------------------------------------------
    # Criterion 3: Ticks (30 pts)
    # ---------------------------------------------------------
    tick_entities = msp.query(f'*[layer=="TICKS" or layer=="ticks"]')
    lines = [e for e in tick_entities if e.dxftype() == 'LINE']
    
    valid_ticks = 0
    for line in lines:
        # Check start point radius
        start = line.dxf.start
        r_start = math.hypot(start.x, start.y)
        # Check end point radius
        end = line.dxf.end
        r_end = math.hypot(end.x, end.y)
        
        # Tick should start around 40 and go out
        if 39.0 <= min(r_start, r_end) <= 41.0:
            if 41.5 <= max(r_start, r_end) <= 46.0:
                valid_ticks += 1
                
    # Expect 21 total ticks (11 major + 10 minor)
    if valid_ticks >= 18:
        score += 30
        feedback_parts.append(f"Tick marks found ({valid_ticks}).")
    elif valid_ticks >= 10:
        score += 15
        feedback_parts.append(f"Some tick marks found ({valid_ticks}).")
    else:
        feedback_parts.append(f"Insufficient tick marks found ({valid_ticks}, expected ~21).")

    # ---------------------------------------------------------
    # Criterion 4: Labels (20 pts)
    # ---------------------------------------------------------
    label_entities = msp.query(f'*[layer=="LABELS" or layer=="labels"]')
    text_content = []
    for e in label_entities:
        if e.dxftype() in ['TEXT', 'MTEXT']:
            text_content.append(e.dxf.text)
            
    found_0 = any("0" in t for t in text_content)
    found_100 = any("100" in t for t in text_content)
    
    if found_0 and found_100:
        score += 20
        feedback_parts.append("Start/End labels (0, 100) found.")
    elif found_0 or found_100:
        score += 10
        feedback_parts.append("Partial labels found.")
    else:
        feedback_parts.append("Numeric labels 0/100 not found.")

    # ---------------------------------------------------------
    # Criterion 5: Danger Zone Arc (15 pts)
    # ---------------------------------------------------------
    danger_entities = msp.query(f'*[layer=="DANGER" or layer=="danger"]')
    arcs = [e for e in danger_entities if e.dxftype() == 'ARC']
    
    valid_arc = False
    for arc in arcs:
        r = arc.dxf.radius
        if 39.0 <= r <= 41.0:
            # Danger zone is last 20 PSI
            # 225 start. 100 PSI = 270 deg sweep. 
            # 80 PSI = 225 - (80 * 2.7) = 225 - 216 = 9 deg (if math is strict)
            # Wait, rotation direction:
            # Start 225 (SW). Clockwise (decreasing angle in standard math, but CAD usually CCW?)
            # Prompt said: "rotate clockwise to -45".
            # 225 - 270 = -45 (or 315).
            # 80 PSI = 80% of sweep.
            # Angle at 80 PSI = 225 - (80/100 * 270) = 225 - 216 = 9 degrees.
            # Angle at 100 PSI = -45 (315) degrees.
            # So arc should cover approx 9 deg to 315 deg (spanning 0).
            # ezdxf/DXF arcs are always CCW.
            # So to draw a CW arc from 9 to 315, in DXF it is an arc from 315 to 9.
            
            start = normalize_angle(arc.dxf.start_angle)
            end = normalize_angle(arc.dxf.end_angle)
            
            # Check if angles are roughly correct (allow some slop)
            # Expecting range [315, 9] (which is -45 to 9)
            # Center of arc should be roughly -18 deg (342 deg)
            
            # Simple check: does it cover the gap?
            # Length of arc in degrees
            span = (end - start) % 360
            if 40 <= span <= 68: # 20 PSI is 54 degrees. Allow +/- 14 deg.
                valid_arc = True
                
    if valid_arc:
        score += 15
        feedback_parts.append("Danger zone arc correct.")
    else:
        feedback_parts.append("Danger zone arc not found or incorrect angles.")

    # ---------------------------------------------------------
    # Final Scoring
    # ---------------------------------------------------------
    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }