#!/usr/bin/env python3
"""
Verifier for customize_bullet_style task.
"""

import json
import zipfile
import xml.etree.ElementTree as ET
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_customize_bullet_style(traj, env_info, task_info):
    """
    Verify that the bullet style was customized correctly.
    
    Criteria:
    1. File modified (Anti-gaming) - 10 pts
    2. Bullet character is a checkmark - 35 pts
    3. Bullet color is green - 35 pts
    4. Text content preserved - 10 pts
    5. VLM Verification (Visual confirmation) - 10 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_chars = metadata.get('expected_chars', ["✓", "✔", "☑", "✅", "🗸"])
    expected_colors = metadata.get('expected_colors', ["#008000", "#006400", "green"])
    required_text = metadata.get('required_text_snippets', [])

    # Load result JSON
    result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", result_file.name)
        with open(result_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(result_file.name):
            os.unlink(result_file.name)

    # Basic Checks
    score = 0
    feedback_parts = []
    
    if not result_data.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "Target file does not exist"}

    if result_data.get("file_modified"):
        score += 10
        feedback_parts.append("File modified")
    else:
        feedback_parts.append("File NOT modified")

    # Analyze ODP File
    odp_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.odp')
    try:
        copy_from_env(result_data["file_path"], odp_temp.name)
        
        char_correct = False
        color_correct = False
        content_preserved = False
        
        with zipfile.ZipFile(odp_temp.name, 'r') as z:
            content_xml = z.read('content.xml')
            styles_xml = z.read('styles.xml')
            
            content_root = ET.fromstring(content_xml)
            styles_root = ET.fromstring(styles_xml)
            
            ns = {
                'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
                'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
                'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0',
                'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
                'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0'
            }
            
            # Check content preservation
            full_text = " ".join([elem.text for elem in content_root.findall('.//text:p', ns) if elem.text])
            if all(snippet in full_text for snippet in required_text):
                content_preserved = True
                score += 10
                feedback_parts.append("Content preserved")
            else:
                feedback_parts.append("Content text missing/modified")

            # Find list styles
            # 1. Find paragraph with specific text to get its list style name
            target_list_style_name = None
            for p in content_root.findall('.//text:p', ns):
                if p.text and "QR Code" in p.text:
                    target_list_style_name = p.get(f"{{{ns['text']}}}list-style-name")
                    # Sometimes the style is on the style, not the paragraph directly
                    if not target_list_style_name:
                         style_name = p.get(f"{{{ns['text']}}}style-name")
                         # Logic to look up style definition would go here, 
                         # but usually direct formatting or list styles are directly linked.
                    break
            
            # Collect all relevant list styles (automatic and named)
            list_styles = []
            
            # Check automatic styles in content.xml
            auto_styles = content_root.find('office:automatic-styles', ns)
            if auto_styles:
                list_styles.extend(auto_styles.findall('text:list-style', ns))
                
            # Check named styles in styles.xml
            master_styles = styles_root.find('office:styles', ns)
            if master_styles:
                list_styles.extend(master_styles.findall('text:list-style', ns))

            # Filter if we found a specific target name, otherwise check all (lenient)
            if target_list_style_name:
                list_styles = [s for s in list_styles if s.get(f"{{{ns['style']}}}name") == target_list_style_name]
            
            # Verify attributes
            found_char = None
            found_color = None
            
            for ls in list_styles:
                # Check levels (usually level 1)
                for level in ls.findall('text:list-level-style-bullet', ns):
                    char = level.get(f"{{{ns['text']}}}bullet-char")
                    if char:
                        found_char = char
                    
                    props = level.find('style:text-properties', ns)
                    if props is not None:
                        color = props.get(f"{{{ns['fo']}}}color")
                        if color:
                            found_color = color.lower()

            if found_char in expected_chars:
                char_correct = True
                score += 35
                feedback_parts.append(f"Bullet char correct ({found_char})")
            else:
                feedback_parts.append(f"Bullet char incorrect ({found_char})")
                
            # Check color (flexible matching)
            if found_color:
                # Simple normalization
                is_green = found_color in expected_colors or \
                          (len(found_color) == 7 and found_color.startswith('#00') and int(found_color[3:5], 16) > 60 and int(found_color[5:7], 16) < 60)
                
                if is_green:
                    color_correct = True
                    score += 35
                    feedback_parts.append(f"Bullet color correct ({found_color})")
                else:
                    feedback_parts.append(f"Bullet color incorrect ({found_color})")
            else:
                feedback_parts.append("Bullet color not found")

    except Exception as e:
        feedback_parts.append(f"ODP parsing failed: {str(e)}")
    finally:
        if os.path.exists(odp_temp.name):
            os.unlink(odp_temp.name)

    # VLM Verification (Trajectory Analysis)
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        
        if final_img:
            # Check final visual result
            prompt = """
            Analyze this presentation slide.
            1. Look at the bullet points. Are they Checkmark symbols (✓) or standard dots?
            2. What color are the bullet points?
            
            Respond in JSON: {"is_checkmark": bool, "color": "string"}
            """
            vlm_res = query_vlm(prompt=prompt, image=final_img)
            
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                is_check = parsed.get("is_checkmark", False)
                color_str = parsed.get("color", "").lower()
                
                if is_check:
                    vlm_score += 5
                if "green" in color_str:
                    vlm_score += 5
                
                feedback_parts.append(f"VLM Visual: Checkmark={is_check}, Color={color_str}")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        
    score += vlm_score

    # Final verdict
    passed = score >= 90  # Strict threshold (must basically get everything right)
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }