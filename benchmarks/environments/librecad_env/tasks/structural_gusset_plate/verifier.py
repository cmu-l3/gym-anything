#!/usr/bin/env python3
import json
import os
import sys
import tempfile
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Attempt to import ezdxf, installing if necessary
try:
    import ezdxf
except ImportError:
    import subprocess
    logger.info("Installing ezdxf...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "ezdxf"])
    import ezdxf

def verify_structural_gusset_plate(traj, env_info, task_info):
    """
    Verifies the Structural Gusset Plate task.
    
    Criteria:
    1. File exists and is a valid DXF.
    2. Layers STEEL(Cyan), HOLES(Yellow), MARK(Red) exist.
    3. STEEL layer contains a chamfered plate (8 vertices/segments).
    4. HOLES layer contains 6 circles at correct grid coordinates.
    5. MARK layer contains text "GP-1".
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_holes = metadata.get('holes', {})
    
    score = 0
    feedback = []
    
    # 1. Retrieve Result JSON and DXF File
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_dxf = tempfile.NamedTemporaryFile(delete=False, suffix='.dxf')
    
    try:
        # Load JSON result
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
            
        if not result.get('output_exists'):
            return {"passed": False, "score": 0, "feedback": "Output DXF file was not created."}
            
        if not result.get('file_created_during_task'):
             return {"passed": False, "score": 0, "feedback": "Output file exists but was not created during the task (anti-gaming check failed)."}

        # Load DXF file
        copy_from_env(result['output_path'], temp_dxf.name)
        try:
            doc = ezdxf.readfile(temp_dxf.name)
            msp = doc.modelspace()
            score += 10 # Valid DXF
            feedback.append("Valid DXF file parsed.")
        except Exception as e:
            return {"passed": False, "score": 10, "feedback": f"File created but is not a valid DXF: {e}"}
            
        # 2. Verify Layers
        layers_score = 0
        required_layers = metadata.get('layers', {})
        for name, color in required_layers.items():
            if name in doc.layers:
                layer = doc.layers.get(name)
                # DXF color index check (allow some flexibility if names match)
                if layer.color == color:
                    layers_score += 10/len(required_layers)
                else:
                    layers_score += 5/len(required_layers) # Half points for correct name, wrong color
                    feedback.append(f"Layer '{name}' exists but has wrong color (expected {color}, got {layer.color}).")
            else:
                feedback.append(f"Missing layer: '{name}'.")
        
        score += int(layers_score)
        if int(layers_score) == 10:
            feedback.append("All layers created correctly.")

        # 3. Verify Plate Geometry (STEEL Layer)
        # Expected: A closed shape with chamfered corners.
        # Original rect: 0,0 to 300,200. Chamfer 40.
        # Vertices should approx be: (40,0), (260,0), (300,40), (300,160), (260,200), (40,200), (0,160), (0,40)
        
        steel_entities = msp.query(f'LINE LWPOLYLINE[layer=="STEEL"]')
        if len(steel_entities) == 0:
            feedback.append("No geometry found on STEEL layer.")
        else:
            # Simplification: Check bounding box and vertex count/complexity
            # Accurate geometric checking of chamfers is complex due to drawing methods (lines vs polyline)
            # We check if the bounding box matches 300x200 and if it's NOT a simple rectangle (4 points)
            
            bbox = ezdxf.bbox.extents(steel_entities)
            width = bbox.extmax.x - bbox.extmin.x
            height = bbox.extmax.y - bbox.extmin.y
            
            dim_score = 0
            if abs(width - 300) < 5 and abs(height - 200) < 5:
                dim_score = 20
                feedback.append("Plate overall dimensions correct (300x200).")
            else:
                feedback.append(f"Plate dimensions incorrect: {width:.1f}x{height:.1f} (expected 300x200).")
            
            # Chamfer check: If it's a simple rectangle, it fails chamfer check
            # An unchamfered rectangle has 4 vertices or 4 lines.
            # A chamfered one has 8 vertices or 8 lines.
            
            chamfer_score = 0
            entity_count = len(steel_entities)
            
            # If polyline, check vertex count
            has_chamfer = False
            if entity_count == 1 and steel_entities[0].dxftype() == 'LWPOLYLINE':
                 if len(steel_entities[0]) >= 8:
                     has_chamfer = True
            elif entity_count >= 8: # Assuming lines
                 has_chamfer = True
                 
            if has_chamfer and dim_score > 0:
                chamfer_score = 20
                feedback.append("Chamfer geometry detected.")
            elif dim_score > 0:
                feedback.append("Plate appears to be a simple rectangle (chamfers missing).")
            
            score += dim_score + chamfer_score

        # 4. Verify Holes (HOLES Layer)
        holes = msp.query(f'CIRCLE[layer=="HOLES"]')
        holes_score = 0
        
        if len(holes) == 6:
            holes_score += 10
            feedback.append("Correct number of holes (6).")
            
            # Check Radius
            correct_radius = 0
            for h in holes:
                if abs(h.dxf.radius - 11) < 0.5:
                    correct_radius += 1
            
            if correct_radius == 6:
                holes_score += 10
                feedback.append("All holes have correct diameter (22mm).")
            else:
                feedback.append(f"{correct_radius}/6 holes have correct diameter.")
                
            # Check Position (Grid)
            # Expected centers: (50,50), (150,50), (250,50), (50,150), (150,150), (250,150)
            expected_centers = [(50,50), (150,50), (250,50), (50,150), (150,150), (250,150)]
            matched_holes = 0
            
            # Get actual centers
            actual_centers = [(h.dxf.center.x, h.dxf.center.y) for h in holes]
            
            for ex, ey in expected_centers:
                # Find closest match
                for ax, ay in actual_centers:
                    dist = math.hypot(ex - ax, ey - ay)
                    if dist < 2.0: # Tolerance
                        matched_holes += 1
                        break
            
            if matched_holes == 6:
                holes_score += 20
                feedback.append("Hole grid positions correct.")
            else:
                feedback.append(f"{matched_holes}/6 holes in correct positions.")
                holes_score += (matched_holes / 6) * 20
                
        else:
            feedback.append(f"Found {len(holes)} holes on HOLES layer (expected 6).")
            
        score += int(holes_score)

        # 5. Verify Text (MARK Layer)
        text_entities = msp.query(f'TEXT MTEXT[layer=="MARK"]')
        text_score = 0
        found_text = False
        for t in text_entities:
            content = t.dxf.text if t.dxftype() == 'TEXT' else t.text
            if "GP-1" in content:
                found_text = True
                break
        
        if found_text:
            text_score = 10
            feedback.append("Part mark 'GP-1' found.")
        else:
            feedback.append("Part mark 'GP-1' not found on MARK layer.")
            
        score += text_score

    except Exception as e:
        logger.exception("Verification failed with error")
        return {"passed": False, "score": score, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
        if os.path.exists(temp_dxf.name):
            os.unlink(temp_dxf.name)

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }