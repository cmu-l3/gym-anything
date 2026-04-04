#!/usr/bin/env python3
"""
Verifier for Convert List to Process Diagram task.

Checks:
1. File exists and was modified.
2. Slide 2 contains shapes (Chevrons preferred).
3. The expected text strings are found INSIDE shapes/objects, not in a list structure.
4. Shapes are aligned horizontally (similar Y coordinates).
5. Shapes have distinct colors.
"""

import json
import tempfile
import os
import zipfile
import xml.etree.ElementTree as ET
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_process_diagram(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_texts = metadata.get('expected_texts', ["Market Analysis", "Prototype Development", "Global Release"])
    target_file = metadata.get('target_file')

    # Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result.get('output_exists') or not result.get('file_modified'):
        return {"passed": False, "score": 0, "feedback": "Presentation file was not saved or modified."}

    # Retrieve and parse ODP file
    temp_odp = tempfile.NamedTemporaryFile(delete=False, suffix='.odp')
    try:
        copy_from_env(target_file, temp_odp.name)
        
        # ODP is a zip file. We need to parse content.xml
        with zipfile.ZipFile(temp_odp.name, 'r') as z:
            with z.open('content.xml') as f:
                tree = ET.parse(f)
                root = tree.getroot()
        
        # Namespaces
        ns = {
            'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
            'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
            'svg': 'urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0',
            'presentation': 'urn:oasis:names:tc:opendocument:xmlns:presentation:1.0'
        }

        # Find Slide 2
        slides = root.findall('.//draw:page', ns)
        if len(slides) < 2:
            return {"passed": False, "score": 0, "feedback": "Presentation has fewer than 2 slides."}
        
        slide2 = slides[1]
        
        # Analyze Slide 2 Objects
        shapes = []
        all_text_elements = []
        
        # Helper to recursively get text from an element
        def get_text(elem):
            text_content = []
            if elem.text: text_content.append(elem.text)
            for child in elem:
                text_content.extend(get_text(child))
                if child.tail: text_content.append(child.tail)
            return "".join(text_content).strip()

        # Iterate over shapes in Slide 2
        # We look for draw:custom-shape (which chevrons usually are) or other shape types
        for shape in slide2.findall('.//draw:custom-shape', ns) + slide2.findall('.//draw:rect', ns):
            # Get geometry info
            y_pos = shape.get(f"{{{ns['svg']}}}y")
            x_pos = shape.get(f"{{{ns['svg']}}}x")
            fill_color = shape.get(f"{{{ns['draw']}}}fill-color")
            
            # Get text content inside this shape
            shape_text = get_text(shape)
            
            shapes.append({
                'type': 'shape',
                'text': shape_text,
                'y': y_pos,
                'x': x_pos,
                'color': fill_color
            })
            
            if shape_text:
                all_text_elements.append(shape_text)

        # Iterate over text boxes (legacy frames) just in case
        for frame in slide2.findall('.//draw:frame', ns):
            # Skip if it's already counted as part of a custom shape (nested)
            # But frames are usually top level.
            # Check if this frame contains the bullet list (we want this GONE or Empty)
            pass

        # === Scoring ===
        score = 0
        feedback_parts = []
        
        # Criterion 1: Text Persistence (30 pts)
        found_texts = 0
        for expected in expected_texts:
            # Check if expected text is in any of the shapes
            if any(expected in s['text'] for s in shapes):
                found_texts += 1
        
        if found_texts == 3:
            score += 30
            feedback_parts.append("All text content preserved in shapes")
        elif found_texts > 0:
            score += 10 * found_texts
            feedback_parts.append(f"Some text content preserved ({found_texts}/3)")
        else:
            feedback_parts.append("Text content missing")

        # Criterion 2: Shape Count (20 pts)
        # We expect at least 3 shapes that contain text
        text_shapes = [s for s in shapes if any(t in s['text'] for t in expected_texts)]
        if len(text_shapes) >= 3:
            score += 20
            feedback_parts.append("Correct number of shapes found")
        else:
            feedback_parts.append(f"Insufficient shapes found ({len(text_shapes)})")

        # Criterion 3: Alignment (20 pts)
        aligned = False
        if len(text_shapes) >= 3:
            # Parse Y coordinates (e.g., "12.5cm", "300pt") - simplified check
            # We'll just check if raw strings are identical or very close if parsed
            # Since parsing units is hard, we check if they are identical or if we can extract numbers
            ys = []
            for s in text_shapes:
                y_str = s['y']
                if y_str:
                    # Extract numeric part
                    import re
                    match = re.match(r"([\d\.]+)", y_str)
                    if match:
                        ys.append(float(match.group(1)))
            
            if len(ys) >= 3:
                max_diff = max(ys) - min(ys)
                # Assuming same unit, if max diff is small (< 10% of value or < 0.5 unit)
                if max_diff < 1.0: # arbitrary small tolerance
                    aligned = True
            
        if aligned:
            score += 20
            feedback_parts.append("Shapes appear horizontally aligned")
        elif len(text_shapes) >= 3:
            feedback_parts.append("Shapes do not appear aligned")
        
        # Criterion 4: Colors (10 pts)
        # Check if colors are different
        colors = set(s['color'] for s in text_shapes if s['color'])
        if len(colors) >= 2: # At least 2 distinct colors (gradient)
            score += 10
            feedback_parts.append("Color variation detected")
        elif len(colors) == 1:
            feedback_parts.append("All shapes have same color (no gradient)")
        
        # Criterion 5: File Modified (20 pts)
        score += 20 # If we got here, file was modified
        feedback_parts.append("File saved successfully")

        return {
            "passed": score >= 70,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Error parsing ODP: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Verification failed due to parsing error: {str(e)}"
        }
    finally:
        if os.path.exists(temp_odp.name):
            os.unlink(temp_odp.name)