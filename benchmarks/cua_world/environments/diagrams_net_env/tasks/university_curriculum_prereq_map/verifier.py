#!/usr/bin/env python3
import json
import os
import tempfile
import xml.etree.ElementTree as ET
import base64
import zlib
import re
from urllib.parse import unquote

def decode_drawio_xml(xml_content):
    """
    Decodes draw.io's compressed XML format.
    Standard format: <mxfile><diagram>ENCODED_STRING</diagram></mxfile>
    Encoded string is: URL_Encoded -> Base64_Decoded -> Deflate_Decompressed (raw, -15)
    """
    try:
        # Check if it's a plain XML first
        if b"<mxGraphModel" in xml_content:
            return xml_content

        # Parse the container XML
        root = ET.fromstring(xml_content)
        diagram_node = root.find('diagram')
        
        if diagram_node is not None and diagram_node.text:
            # 1. Base64 Decode
            b64_data = base64.b64decode(diagram_node.text)
            # 2. Deflate Decompress (raw wbits=-15 is crucial for draw.io)
            decompressed = zlib.decompress(b64_data, -15)
            # 3. URL Decode
            final_xml = unquote(decompressed.decode('utf-8'))
            return final_xml.encode('utf-8')
            
        return xml_content # Return original if structure doesn't match expected compression
    except Exception as e:
        print(f"Warning: XML decoding failed or file is plain text. Error: {e}")
        return xml_content

def analyze_diagram_structure(drawio_path):
    """Parses .drawio file to count nodes, edges, and find specific labels."""
    stats = {
        "node_count": 0,
        "edge_count": 0,
        "labels_found": set(),
        "swimlanes_found": False,
        "colors_used": set(),
        "prereq_connections": []
    }
    
    if not os.path.exists(drawio_path):
        return stats

    try:
        with open(drawio_path, 'rb') as f:
            raw_content = f.read()
            
        xml_content = decode_drawio_xml(raw_content)
        
        # Parse graph model
        # Note: Depending on decode, we might have <mxGraphModel> root or just a string
        if isinstance(xml_content, bytes):
            xml_content = xml_content.decode('utf-8')
            
        # Regex is often more robust for loose XML parsing than ElementTree if namespaces get messy
        # But let's try ET first on the graph model part
        graph_model_match = re.search(r'(<mxGraphModel.*?</mxGraphModel>)', xml_content, re.DOTALL)
        if graph_model_match:
            xml_content = graph_model_match.group(1)
            
        root = ET.fromstring(xml_content)
        
        # Build ID map for connections
        id_to_label = {}
        
        for cell in root.findall(".//mxCell"):
            style = cell.get('style', '')
            value = cell.get('value', '')
            cell_id = cell.get('id')
            
            # Detect Nodes (vertices)
            if cell.get('vertex') == '1':
                # Check for Swimlane
                if 'swimlane' in style.lower():
                    stats['swimlanes_found'] = True
                    continue # Don't count swimlane header as a course node usually
                
                stats['node_count'] += 1
                
                # Extract label text (clean HTML)
                clean_label = re.sub(r'<[^>]+>', '', value).strip()
                if clean_label:
                    id_to_label[cell_id] = clean_label
                    stats['labels_found'].add(clean_label.upper())
                
                # Extract Color
                # style often contains "fillColor=#dae8fc;"
                color_match = re.search(r'fillColor=([^;]+)', style)
                if color_match:
                    stats['colors_used'].add(color_match.group(1))

            # Detect Edges
            if cell.get('edge') == '1':
                stats['edge_count'] += 1
                source = cell.get('source')
                target = cell.get('target')
                if source and target:
                    stats['prereq_connections'].append((source, target))

        # Resolve connection IDs to labels
        resolved_connections = []
        for src, tgt in stats['prereq_connections']:
            src_lbl = id_to_label.get(src, "Unknown")
            tgt_lbl = id_to_label.get(tgt, "Unknown")
            resolved_connections.append((src_lbl.upper(), tgt_lbl.upper()))
        stats['prereq_connections'] = resolved_connections
        
    except Exception as e:
        print(f"XML Parsing Error: {e}")
        
    return stats

def verify_university_curriculum_prereq_map(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Get Metadata & Result JSON
    metadata = task_info.get('metadata', {})
    expected_courses = metadata.get('required_courses', [])
    
    # Load task result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    copy_from_env("/tmp/task_result.json", temp_result.name)
    with open(temp_result.name, 'r') as f:
        task_result = json.load(f)
    os.unlink(temp_result.name)
    
    # 3. Copy Actual Diagram File for Analysis
    temp_drawio = tempfile.NamedTemporaryFile(delete=False, suffix='.drawio')
    copy_from_env("/home/ga/Diagrams/ai_curriculum_map.drawio", temp_drawio.name)
    
    # 4. Analyze Diagram
    stats = analyze_diagram_structure(temp_drawio.name)
    os.unlink(temp_drawio.name)
    
    # 5. Scoring Logic
    score = 0
    feedback = []
    
    # Criteria A: Files Exist (20 pts)
    files_ok = task_result['diagram_file']['exists'] and task_result['diagram_file']['modified_during_task']
    if files_ok:
        score += 10
        feedback.append("Diagram file created and modified.")
    else:
        feedback.append("Diagram file missing or not modified.")
        
    if task_result['pdf_file']['exists']:
        score += 10
        feedback.append("PDF export found.")
    else:
        feedback.append("PDF export missing.")

    # Criteria B: Node Count & Content (30 pts)
    # Expect ~20 nodes. Give partial credit.
    node_count = stats['node_count']
    if node_count >= 18:
        score += 10
        feedback.append(f"Node count good ({node_count}).")
    elif node_count >= 10:
        score += 5
        feedback.append(f"Node count low ({node_count}, expected ~20).")
    else:
        feedback.append(f"Node count insufficient ({node_count}).")

    # Check for specific course codes
    found_courses = 0
    for req in expected_courses:
        # Check if any label contains the required code
        if any(req in label for label in stats['labels_found']):
            found_courses += 1
    
    if found_courses == len(expected_courses):
        score += 20
        feedback.append("All key course codes found.")
    elif found_courses >= len(expected_courses) // 2:
        score += 10
        feedback.append(f"Some key course codes missing ({found_courses}/{len(expected_courses)} found).")
    else:
        feedback.append("Most key course codes missing.")

    # Criteria C: Edges & Logic (30 pts)
    edge_count = stats['edge_count']
    if edge_count >= 15:
        score += 15
        feedback.append(f"Edge count good ({edge_count}).")
    elif edge_count >= 8:
        score += 7
        feedback.append(f"Edge count low ({edge_count}).")
        
    # Check specific chains (simplified check)
    # We look for connections roughly matching metadata
    # (Checking exact graph topology is brittle due to label matching issues, so we rely on count + sampling)
    chain_score = 0
    # Check if CS101 connects to anything (it should be a prerequisite)
    cs101_connected = any("CS101" in src for src, tgt in stats['prereq_connections'])
    if cs101_connected: chain_score += 5
    
    # Check if AI connects to ML
    ai_ml_connected = any(("CS300" in src and "CS310" in tgt) for src, tgt in stats['prereq_connections'])
    if ai_ml_connected: chain_score += 10
    
    score += chain_score
    if chain_score > 0:
        feedback.append("Verified key prerequisite connections.")

    # Criteria D: Structure & Style (20 pts)
    if stats['swimlanes_found']:
        score += 10
        feedback.append("Swimlanes/Containers used.")
    else:
        feedback.append("No Swimlanes detected.")
        
    if len(stats['colors_used']) >= 2:
        score += 10
        feedback.append(f"Color coding used ({len(stats['colors_used'])} colors found).")
    else:
        feedback.append("Nodes appear to be monochromatic (missing color coding).")

    # Final Verdict
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }