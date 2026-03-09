#!/usr/bin/env python3
import json
import os
import sys
import tempfile
import logging
import math

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import ezdxf, installing if necessary
try:
    import ezdxf
except ImportError:
    try:
        import subprocess
        subprocess.check_call([sys.executable, "-m", "pip", "install", "ezdxf"])
        import ezdxf
    except Exception as e:
        logger.error(f"Failed to install ezdxf: {e}")
        ezdxf = None

def verify_cabinet_side_panel(traj, env_info, task_info):
    """
    Verifies the Cabinet Side Panel task.
    
    Criteria:
    1. DXF file exists and can be parsed.
    2. Layers 'PANEL', 'DRILLING', 'DADO' exist with correct colors.
    3. Panel dimensions match spec (720x560) with Toe Kick (100x70).
    4. Back Groove exists on DADO layer.
    5. Shelf pin holes exist on DRILLING layer (System 32 pattern).
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    spec_values = metadata.get('spec_values', {})
    
    # Create temp directory for artifacts
    with tempfile.TemporaryDirectory() as temp_dir:
        result_json_path = os.path.join(temp_dir, "task_result.json")
        dxf_path = os.path.join(temp_dir, "side_panel.dxf")
        
        try:
            # Copy result JSON
            copy_from_env("/tmp/task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                result = json.load(f)
            
            # Check basic file existence
            if not result.get("output_exists", False):
                return {"passed": False, "score": 0, "feedback": "Output DXF file was not found."}
            
            if not result.get("file_created_during_task", False):
                return {"passed": False, "score": 0, "feedback": "Output file was not modified during the task."}

            # Copy DXF file
            copy_from_env(result["output_file_path"], dxf_path)
            
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task files: {str(e)}"}

        if not ezdxf:
            return {"passed": False, "score": 0, "feedback": "Verification failed: ezdxf library unavailable."}

        # 2. Parse DXF
        try:
            doc = ezdxf.readfile(dxf_path)
            msp = doc.modelspace()
        except Exception as e:
            return {"passed": False, "score": 10, "feedback": f"Invalid DXF file: {str(e)}"}

        score = 10  # Base score for valid file
        feedback = []
        
        # 3. Verify Layers (15 points)
        # Colors: Panel=White(7), Drilling=Red(1), Dado=Cyan(4)
        required_layers = {
            "PANEL": 7,
            "DRILLING": 1,
            "DADO": 4
        }
        
        layers_score = 0
        for name, color in required_layers.items():
            if name in doc.layers:
                layer = doc.layers.get(name)
                # Check color (strict or lenient?) - lenient on color, strict on name
                if layer.color == color:
                    layers_score += 5
                else:
                    layers_score += 3 # Layer exists but wrong color
                    feedback.append(f"Layer '{name}' exists but color is {layer.color} (expected {color}).")
            else:
                feedback.append(f"Missing layer: '{name}'.")
        
        score += layers_score

        # 4. Verify Geometry - Panel Outline (25 points)
        # Bounding box should be approx Height x Depth
        # Since we don't know exact coordinates (relative to origin), we check extents
        panel_entities = list(msp.query('Entity[layer=="PANEL"]'))
        
        if not panel_entities:
            feedback.append("No entities found on PANEL layer.")
        else:
            # Calculate bounding box of panel entities
            min_x, min_y = float('inf'), float('inf')
            max_x, max_y = float('-inf'), float('-inf')
            valid_geom = False
            
            for e in panel_entities:
                if e.dxftype() in ['LINE', 'LWPOLYLINE', 'POLYLINE']:
                    valid_geom = True
                    # ezdxf bbox calculation can be complex, doing simple vertex check
                    if e.dxftype() == 'LINE':
                        pts = [e.dxf.start, e.dxf.end]
                    elif e.dxftype() == 'LWPOLYLINE':
                        pts = list(e.vertices())
                    
                    for p in pts:
                        min_x = min(min_x, p[0])
                        max_x = max(max_x, p[0])
                        min_y = min(min_y, p[1])
                        max_y = max(max_y, p[1])

            if valid_geom and min_x != float('inf'):
                width = max_x - min_x
                height = max_y - min_y
                
                # Check width (Depth) and height (Height)
                # Allow small tolerance
                target_w = spec_values['depth']
                target_h = spec_values['height']
                
                if abs(width - target_w) < 2.0 and abs(height - target_h) < 2.0:
                    score += 15
                    feedback.append("Panel overall dimensions correct.")
                    
                    # Check for Toe Kick (Notch)
                    # A notch would create vertex points inside the bounding box
                    # This is hard to verify robustly without full shape analysis.
                    # We'll check vertex count or visual cues via VLM, but here maybe just simple heuristic:
                    # A simple rectangle has 4 vertices. A notched one has 6.
                    vertex_count = 0
                    for e in panel_entities:
                        if e.dxftype() == 'LWPOLYLINE':
                            vertex_count += len(e)
                        elif e.dxftype() == 'LINE':
                            vertex_count += 1 # Rough count
                    
                    if vertex_count >= 6:
                        score += 10
                        feedback.append("Panel geometry complexity suggests notch presence.")
                    else:
                        feedback.append("Panel geometry seems too simple (missing notch?).")
                else:
                    feedback.append(f"Panel dimensions incorrect. Found {width:.1f}x{height:.1f}, expected {target_w}x{target_h}.")

        # 5. Verify Back Groove (15 points)
        dado_entities = list(msp.query('Entity[layer=="DADO"]'))
        if dado_entities:
            score += 15
            feedback.append("Back groove layer populated.")
        else:
            feedback.append("No geometry on DADO layer.")

        # 6. Verify Drilling (35 points)
        # Expect circles of diameter 5
        # Expect spacing 32mm
        drill_entities = list(msp.query('CIRCLE[layer=="DRILLING"]'))
        
        if drill_entities:
            # Check diameters
            correct_dia = 0
            for e in drill_entities:
                # Radius * 2
                if abs((e.dxf.radius * 2) - spec_values['hole_dia']) < 0.1:
                    correct_dia += 1
            
            if correct_dia == len(drill_entities) and len(drill_entities) > 0:
                score += 10
                feedback.append("Hole diameters correct.")
            elif correct_dia > 0:
                score += 5
                feedback.append("Some hole diameters incorrect.")
            
            # Check Pattern (Y spacing)
            # Collect centers
            centers = sorted([(e.dxf.center.x, e.dxf.center.y) for e in drill_entities], key=lambda p: p[1])
            
            if len(centers) > 1:
                # Check vertical pitch matches 32mm for at least some holes
                matches_32 = 0
                for i in range(len(centers) - 1):
                    dy = centers[i+1][1] - centers[i][1]
                    if abs(dy - 32.0) < 0.1:
                        matches_32 += 1
                
                # We expect roughly (N_holes_per_col - 1) * 2 matches
                if matches_32 >= 4: # Arbitrary threshold for "looks like a system 32 array"
                    score += 25
                    feedback.append("System 32 vertical spacing verified.")
                else:
                    feedback.append(f"Hole spacing does not match 32mm pitch (Found {matches_32} matches).")
            else:
                feedback.append("Not enough holes to verify spacing.")
                
        else:
            feedback.append("No holes found on DRILLING layer.")

        # 7. Final VLM check (External signal integration)
        # If score is borderline, we trust the geometric verification mostly, 
        # but we can penalize if VLM visual check fails (simulated here)
        
        pass_threshold = 60
        passed = score >= pass_threshold
        
        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " ".join(feedback)
        }