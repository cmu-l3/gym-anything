#!/usr/bin/env python3
import json
import os
import math
import xml.etree.ElementTree as ET
import tempfile
import urllib.parse
import base64
import zlib

def decode_drawio_content(encoded_text):
    """Decompresses the standard draw.io XML content format."""
    try:
        # It's usually URL encoded, then Base64, then Deflate
        decoded = base64.b64decode(encoded_text)
        xml_content = zlib.decompress(decoded, -15).decode('utf-8')
        return xml_content
    except Exception as e:
        return None

def parse_geometry(xml_file):
    """
    Parses the .drawio XML to find lenses and lines.
    Returns a dict with identified components.
    """
    try:
        tree = ET.parse(xml_file)
        root = tree.getroot()
        
        # Draw.io files can be compressed inside the <diagram> tag
        diagram_node = root.find('diagram')
        if diagram_node is not None and diagram_node.text:
            content = decode_drawio_content(diagram_node.text)
            if content:
                root = ET.fromstring(content)
                
        # Find all cells
        cells = root.findall(".//mxCell")
        
        components = {
            "lenses": [],
            "rays": [],
            "labels": []
        }
        
        for cell in cells:
            style = cell.get("style", "").lower()
            val = cell.get("value", "").lower()
            geo = cell.find("mxGeometry")
            
            if geo is None:
                continue

            # Identify Lenses (Ellipse shapes or curved arcs)
            # Users might use 'ellipse' or specific optical shapes if found
            if "ellipse" in style or "shape=mxgraph.basic.arc" in style or "lens" in val:
                try:
                    x = float(geo.get("x", 0))
                    y = float(geo.get("y", 0))
                    w = float(geo.get("width", 0))
                    h = float(geo.get("height", 0))
                    components["lenses"].append({"x": x, "y": y, "w": w, "h": h, "cx": x + w/2, "cy": y + h/2})
                except ValueError:
                    pass

            # Identify Rays (Connectors/Edges)
            if "edge" in cell.attrib and cell.attrib["edge"] == "1":
                # Get source and target points if available
                source_pt = None
                target_pt = None
                
                # Check mxPoint children
                points = geo.findall("mxPoint")
                path_points = []
                for pt in points:
                    pt_type = pt.get("as")
                    try:
                        px = float(pt.get("x", 0))
                        py = float(pt.get("y", 0))
                        if pt_type == "sourcePoint":
                            source_pt = (px, py)
                        elif pt_type == "targetPoint":
                            target_pt = (px, py)
                        else:
                            path_points.append((px, py))
                    except ValueError:
                        pass
                
                components["rays"].append({
                    "source": source_pt,
                    "target": target_pt,
                    "points": path_points
                })

            # Identify Labels
            if val:
                components["labels"].append(val)
                
        return components

    except Exception as e:
        print(f"XML Parse Error: {e}")
        return None

def verify_optical_ray_tracing_telescope(traj, env_info, task_info):
    """
    Verifies the telescope diagram task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": "Could not retrieve task results."}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Retrieve Diagram XML
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.drawio')
    try:
        copy_from_env("/tmp/final_diagram.drawio", temp_xml.name)
        components = parse_geometry(temp_xml.name)
    except Exception:
        components = None
    finally:
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)

    # --- SCORING CRITERIA ---
    score = 0
    feedback = []

    # A. Basic File Checks (20 pts)
    if result_data.get("diagram_modified", False):
        score += 10
        feedback.append("Diagram file modified.")
    else:
        feedback.append("Diagram file not modified.")

    if result_data.get("pdf_exists", False):
        score += 10
        feedback.append("PDF export found.")
    else:
        feedback.append("PDF export missing.")

    if not components:
        return {"passed": False, "score": score, "feedback": "\n".join(feedback) + " - Could not parse diagram XML."}

    # B. Geometric Verification (60 pts)
    lenses = components["lenses"]
    
    # Sort lenses by X position
    lenses.sort(key=lambda l: l["x"])
    
    valid_setup = False
    
    if len(lenses) >= 2:
        # Assume first is objective, second is eyepiece based on X order (light left->right)
        obj = lenses[0]
        eye = lenses[1]
        
        # Calculate separation in pixels
        # Using centroid difference (cx)
        separation = abs(eye["cx"] - obj["cx"])
        
        # Specs: fo=400mm, fe=80mm -> Total = 480mm
        # Scale: 1 grid (10px) = 10mm -> 1px = 1mm
        # Expected separation = 480 px
        expected_sep = 480.0
        tolerance = 30.0 # +/- 30px (3cm) tolerance
        
        if abs(separation - expected_sep) < tolerance:
            score += 30
            feedback.append(f"Lens separation correct (~{int(separation)}mm).")
            valid_setup = True
        else:
            feedback.append(f"Lens separation incorrect. Measured: {int(separation)}mm, Expected: 480mm.")
            
        # Check Relative Sizes
        # Objective (60mm) should be larger than Eyepiece (20mm)
        if obj["h"] > eye["h"]:
            score += 10
            feedback.append("Objective lens correctly larger than Eyepiece.")
        else:
            feedback.append("Lens size ratio incorrect (Objective should be larger).")
            
        # C. Ray Tracing Logic (10 pts)
        # Check if rays converge between the lenses
        # Focal point should be at obj["cx"] + 400
        focal_x = obj["cx"] + 400
        
        rays_converging = 0
        for ray in components["rays"]:
            # Simple check: does the ray have a point near the focal X?
            points = ray.get("points", [])
            if ray.get("target"): points.append(ray["target"])
            if ray.get("source"): points.insert(0, ray["source"])
            
            for pt in points:
                if abs(pt[0] - focal_x) < 20: # Within 20px of focal plane
                    rays_converging += 1
                    break
        
        if rays_converging >= 2:
            score += 10
            feedback.append("Light rays appear to converge at the focal plane.")
        elif rays_converging > 0:
            score += 5
            feedback.append("Some rays pass near focal plane.")
        else:
            feedback.append("Rays do not clearly converge at the focal point.")

    else:
        feedback.append(f"Found {len(lenses)} lenses (need at least 2).")

    # D. Labels (10 pts)
    required_labels = ["objective", "eyepiece", "focal"]
    found_labels = 0
    found_text = " ".join(components["labels"]).lower()
    
    for lbl in required_labels:
        if lbl in found_text:
            found_labels += 1
    
    if found_labels >= 3:
        score += 10
        feedback.append("All required labels present.")
    elif found_labels > 0:
        score += 5
        feedback.append("Some labels present.")

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }