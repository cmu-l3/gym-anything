#!/usr/bin/env python3
"""
Verifier for Warehouse Layout Optimization.

Checks:
1. Spatial Organization: Fast movers should be closer to Packing Area than Slow movers.
2. Zone Placement: Fast movers should be in "Zone A" (absolute distance check).
3. Artifacts: PDF export exists, file modified.
4. Visuals (VLM): Checks for "Zone A" label and "Pick Path" arrow.
"""

import json
import os
import tempfile
import logging
import math
import zlib
import base64
import xml.etree.ElementTree as ET
from urllib.parse import unquote

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_drawio_xml(file_path):
    """
    Parses a draw.io XML file, handling compression (deflate) and URL encoding.
    Returns the root ElementTree object or None.
    """
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
        
        # Check if it's a compressed diagram
        diagram_node = root.find("diagram")
        if diagram_node is not None and diagram_node.text:
            try:
                # Standard draw.io compression: Base64 -> Deflate
                # Sometimes URL encoded first
                text = diagram_node.text.strip()
                try:
                    decoded = base64.b64decode(text)
                except:
                    # Try url decoding first
                    text = unquote(text)
                    decoded = base64.b64decode(text)
                
                # Deflate (wbits=-15 handles raw deflate streams without headers)
                xml_content = zlib.decompress(decoded, -15).decode('utf-8')
                # Parse the inner XML
                return ET.fromstring(xml_content)
            except Exception as e:
                logger.warning(f"Failed to decompress diagram node: {e}")
                # Fallback: maybe it wasn't compressed?
                return root
        
        # If not compressed, return structure
        return root
    except Exception as e:
        logger.error(f"Error parsing XML: {e}")
        return None

def get_center(geometry):
    """Calculates center (x, y) from mxGeometry element."""
    if geometry is None:
        return (0, 0)
    try:
        x = float(geometry.get("x", 0))
        y = float(geometry.get("y", 0))
        w = float(geometry.get("width", 0))
        h = float(geometry.get("height", 0))
        return (x + w/2, y + h/2)
    except ValueError:
        return (0, 0)

def verify_warehouse_layout(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    fast_movers = [n.lower() for n in metadata.get('fast_movers', [])]
    slow_movers = [n.lower() for n in metadata.get('slow_movers', [])]
    packing_keyword = metadata.get('packing_area_keyword', 'Packing Area').lower()
    zone_threshold = metadata.get('zone_threshold_px', 400) # Distance threshold for Zone A

    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name): os.unlink(temp_json.name)

    # 2. Retrieve Diagram File
    temp_drawio = tempfile.NamedTemporaryFile(delete=False, suffix='.drawio')
    try:
        copy_from_env(result_data.get("diagram_path"), temp_drawio.name)
        root = parse_drawio_xml(temp_drawio.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse diagram: {e}"}
    finally:
        if os.path.exists(temp_drawio.name): os.unlink(temp_drawio.name)

    if root is None:
        return {"passed": False, "score": 0, "feedback": "Corrupt or unreadable diagram file"}

    # 3. Analyze Spatial Layout
    packing_pos = None
    fast_positions = []
    slow_positions = []
    
    # Iterate all cells
    # Find mxGraphModel/root/mxCell or just findall .//mxCell
    cells = root.findall(".//mxCell")
    
    for cell in cells:
        val = cell.get("value", "").lower()
        geo = cell.find("mxGeometry")
        
        if not val or geo is None:
            continue
            
        pos = get_center(geo)
        
        if packing_keyword in val:
            packing_pos = pos
        
        # Check racks
        if "rack" in val:
            for fm in fast_movers:
                if fm in val:
                    fast_positions.append(pos)
                    break
            for sm in slow_movers:
                if sm in val:
                    slow_positions.append(pos)
                    break

    score = 0
    feedback_parts = []
    
    # Scoring: Artifacts
    if result_data.get("pdf_exists"):
        score += 10
        feedback_parts.append("PDF export found (+10)")
    else:
        feedback_parts.append("PDF export missing")

    if result_data.get("diagram_modified"):
        score += 10
        feedback_parts.append("Diagram modified (+10)")

    # Scoring: Spatial Logic
    if packing_pos and fast_positions and slow_positions:
        # Euclidean distance
        avg_fast_dist = sum(math.hypot(p[0]-packing_pos[0], p[1]-packing_pos[1]) for p in fast_positions) / len(fast_positions)
        avg_slow_dist = sum(math.hypot(p[0]-packing_pos[0], p[1]-packing_pos[1]) for p in slow_positions) / len(slow_positions)
        
        # Criterion: Fast < Slow (25 pts)
        if avg_fast_dist < avg_slow_dist:
            score += 25
            feedback_parts.append("Fast movers closer than slow movers (+25)")
            
            # Criterion: Significant difference (15 pts)
            if avg_fast_dist < (avg_slow_dist * 0.7):
                score += 15
                feedback_parts.append("Optimization significant (+15)")
        else:
            feedback_parts.append("Optimization failed: Fast movers further than slow movers")

        # Criterion: Fast Movers in Zone A (Absolute Threshold) (15 pts)
        # Assuming packing is at ~X=650, Zone A is X>400 approx
        # We use distance check < threshold
        if avg_fast_dist < zone_threshold:
            score += 15
            feedback_parts.append(f"Fast movers in Zone A (<{zone_threshold}px) (+15)")
        else:
            feedback_parts.append(f"Fast movers not close enough to Packing (Dist: {int(avg_fast_dist)})")

    else:
        feedback_parts.append("Critical: Could not locate Packing Area or Racks in diagram")

    # 4. VLM Verification (Visual Check for Zone Label and Path)
    # We look at trajectory frames to see if they drew the path/label
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        prompt = """
        You are verifying a warehouse layout diagram.
        Look for two specific visual elements:
        1. A visual label or area marked "Zone A" or "Fast Movers".
        2. A directional arrow or line (Pick Path) drawn through the aisles.
        
        Answer with JSON:
        {"zone_label_visible": bool, "pick_path_visible": bool}
        """
        
        try:
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res and vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("zone_label_visible"):
                    score += 10
                    feedback_parts.append("Zone label visible (+10)")
                if parsed.get("pick_path_visible"):
                    score += 15
                    feedback_parts.append("Pick path visible (+15)")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")

    final_passed = score >= 70
    return {
        "passed": final_passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }