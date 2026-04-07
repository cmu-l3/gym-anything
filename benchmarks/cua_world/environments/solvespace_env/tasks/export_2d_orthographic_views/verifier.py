#!/usr/bin/env python3
"""
Verifier for export_2d_orthographic_views task.
"""

import os
import json
import tempfile
import re
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_dimension(dim_str):
    """Parses an SVG dimension string (e.g., '150mm', '80.5in') into mm float."""
    if not dim_str:
        return 0.0
    dim_str = dim_str.strip().lower()
    
    match = re.match(r'([0-9.]+)([a-z]*)', dim_str)
    if not match:
        return 0.0
        
    val = float(match.group(1))
    unit = match.group(2)
    
    if unit == 'in':
        return val * 25.4
    elif unit == 'cm':
        return val * 10.0
    elif unit == 'px' or unit == '':
        return val / 3.7795275591  # standard 96 dpi assumption
    
    return val  # Default assuming mm


def analyze_svg(file_path):
    """Reads an SVG file and extracts key metadata for validation."""
    if not os.path.exists(file_path):
        return None
        
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
            
        # Extract width and height from the <svg> root tag
        width_match = re.search(r'<svg[^>]*\swidth="([^"]+)"', content)
        height_match = re.search(r'<svg[^>]*\sheight="([^"]+)"', content)
        
        w_val = parse_dimension(width_match.group(1)) if width_match else 0.0
        h_val = parse_dimension(height_match.group(1)) if height_match else 0.0
        
        # Check for axes (SolveSpace uses <text> for X,Y,Z labels and standard axis strokes)
        has_text_tags = '<text' in content
        
        # Check for hidden lines (SolveSpace uses stroke-dasharray)
        has_hidden_lines = 'stroke-dasharray' in content
        
        return {
            "width_mm": w_val,
            "height_mm": h_val,
            "has_axes": has_text_tags,
            "has_hidden_lines": has_hidden_lines
        }
    except Exception as e:
        logger.error(f"Error analyzing SVG {file_path}: {e}")
        return None


def verify_export_2d_orthographic_views(traj, env_info, task_info):
    """
    Verifies that the agent properly manipulated views and exported clean SVGs.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    
    # 1. Read task results JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    face_created = result.get('face_file', {}).get('created_during_task', False)
    edge_created = result.get('edge_file', {}).get('created_during_task', False)

    if face_created and edge_created:
        score += 20
        feedback_parts.append("✅ Both SVGs created during task")
    elif face_created or edge_created:
        score += 10
        feedback_parts.append("⚠️ Only one SVG file created")
    else:
        return {"passed": False, "score": 0, "feedback": "❌ Required SVG files were not created."}

    # 2. Extract and analyze the SVG files directly from the container
    face_metrics, edge_metrics = None, None
    
    temp_face = tempfile.NamedTemporaryFile(delete=False, suffix='.svg')
    temp_edge = tempfile.NamedTemporaryFile(delete=False, suffix='.svg')
    
    try:
        if result.get('face_file', {}).get('exists', False):
            copy_from_env("/home/ga/Documents/SolveSpace/side_face.svg", temp_face.name)
            face_metrics = analyze_svg(temp_face.name)
            
        if result.get('edge_file', {}).get('exists', False):
            copy_from_env("/home/ga/Documents/SolveSpace/side_edge.svg", temp_edge.name)
            edge_metrics = analyze_svg(temp_edge.name)
    finally:
        for tmp in [temp_face.name, temp_edge.name]:
            if os.path.exists(tmp):
                os.unlink(tmp)

    # 3. Geometric Validations
    face_valid = False
    edge_valid = False
    
    # Face Validation (Requires both dimensions to be large, W & H > 20mm)
    if face_metrics:
        w, h = face_metrics['width_mm'], face_metrics['height_mm']
        if w > 20 and h > 20:
            face_valid = True
            score += 20
            feedback_parts.append(f"✅ side_face.svg is valid face view ({w:.1f}x{h:.1f}mm)")
        else:
            feedback_parts.append(f"❌ side_face.svg dimensions ({w:.1f}x{h:.1f}mm) do not match a face view")

    # Edge Validation (Requires one dimension to be thickness-sized < 20mm, and the other large > 20mm)
    if edge_metrics:
        w, h = edge_metrics['width_mm'], edge_metrics['height_mm']
        min_dim, max_dim = min(w, h), max(w, h)
        if 0 < min_dim < 20 and max_dim > 20:
            edge_valid = True
            score += 20
            feedback_parts.append(f"✅ side_edge.svg is valid edge view ({w:.1f}x{h:.1f}mm)")
        else:
            feedback_parts.append(f"❌ side_edge.svg dimensions ({w:.1f}x{h:.1f}mm) do not match an edge view at 1:1 scale")

    # 4. Settings Validation (Scale, Hidden Lines, Axes)
    if face_metrics and edge_metrics:
        if not face_metrics['has_hidden_lines'] and not edge_metrics['has_hidden_lines']:
            score += 10
            feedback_parts.append("✅ Hidden lines successfully disabled")
        else:
            feedback_parts.append("❌ Hidden lines detected in export")
            
        if not face_metrics['has_axes'] and not edge_metrics['has_axes']:
            score += 10
            feedback_parts.append("✅ Axes successfully disabled")
        else:
            feedback_parts.append("❌ Axes detected in export")

    # 5. VLM Trajectory Verification
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        if frames:
            prompt = """
            Look at these frames of a user operating SolveSpace CAD software.
            1. Did the user open the "Export 2D View" dialog at least once?
            2. In the export dialog, did the user uncheck "Export hidden lines" and "Draw axes"?
            3. Did the user manipulate the camera view to flat orthographic projections?
            
            Return JSON:
            {
                "export_dialog_used": boolean,
                "settings_adjusted": boolean,
                "camera_manipulated": boolean
            }
            """
            vlm_res = query_vlm(prompt=prompt, images=frames)
            
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('export_dialog_used', False): vlm_score += 5
                if parsed.get('settings_adjusted', False): vlm_score += 10
                if parsed.get('camera_manipulated', False): vlm_score += 5
                
                score += vlm_score
                feedback_parts.append(f"✅ VLM Trajectory check: {vlm_score}/20 pts")
            else:
                feedback_parts.append("⚠️ VLM verification failed to parse")

    # Determine passing state
    key_criteria_met = face_valid and edge_valid
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }