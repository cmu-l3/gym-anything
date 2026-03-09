#!/usr/bin/env python3
"""
Verifier for UML Design Pattern Refactoring Task.
Parses the .drawio XML file to verify the presence of specific classes, interfaces,
and design patterns.
"""

import json
import os
import sys
import tempfile
import logging
import base64
import zlib
import urllib.parse
from lxml import etree

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("verifier")

def decode_drawio_content(raw_xml):
    """
    Decodes draw.io compressed XML content.
    draw.io files often wrap the diagram in <mxfile><diagram>...compressed...</diagram></mxfile>.
    The compressed part is URL-encoded, Base64-encoded, then Deflate-compressed.
    """
    try:
        # Check if it is a raw XML (uncompressed) first
        if raw_xml.strip().startswith('<mxGraphModel'):
            return raw_xml
            
        root = etree.fromstring(raw_xml.encode('utf-8'))
        
        # If root is mxfile, iterate diagrams
        if root.tag == 'mxfile':
            diagram_node = root.find('diagram')
            if diagram_node is not None and diagram_node.text:
                # Decode: URL Decode -> Base64 Decode -> Inflate (no header)
                data = diagram_node.text.strip()
                try:
                    data = urllib.parse.unquote(data)
                    data = base64.b64decode(data)
                    # -15 for raw deflate (no zlib header)
                    xml_content = zlib.decompress(data, -15).decode('utf-8')
                    # The result is URL encoded again inside the zip? Sometimes.
                    # Usually it results in the <mxGraphModel> directly.
                    return urllib.parse.unquote(xml_content)
                except Exception as e:
                    logger.error(f"Error decompression: {e}")
                    return raw_xml # Return raw if decompression fails, maybe it wasn't compressed
        
        return raw_xml
    except Exception as e:
        logger.error(f"Error parsing XML structure: {e}")
        return raw_xml

def verify_uml_design_pattern_refactoring(traj, env_info, task_info):
    """
    Verifies the UML refactoring task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_strategies = set(metadata.get('required_strategies', []))
    required_observers = set(metadata.get('required_observers', []))
    required_factories = set(metadata.get('required_factories', []))

    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result metadata: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check Basic File Requirements (20 points)
    score = 0
    feedback = []
    
    if result_data.get('file_modified', False):
        score += 10
        feedback.append("Diagram file was modified.")
    else:
        feedback.append("Diagram file was NOT modified.")

    if result_data.get('export_exists', False) and result_data.get('export_size', 0) > 1000:
        score += 10
        feedback.append("PNG export exists and has content.")
    else:
        feedback.append("PNG export missing or empty.")

    # 3. Retrieve and Parse Diagram File (80 points)
    # Strategy: 25pts, Observer: 25pts, Factory: 30pts
    temp_diagram = tempfile.NamedTemporaryFile(delete=False, suffix='.drawio')
    try:
        copy_from_env(result_data.get('diagram_path', ''), temp_diagram.name)
        with open(temp_diagram.name, 'r', encoding='utf-8', errors='ignore') as f:
            raw_content = f.read()
        
        decoded_xml = decode_drawio_content(raw_content)
        
        # We search for class names in the decoded XML
        # draw.io stores text labels in 'value' attributes of 'mxCell'
        
        found_strategies = []
        found_observers = []
        found_factories = []
        
        # Normalize content for searching
        searchable_content = decoded_xml.lower()
        
        # Check Strategy Pattern
        for item in required_strategies:
            if item.lower() in searchable_content:
                found_strategies.append(item)
        
        # Check Observer Pattern
        for item in required_observers:
            if item.lower() in searchable_content:
                found_observers.append(item)
                
        # Check Factory Pattern
        for item in required_factories:
            if item.lower() in searchable_content:
                found_factories.append(item)

        # Scoring Logic
        
        # Strategy (Need at least interface + 2 concretes)
        if len(found_strategies) >= 3:
            score += 25
            feedback.append(f"Strategy Pattern: Verified ({len(found_strategies)}/{len(required_strategies)} classes found).")
        elif len(found_strategies) > 0:
            score += 10
            feedback.append(f"Strategy Pattern: Partial ({len(found_strategies)} classes found).")
        else:
            feedback.append("Strategy Pattern: Not found.")

        # Observer (Need at least interface + 2 concretes)
        if len(found_observers) >= 3:
            score += 25
            feedback.append(f"Observer Pattern: Verified ({len(found_observers)}/{len(required_observers)} classes found).")
        elif len(found_observers) > 0:
            score += 10
            feedback.append(f"Observer Pattern: Partial ({len(found_observers)} classes found).")
        else:
            feedback.append("Observer Pattern: Not found.")

        # Factory (Need at least factories + providers)
        # This is larger, so threshold is higher (e.g. 4 classes)
        if len(found_factories) >= 4:
            score += 30
            feedback.append(f"Factory Method Pattern: Verified ({len(found_factories)}/{len(required_factories)} classes found).")
        elif len(found_factories) > 0:
            score += 10
            feedback.append(f"Factory Method Pattern: Partial ({len(found_factories)} classes found).")
        else:
            feedback.append("Factory Method Pattern: Not found.")
            
        # Check for Interface Stereotypes
        if "&lt;&lt;interface&gt;&gt;" in searchable_content or "«interface»" in searchable_content:
            feedback.append("Interface stereotypes detected.")
        else:
            feedback.append("Warning: Interface stereotypes (<<interface>>) not clearly detected.")

    except Exception as e:
        feedback.append(f"Failed to parse diagram XML: {e}")
    finally:
        if os.path.exists(temp_diagram.name):
            os.unlink(temp_diagram.name)

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }