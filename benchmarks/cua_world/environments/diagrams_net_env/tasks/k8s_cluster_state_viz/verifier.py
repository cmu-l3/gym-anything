#!/usr/bin/env python3
import json
import os
import tempfile
import gzip
import zlib
import base64
import re
import xml.etree.ElementTree as ET
from urllib.parse import unquote

def decode_drawio_xml(raw_xml_data):
    """
    Decodes the mxfile content from a .drawio file.
    Draw.io files are often XML wrapping a compressed, base64-encoded payload.
    """
    try:
        tree = ET.ElementTree(ET.fromstring(raw_xml_data))
        root = tree.getroot()
        
        # If it's a standard mxfile with a diagram child
        for diagram in root.findall('diagram'):
            # If text is present, it might be compressed
            if diagram.text and diagram.text.strip():
                # 1. Base64 decode
                try:
                    data = base64.b64decode(diagram.text)
                    # 2. Deflate (raw or zlib)
                    # Draw.io usually uses raw deflate (no header), zlib.decompress w/ -15
                    try:
                        decoded = zlib.decompress(data, -15).decode('utf-8')
                        # It is now URL encoded XML
                        final_xml = unquote(decoded)
                        return final_xml
                    except Exception:
                        # Fallback for standard zlib
                        return zlib.decompress(data).decode('utf-8')
                except Exception:
                    # Maybe it's not encoded, just plain text?
                    return diagram.text
            
        # If we couldn't find/decode diagram, maybe it's uncompressed XML directly
        return raw_xml_data.decode('utf-8')
    except Exception as e:
        print(f"Error decoding XML: {e}")
        return str(raw_xml_data)

def parse_geometry(cell):
    """Extracts geometry (x, y, width, height) from an mxCell."""
    geo = cell.find('mxGeometry')
    if geo is not None:
        return {
            'x': float(geo.get('x', 0)),
            'y': float(geo.get('y', 0)),
            'width': float(geo.get('width', 0)),
            'height': float(geo.get('height', 0))
        }
    return None

def is_contained(inner, outer):
    """Checks if inner rect is visually inside outer rect."""
    if not inner or not outer:
        return False
    # Simple bounding box check
    return (inner['x'] >= outer['x'] and
            inner['y'] >= outer['y'] and
            (inner['x'] + inner['width']) <= (outer['x'] + outer['width']) and
            (inner['y'] + inner['height']) <= (outer['y'] + outer['height']))

def verify_k8s_cluster_state_viz(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}
    
    metadata = task_info.get('metadata', {})
    expected_nodes = metadata.get('expected_nodes', [])
    node_cpu_totals = metadata.get('node_cpu_totals', {})
    crashing_pod = metadata.get('crashing_pod', "payment-db-master")
    
    score = 0
    feedback = []
    
    # 2. Retrieve Files
    # Get the metadata result JSON
    meta_path = tempfile.mktemp()
    drawio_path = tempfile.mktemp()
    
    try:
        # Load task_result.json
        copy_from_env("/tmp/task_result.json", meta_path)
        with open(meta_path, 'r') as f:
            task_result = json.load(f)
            
        # Basic File Checks
        if task_result.get('drawio_exists') and task_result.get('drawio_created_during_task'):
            score += 10
            feedback.append("Draw.io file created.")
        else:
            return {"passed": False, "score": 0, "feedback": "No .drawio file created."}
            
        if task_result.get('png_exists'):
            score += 5
            feedback.append("PNG export found.")
        
        # Load the actual .drawio file content
        copy_from_env("/home/ga/Diagrams/cluster_state.drawio", drawio_path)
        with open(drawio_path, 'rb') as f:
            raw_data = f.read()
            
        # Decode and Parse XML
        xml_content = decode_drawio_xml(raw_data)
        # Wrap in fake root if needed for parsing partials, but decode usually gives full XML
        # If decode returned plain XML string, wrap it to parse
        try:
            # Check if it starts with <mxGraphModel> or similar
            if xml_content.strip().startswith('<mxGraphModel'):
                root = ET.fromstring(xml_content)
            else:
                # It might be a full <mxfile>
                root = ET.fromstring(xml_content)
                # If it's mxfile, drill down to root of graph
                if root.tag == 'mxfile':
                    # Already handled in decode, but double check
                    pass
        except ET.ParseError:
            # Fallback for simple wrapper
             root = ET.fromstring(f"<root>{xml_content}</root>")

        # Find all cells
        # Flatten structure to find cells anywhere
        cells = root.findall(".//mxCell")
        
        # Analysis Data Structures
        node_shapes = {}  # Label -> Geometry
        pod_shapes = {}   # Label -> (Geometry, Style)
        all_labels = []
        
        for cell in cells:
            val = cell.get('value', '')
            style = cell.get('style', '')
            geo = parse_geometry(cell)
            
            # Sanitize label (remove HTML)
            label = re.sub(r'<[^>]+>', '', val).strip()
            all_labels.append(label)
            
            # Identify Nodes
            for n_name in expected_nodes:
                if n_name in label:
                    if geo and geo['width'] > 50: # Assume nodes are bigger
                        node_shapes[n_name] = geo
            
            # Identify Pods
            # We look for pod names from the expected data
            # (In a real implementation we might read the json, here we assume standard naming)
            if "frontend" in label or "backend" in label or "redis" in label or "service" in label or "db-master" in label:
                if geo:
                    pod_shapes[label] = (geo, style)

        # 3. Verify Node Shapes
        found_nodes = len(node_shapes)
        if found_nodes == 3:
            score += 15
            feedback.append("All 3 Nodes found.")
        elif found_nodes > 0:
            score += 5
            feedback.append(f"Found {found_nodes}/3 Nodes.")
        else:
            feedback.append("No Node shapes found (check labels).")

        # 4. Verify Pod Count
        # We expect 15 pods. Loose matching allows for "frontend-01" etc.
        unique_pods = len(pod_shapes)
        if unique_pods >= 15:
            score += 15
            feedback.append(f"Found {unique_pods} Pods.")
        elif unique_pods >= 10:
            score += 10
            feedback.append(f"Found {unique_pods}/15 Pods.")
        
        # 5. Verify Containment (Pod inside Node)
        # We need to map pods to expected nodes to check correctness
        # For simplicity, we just check if *every* pod is inside *some* node
        # And specifically check a few key ones if possible.
        # Let's check generally: "Are pods inside the correct labeled nodes?"
        
        # Reconstruct ground truth mapping roughly
        # Node A: frontend, redis
        # Node B: payment, auth, user
        # Node C: backend
        
        correct_placements = 0
        total_checked = 0
        
        for pod_label, (p_geo, _) in pod_shapes.items():
            assigned_node = None
            if any(x in pod_label for x in ["frontend", "redis"]):
                assigned_node = "worker-us-east-1a"
            elif any(x in pod_label for x in ["payment", "auth", "user"]):
                assigned_node = "worker-us-east-1b"
            elif "backend" in pod_label:
                assigned_node = "worker-us-east-1c"
            
            if assigned_node and assigned_node in node_shapes:
                total_checked += 1
                # Check geometric containment
                # Note: Coordinates in draw.io can be relative if grouped. 
                # If 'parent' attribute is set to the node ID, that's valid too.
                # However, visual containment (absolute coords) is harder to parse without full graph logic.
                # We will relax this: Check if they are grouped (parent relationship) OR geometric overlap.
                
                # Check 1: Geometry overlap (assuming absolute coords or simple layout)
                # In many simple draw.io creates, users just drag shapes over others.
                if is_contained(p_geo, node_shapes[assigned_node]):
                    correct_placements += 1
        
        # Scoring placement
        if total_checked > 0:
            ratio = correct_placements / total_checked
            if ratio > 0.8:
                score += 25
                feedback.append("Pods correctly placed in Nodes.")
            elif ratio > 0.4:
                score += 10
                feedback.append("Some pods placed correctly.")
        
        # 6. Verify CrashLoopBackOff Styling
        # Expected crashing pod: payment-db-master
        # Look for red color in style
        crash_pod_data = None
        for label, data in pod_shapes.items():
            if crashing_pod in label:
                crash_pod_data = data
                break
        
        if crash_pod_data:
            style_str = crash_pod_data[1].lower()
            # Check for red fill codes
            if "f8cecc" in style_str or "ff0000" in style_str or "red" in style_str:
                score += 15
                feedback.append("Crashing pod correctly colored red.")
            else:
                feedback.append("Crashing pod found but not colored red.")
        else:
            feedback.append("Crashing pod not found.")

        # 7. Verify Math (CPU Totals)
        # Look for strings like "400m", "1250m", "2400m" in the labels
        # Or "0.4", "1.25", "2.4" if they converted units (though task said 'm')
        
        found_math = 0
        full_text = " ".join(all_labels)
        
        if "400m" in full_text: found_math += 1
        if "1250m" in full_text: found_math += 1
        if "2400m" in full_text: found_math += 1
        
        if found_math == 3:
            score += 20
            feedback.append("All CPU totals calculated correctly.")
        elif found_math > 0:
            score += 10
            feedback.append(f"Found {found_math}/3 CPU totals.")
        else:
            feedback.append("CPU totals missing or incorrect.")

        # 8. Formatting / Style (5 pts free if > 50)
        if score > 50:
            score += 10
            feedback.append("Formatting bonus.")

    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Verification Error: {str(e)}"}
    finally:
        # Cleanup
        if os.path.exists(meta_path): os.remove(meta_path)
        if os.path.exists(drawio_path): os.remove(drawio_path)

    return {
        "passed": score >= 65,
        "score": min(score, 100),
        "feedback": " ".join(feedback)
    }