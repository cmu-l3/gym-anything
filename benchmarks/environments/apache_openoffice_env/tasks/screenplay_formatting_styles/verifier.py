#!/usr/bin/env python3
"""
Verifier for screenplay_formatting_styles task.

Verifies:
1. File creation and validity.
2. Use of distinct paragraph styles for different script elements (Character, Dialogue, Action).
3. Correct indentation logic (e.g., Character names should be indented more than Action).
4. Content integrity (text matches the source).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_measure(value_str):
    """
    Parses ODT measurement strings like '2.001in', '5.08cm' into inches.
    Returns float inches, or 0.0 if failed.
    """
    if not value_str or value_str == "0":
        return 0.0
    
    value_str = value_str.lower().strip()
    try:
        if value_str.endswith('in') or value_str.endswith('inch'):
            return float(value_str.replace('in', '').replace('ch', ''))
        elif value_str.endswith('cm'):
            return float(value_str.replace('cm', '')) / 2.54
        elif value_str.endswith('mm'):
            return float(value_str.replace('mm', '')) / 25.4
        elif value_str.endswith('pt'):
            return float(value_str.replace('pt', '')) / 72.0
        else:
            # Assume inches if just a number, though ODT usually has units
            return float(value_str)
    except:
        return 0.0

def verify_screenplay_formatting(traj, env_info, task_info):
    """
    Verify the screenplay formatting task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Basic Checks
    if not result.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
    
    if not result.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output file was not created during the task window (anti-gaming)."}

    score = 0
    feedback = []
    
    odt_data = result.get("odt_analysis", {})
    paragraphs = odt_data.get("paragraphs", [])
    style_defs = odt_data.get("style_definitions", {})

    if not paragraphs:
        return {"passed": False, "score": 0, "feedback": "Document appears empty or corrupted."}

    # Score: File exists and is valid ODT
    score += 10
    feedback.append("File created successfully.")

    # Identify styles used for specific known text
    # We map "Text Content" -> "Style Name Used"
    char_lines = ["CMDR. CHEN", "LT. SPARKS", "SHIP COMPUTER"]
    dial_lines = ["Report!", "Shields are down", "Reroute auxiliary power"]
    action_lines = ["The bridge is chaotic", "The ship ROCKS violently"]
    heading_lines = ["INT. BRIDGE"]

    style_map = {
        "character": set(),
        "dialogue": set(),
        "action": set(),
        "heading": set()
    }

    content_found = 0
    
    for p in paragraphs:
        txt = p["text"]
        style = p["style"]
        
        # Check text match
        if any(x in txt for x in char_lines):
            style_map["character"].add(style)
            content_found += 1
        elif any(x in txt for x in dial_lines):
            style_map["dialogue"].add(style)
            content_found += 1
        elif any(x in txt for x in action_lines):
            style_map["action"].add(style)
            content_found += 1
        elif any(x in txt for x in heading_lines):
            style_map["heading"].add(style)
            content_found += 1

    # Score: Content Integrity
    if content_found >= 5:
        score += 10
        feedback.append("Text content verified.")
    else:
        feedback.append("Warning: Some expected text content is missing.")

    # Score: Naming distinct styles
    # We expect distinct style names for Character vs Dialogue vs Action
    # They shouldn't all be "Standard" or "Default Style"
    
    char_styles = list(style_map["character"])
    dial_styles = list(style_map["dialogue"])
    action_styles = list(style_map["action"])
    
    # Resolve default style names
    # In ODT, no style attribute often means "Standard"
    def clean_style(s): return s if s else "Standard"
    
    char_s = clean_style(char_styles[0]) if char_styles else None
    dial_s = clean_style(dial_styles[0]) if dial_styles else None
    act_s = clean_style(action_styles[0]) if action_styles else None

    # Check Usage
    used_styles = set()
    if char_s: used_styles.add(char_s)
    if dial_s: used_styles.add(dial_s)
    if act_s: used_styles.add(act_s)

    if len(used_styles) >= 3:
        score += 20
        feedback.append("Distinct styles used for Character, Dialogue, and Action.")
    elif len(used_styles) == 2:
        score += 10
        feedback.append("Only 2 distinct styles found (expected 3 for Char/Dial/Action).")
    else:
        feedback.append("Failed to use distinct styles for different script elements.")

    # Score: Indentation Logic (The core of the task)
    # Character indent (2.0") > Dialogue indent (1.0") > Action indent (0")
    
    def get_indent(style_name):
        if not style_name or style_name not in style_defs:
            return 0.0
        s_def = style_defs[style_name]
        # Total indent = margin-left + text-indent
        ml = parse_measure(s_def.get("margin_left", "0"))
        ti = parse_measure(s_def.get("text_indent", "0"))
        return ml + ti

    char_indent = get_indent(char_s)
    dial_indent = get_indent(dial_s)
    act_indent = get_indent(act_s)

    indent_score = 0
    # Check 1: Character is indented significantly (> 1.5 inch)
    if char_indent > 1.5:
        indent_score += 20
        feedback.append(f"Character indentation correct (>1.5\"). Found: {char_indent:.2f}\"")
    elif char_indent > 0.5:
        indent_score += 10
        feedback.append(f"Character indentation present but small. Found: {char_indent:.2f}\"")
    else:
        feedback.append("Character indentation missing.")

    # Check 2: Dialogue is indented (> 0.5 inch) but less than Character
    if dial_indent > 0.5 and dial_indent < char_indent:
        indent_score += 20
        feedback.append(f"Dialogue indentation correct (between Action and Character). Found: {dial_indent:.2f}\"")
    elif dial_indent > 0.1:
        indent_score += 10
        feedback.append(f"Dialogue indentation present. Found: {dial_indent:.2f}\"")
    else:
        feedback.append("Dialogue indentation missing.")
        
    # Check 3: Action is flush left (approx 0)
    if act_indent < 0.2:
        indent_score += 10
        feedback.append("Action is flush left (correct).")
        
    # Check 4: Heading is flush left
    head_s = clean_style(list(style_map["heading"])[0]) if style_map["heading"] else None
    if head_s and get_indent(head_s) < 0.2:
        indent_score += 10
        feedback.append("Scene Heading is flush left (correct).")

    score += indent_score

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback),
        "details": {
            "style_map": {k: list(v) for k,v in style_map.items()},
            "indents": {
                "character": char_indent,
                "dialogue": dial_indent,
                "action": act_indent
            }
        }
    }