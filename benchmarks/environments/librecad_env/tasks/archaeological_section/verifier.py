#!/usr/bin/env python3
"""
Verifier for archaeological_section task.
Uses ezdxf to validate layer structure, hatch patterns, and text content.
"""

import json
import os
import sys
import tempfile
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import ezdxf, install if missing
try:
    import ezdxf
    EZDXF_AVAILABLE = True
except ImportError:
    try:
        import subprocess
        subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "ezdxf"])
        import ezdxf
        EZDXF_AVAILABLE = True
    except Exception as e:
        logger.error(f"Failed to install ezdxf: {e}")
        EZDXF_AVAILABLE = False

def verify_archaeological_section(traj, env_info, task_info):
    """
    Verify the archaeological section drawing.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    if not EZDXF_AVAILABLE:
        return {"passed": False, "score": 0, "feedback": "Verifier failed: ezdxf library could not be installed"}

    metadata = task_info.get('metadata', {})
    required_layers = metadata.get('required_layers', [])
    hatch_patterns = metadata.get('hatch_patterns', {})
    required_text = metadata.get('required_text', [])

    # Retrieve result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Basic checks
    if not result_data.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output DXF file not found."}

    if not result_data.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Output file was not created/modified during the task session."}

    # Retrieve DXF file
    temp_dxf = tempfile.NamedTemporaryFile(delete=False, suffix='.dxf')
    dxf_path_in_env = result_data.get('output_path')
    try:
        copy_from_env(dxf_path_in_env, temp_dxf.name)
    except Exception as e:
        os.unlink(temp_dxf.name)
        return {"passed": False, "score": 0, "feedback": f"Failed to copy DXF file: {e}"}

    # Scoring
    score = 0
    feedback = []
    
    # 1. File Structure (10 pts)
    try:
        doc = ezdxf.readfile(temp_dxf.name)
        score += 10
        feedback.append("Valid DXF file")
    except Exception as e:
        os.unlink(temp_dxf.name)
        return {"passed": False, "score": 0, "feedback": f"Invalid DXF file: {e}"}

    msp = doc.modelspace()

    # 2. Layer Setup (15 pts)
    existing_layers = [layer.dxf.name for layer in doc.layers]
    layers_found = 0
    for layer in required_layers:
        # Case insensitive check
        if any(l.lower() == layer.lower() for l in existing_layers):
            layers_found += 1
    
    if layers_found == len(required_layers):
        score += 15
        feedback.append(f"All {layers_found} required layers found")
    else:
        score += int(15 * (layers_found / len(required_layers)))
        feedback.append(f"Found {layers_found}/{len(required_layers)} required layers")

    # 3. Geometry (20 pts)
    # Check for entities on BOUNDARIES layer
    boundaries_ents = doc.query('LINES POLYLINE SPLINE LWPOLYLINE[layer=="BOUNDARIES"]')
    if len(boundaries_ents) >= 4: # Rectangle + 2 horizons
        score += 20
        feedback.append("Boundary geometry found")
    elif len(boundaries_ents) > 0:
        score += 10
        feedback.append("Incomplete boundary geometry")
    else:
        feedback.append("No geometry on BOUNDARIES layer")

    # 4. Hatching (45 pts total, 15 per context)
    for layer, valid_patterns in hatch_patterns.items():
        # Find hatches on this layer (case insensitive layer name)
        # ezdxf query is case sensitive for values usually, handle carefully
        # We manually iterate to be safe with casing
        layer_hatches = []
        for hatch in msp.query('HATCH'):
            if hatch.dxf.layer.lower() == layer.lower():
                layer_hatches.append(hatch)
        
        if not layer_hatches:
            feedback.append(f"No hatch found on {layer}")
            continue

        # Check pattern name
        pattern_match = False
        found_pattern = "unknown"
        for h in layer_hatches:
            found_pattern = h.dxf.pattern_name
            if found_pattern.upper() in [p.upper() for p in valid_patterns]:
                pattern_match = True
                break
        
        if pattern_match:
            score += 15
            feedback.append(f"Correct hatch '{found_pattern}' on {layer}")
        else:
            # Partial credit for having a hatch at all
            score += 5
            feedback.append(f"Wrong hatch pattern '{found_pattern}' on {layer} (expected {valid_patterns})")

    # 5. Annotation (10 pts)
    found_texts = []
    for text in msp.query('TEXT MTEXT'):
        found_texts.append(text.dxf.text.upper())
    
    text_matches = 0
    for req in required_text:
        if any(req.upper() in t for t in found_texts):
            text_matches += 1
    
    if text_matches == len(required_text):
        score += 10
        feedback.append("All text labels found")
    elif text_matches > 0:
        score += 5
        feedback.append(f"Found {text_matches}/{len(required_text)} text labels")
    else:
        feedback.append("No matching text labels found")

    # Clean up
    if os.path.exists(temp_dxf.name):
        os.unlink(temp_dxf.name)

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }