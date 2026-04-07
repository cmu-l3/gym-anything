#!/usr/bin/env python3
"""Verifier for publication_false_color_figure task.

Scoring breakdown (must sum to exactly 100):
  File existence:                             15 pts
  Valid format & created during task:         15 pts
  Anti-gaming VLM check (clean figure):       20 pts
  Color composite VLM check (false color):    20 pts
  Scale bar present VLM check:                15 pts
  North arrow present VLM check:              15 pts
                                       TOTAL: 100 pts
Pass threshold: 70
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import VLM utilities safely
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logger.warning("VLM utilities not available")


def verify_publication_false_color_figure(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/snap_exports/landsat_figure.png')
    
    # 1. Retrieve programmatic results
    result_path = tempfile.mktemp(suffix='.json')
    try:
        copy_from_env('/tmp/publication_figure_result.json', result_path)
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve JSON result: {e}"}
    finally:
        if os.path.exists(result_path):
            os.unlink(result_path)

    score = 0
    feedback = []

    # Criterion 1: File Existence (15 pts)
    if result.get('file_found'):
        score += 15
        feedback.append("Exported file found (+15)")
    else:
        feedback.append("No exported file found at expected path (0/15)")
        return {"passed": False, "score": 0, "feedback": "; ".join(feedback)}

    # Criterion 2: Valid Format & Timestamp (15 pts)
    fmt = result.get('format', '')
    width = result.get('image_width', 0)
    height = result.get('image_height', 0)
    
    if result.get('file_created_after_start') and fmt == 'PNG' and width >= 400 and height >= 400:
        score += 15
        feedback.append(f"Valid PNG image ({width}x{height}) created during task (+15)")
    elif result.get('file_created_after_start') and fmt in ['PNG', 'JPEG']:
        score += 10
        feedback.append(f"Valid image created, but dimensions or specific format imperfect (+10)")
    else:
        feedback.append("File format invalid, too small, or file existed before task (0/15)")
        
    # If VLM is not available, we have to abort visual verification and return what we have
    if not VLM_AVAILABLE:
        feedback.append("VLM unavailable - cannot visually verify image contents.")
        return {"passed": score >= 70, "score": score, "feedback": "; ".join(feedback)}

    # 3. Retrieve the actual exported image for VLM analysis
    img_path = tempfile.mktemp(suffix='.png')
    try:
        copy_from_env(expected_path, img_path)
        from PIL import Image
        exported_img = Image.open(img_path)
        exported_img.verify()  # Ensure it's not corrupted
        exported_img = Image.open(img_path) # Reload after verify
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to retrieve/open exported image for VLM: {e}"}

    # 4. Perform VLM check on the exported image
    vlm_prompt = """You are analyzing a cartographic figure exported from ESA SNAP.
Please analyze the image and respond in JSON with the following boolean fields:
1. "is_clean_figure": true if it's a cleanly exported map view WITHOUT any desktop/software UI elements (no window borders, OS taskbars, software menus, toolbars, or floating dialogs).
2. "is_false_color": true if the landscape uses a false-color composite. In the SWIR-NIR-Red mapping, vegetation typically appears bright green, while bare soil/urban areas appear magenta, pink, or purple. It should NOT look like a standard true-color photo.
3. "has_scale_bar": true if a geographic distance scale bar overlay is visible anywhere on the map.
4. "has_north_arrow": true if a north-pointing compass arrow overlay is visible.

Return ONLY valid JSON format:
{
  "is_clean_figure": true/false,
  "is_false_color": true/false,
  "has_scale_bar": true/false,
  "has_north_arrow": true/false,
  "observations": "Brief explanation of what you see"
}"""

    try:
        vlm_res = query_vlm(prompt=vlm_prompt, image=exported_img)
        if not vlm_res.get('success'):
            feedback.append(f"VLM query failed: {vlm_res.get('error')}")
        else:
            vlm_data = vlm_res.get('parsed', {})
            
            # Anti-gaming: Clean figure (20 pts)
            if vlm_data.get('is_clean_figure', False):
                score += 20
                feedback.append("VLM confirms clean exported figure (no UI) (+20)")
            else:
                feedback.append("VLM detected UI elements (Screenshot instead of Export View) (0/20)")
                
            # Color Composite (20 pts)
            if vlm_data.get('is_false_color', False):
                score += 20
                feedback.append("VLM confirms SWIR-NIR-Red false color scheme (+20)")
            else:
                feedback.append("VLM did not detect false color composite (0/20)")
                
            # Scale Bar (15 pts)
            if vlm_data.get('has_scale_bar', False):
                score += 15
                feedback.append("VLM confirms scale bar overlay (+15)")
            else:
                feedback.append("VLM did not detect scale bar overlay (0/15)")
                
            # North Arrow (15 pts)
            if vlm_data.get('has_north_arrow', False):
                score += 15
                feedback.append("VLM confirms north arrow overlay (+15)")
            else:
                feedback.append("VLM did not detect north arrow overlay (0/15)")
                
            # Optional: Append the VLM's observations for debugging context
            if 'observations' in vlm_data:
                logger.info(f"VLM Observations: {vlm_data['observations']}")
                
    except Exception as e:
        feedback.append(f"VLM processing error: {str(e)}")
    finally:
        if os.path.exists(img_path):
            os.unlink(img_path)

    # Calculate final status
    passed = score >= 70
    return {"passed": passed, "score": score, "feedback": "; ".join(feedback)}