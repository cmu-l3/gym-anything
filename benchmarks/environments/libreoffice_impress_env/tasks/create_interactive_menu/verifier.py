#!/usr/bin/env python3
"""
Verifier for create_interactive_menu task.

Verifies:
1. File existence and modification.
2. Presence of navigation shapes on Slide 1.
3. Presence of Home button on Slide 6.
4. Correct 'onclick' interactions (goto-page) configured for specific shapes.
"""

import json
import tempfile
import os
import zipfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_interactive_menu(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_file', 'orientation_kiosk_interactive.odp')
    
    # Slide mapping (0-based index)
    # Slide 1 (Home) -> Index 0
    # Slide 2 (History) -> Index 1
    # Slide 4 (Benefits) -> Index 3
    # Slide 6 (Policies) -> Index 5
    target_mappings = {
        "History": 1,
        "Benefits": 3,
        "Policies": 5
    }
    home_target_index = 0

    # 1. Check Export Result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            export_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load export result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if not export_data.get('output_exists'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"❌ Target file '{os.path.basename(expected_path)}' not found. Did you save it with the correct name?"
        }

    # 2. Analyze ODP Content
    temp_odp = tempfile.NamedTemporaryFile(delete=False, suffix='.odp')
    try:
        copy_from_env(expected_path, temp_odp.name)
        
        if not zipfile.is_zipfile(temp_odp.name):
            return {"passed": False, "score": 0, "feedback": "❌ Output file is not a valid ODP/ZIP file."}

        with zipfile.ZipFile(temp_odp.name, 'r') as z:
            with z.open('content.xml') as f:
                tree = ET.parse(f)
                root = tree.getroot()

        # Namespaces
        ns = {
            'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
            'presentation': 'urn:oasis:names:tc:opendocument:xmlns:presentation:1.0',
            'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
            'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0'
        }

        # Find all slides (draw:page)
        # In ODP, slides are usually direct children of office:presentation or office:body/office:presentation
        slides = root.findall('.//draw:page', ns)
        
        if not slides:
            return {"passed": False, "score": 0, "feedback": "❌ Could not parse slides from ODP file."}

        logger.info(f"Found {len(slides)} slides.")
        
        # Helper to get page names for linking
        # ODP interactions link to page names (e.g. "page1"), not indices directly
        page_names = [s.get(f"{{{ns['draw']}}}name") for s in slides]
        
        score = 0
        feedback_parts = []
        
        # --- VERIFY SLIDE 1 (Index 0) ---
        slide1 = slides[0]
        slide1_text_shapes = []
        
        # Find shapes with text and interactions
        # We look for draw:custom-shape, draw:frame, or draw:rect
        for shape in slide1.findall('.//*', ns):
            # Get text content
            texts = [t.text for t in shape.findall('.//text:p', ns) if t.text]
            full_text = " ".join(texts).strip()
            
            # Check for event listener (interaction)
            event_listener = shape.find(f"{{{ns['presentation']}}}event-listener", ns)
            
            if full_text:
                slide1_text_shapes.append({
                    'text': full_text, 
                    'listener': event_listener
                })

        # Check for our 3 specific buttons
        buttons_found = 0
        links_correct = 0
        
        for btn_name, target_idx in target_mappings.items():
            # Find shape matching button name (case insensitive partial match)
            match = next((s for s in slide1_text_shapes if btn_name.lower() in s['text'].lower()), None)
            
            if match:
                buttons_found += 1
                listener = match['listener']
                if listener is not None:
                    action = listener.get(f"{{{ns['presentation']}}}action")
                    # Target can be page-name
                    target_page_name = listener.get(f"{{{ns['presentation']}}}page-name")
                    
                    # Verify action is goto-page
                    if action == "goto-page" or action == "last-page" or action == "first-page" or action == "previous-page" or action == "next-page":
                         # Verify target
                         # We expect "goto-page" and a specific target name
                         if action == "goto-page" and target_page_name:
                             # Check if target name corresponds to the correct slide index
                             # The target name in ODP XML usually matches the draw:name of the target slide
                             expected_target_name = page_names[target_idx] if target_idx < len(page_names) else "UNKNOWN"
                             
                             if target_page_name == expected_target_name:
                                 links_correct += 1
                                 feedback_parts.append(f"✅ '{btn_name}' link correct.")
                             else:
                                 feedback_parts.append(f"❌ '{btn_name}' links to wrong slide ('{target_page_name}' vs '{expected_target_name}').")
                         else:
                             feedback_parts.append(f"❌ '{btn_name}' has interaction but invalid target.")
                    else:
                        feedback_parts.append(f"❌ '{btn_name}' has interaction but wrong action type ({action}).")
                else:
                    feedback_parts.append(f"❌ '{btn_name}' button found but has no interaction.")
            else:
                feedback_parts.append(f"❌ '{btn_name}' button text not found on Slide 1.")

        # --- VERIFY SLIDE 6 (Index 5) ---
        if len(slides) > 5:
            slide6 = slides[5]
            home_found = False
            home_correct = False
            
            for shape in slide6.findall('.//*', ns):
                texts = [t.text for t in shape.findall('.//text:p', ns) if t.text]
                full_text = " ".join(texts).strip()
                
                if "home" in full_text.lower():
                    home_found = True
                    event_listener = shape.find(f"{{{ns['presentation']}}}event-listener", ns)
                    
                    if event_listener is not None:
                        action = event_listener.get(f"{{{ns['presentation']}}}action")
                        target_page_name = event_listener.get(f"{{{ns['presentation']}}}page-name")
                        
                        # Accept explicit goto-page to Slide 1 OR action="first-page"
                        if action == "first-page":
                            home_correct = True
                        elif action == "goto-page" and target_page_name == page_names[0]:
                            home_correct = True
                    break
            
            if home_correct:
                feedback_parts.append("✅ 'Home' button on Slide 6 correct.")
                score += 15
            elif home_found:
                feedback_parts.append("❌ 'Home' button found on Slide 6 but link is missing/wrong.")
                score += 5
            else:
                feedback_parts.append("❌ 'Home' button not found on Slide 6.")
        else:
             feedback_parts.append("❌ Presentation has fewer than 6 slides.")

        # Scoring Logic
        # 3 Main buttons: 15 pts creation + 10 pts linking each = 75 pts max
        # Home button: 15 pts max
        # File saved: 10 pts
        
        score += 10 # File exists
        
        # Calculate button scores
        score += (buttons_found * 10) # 10 pts for creating each button
        score += (links_correct * 15) # 15 pts for correct linking each
        
        if score > 100: score = 100
        
        passed = score >= 75
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_odp.name):
            os.unlink(temp_odp.name)