#!/usr/bin/env python3
"""Verifier for refactor_monolithic_protocol task."""

import json
import tempfile
import os
import re

def is_text_bolded(html, text_to_find):
    """
    Safely parses HTML string to determine if specific text is contained within a bold tag.
    Includes fallbacks in case BeautifulSoup is not immediately accessible.
    """
    if not html:
        return False
    
    text_lower = text_to_find.lower()
    
    try:
        from bs4 import BeautifulSoup
        soup = BeautifulSoup(html, 'html.parser')
        
        # Check standard bold tags
        for tag in soup.find_all(['strong', 'b']):
            if text_lower in tag.get_text().lower():
                return True
                
        # Check inline styles (sometimes used by WYSIWYG editors)
        for tag in soup.find_all(style=True):
            style = tag.get('style', '').lower()
            if 'font-weight: bold' in style or 'font-weight: 700' in style:
                if text_lower in tag.get_text().lower():
                    return True
                    
        # Check specific classes
        for tag in soup.find_all(class_=True):
            classes = tag.get('class', [])
            if any('bold' in c.lower() for c in classes):
                if text_lower in tag.get_text().lower():
                    return True
    except ImportError:
        pass
        
    # Fallback to Regex matching (always processes if bs4 fails)
    html_lower = html.lower()
    patterns = [
        r'<(strong|b)[^>]*>.*?' + re.escape(text_lower) + r'.*?</\1>',
        r'<[^>]*style="[^"]*font-weight:\s*(bold|700)[^"]*"[^>]*>.*?' + re.escape(text_lower) + r'.*?</[^>]+>'
    ]
    
    for p in patterns:
        if re.search(p, html_lower, re.DOTALL):
            return True
            
    return False


def verify_refactor_protocol(traj, env_info, task_info):
    """Verify that protocol was split into 4 steps with accurate text distribution and bolding applied."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_steps = metadata.get('expected_steps', [
        "Reagent Preparation",
        "Sample Preparation",
        "Assay Execution",
        "Measurement and Analysis"
    ])
    keywords = metadata.get('keywords', {})
    bold_warning_text = metadata.get('bold_warning_text', 'WARNING: Coomassie dye')

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/refactor_protocol_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    if not result.get('found', False):
        return {"passed": False, "score": 0, "feedback": "Protocol 'Bradford Protein Assay (Draft)' not found"}

    steps = result.get('steps', [])
    step_count = result.get('step_count', 0)
    
    # 1. Total step count and removal of monolithic step (15 points)
    monolithic_found = any('full procedure' in s.get('name', '').lower() for s in steps)
    if step_count == 4 and not monolithic_found:
        score += 15
        feedback_parts.append("Step count is 4 and monolithic step removed")
    elif not monolithic_found:
        score += 5
        feedback_parts.append(f"Monolithic step removed, but step count is {step_count} (expected 4)")
    else:
        feedback_parts.append("Original 'Full Procedure' step was not deleted")
        
    def find_step(name):
        """Helper to find step by partial name match"""
        for s in steps:
            if name.lower() in s.get('name', '').lower():
                return s
        return None

    # 2. Correct Step Order (15 points)
    order_correct = False
    if len(steps) >= 4:
        names_in_order = [s.get('name', '').lower() for s in steps]
        indices = []
        for exp in expected_steps:
            for i, name in enumerate(names_in_order):
                if exp.lower() in name:
                    indices.append(i)
                    break
        if len(indices) == 4 and indices == sorted(indices):
            order_correct = True
            score += 15
            feedback_parts.append("Step sequence order is correct")
        else:
            feedback_parts.append("Step sequence order is incorrect or missing steps")
    else:
        feedback_parts.append("Not enough steps to check sequence order")

    # 3. Step 1 Correct (15 points)
    step1 = find_step(expected_steps[0])
    step1_correct = False
    if step1:
        if keywords.get('step1', '').lower() in step1.get('text_content', '').lower():
            step1_correct = True
            score += 15
            feedback_parts.append("Step 1 content verified")
        else:
            feedback_parts.append("Step 1 missing expected text content")
    else:
        feedback_parts.append(f"Step '{expected_steps[0]}' not found")

    # 4. Step 1 Bolding (15 points)
    step1_bolding = False
    if step1:
        text_content = step1.get('text_content', '')
        if is_text_bolded(text_content, bold_warning_text):
            step1_bolding = True
            score += 15
            feedback_parts.append("Step 1 safety warning is explicitly bolded")
        else:
            feedback_parts.append("Step 1 safety warning is NOT bolded in the rich text editor")
    else:
        feedback_parts.append("Cannot check bolding (Step 1 missing)")

    # 5. Step 2 Correct (10 points)
    step2 = find_step(expected_steps[1])
    step2_correct = False
    if step2:
        if keywords.get('step2', '').lower() in step2.get('text_content', '').lower():
            step2_correct = True
            score += 10
            feedback_parts.append("Step 2 content verified")
        else:
            feedback_parts.append("Step 2 missing expected text content")
    else:
        feedback_parts.append(f"Step '{expected_steps[1]}' not found")

    # 6. Step 3 Correct (15 points)
    step3 = find_step(expected_steps[2])
    step3_correct = False
    if step3:
        if keywords.get('step3', '').lower() in step3.get('text_content', '').lower():
            step3_correct = True
            score += 15
            feedback_parts.append("Step 3 content verified")
        else:
            feedback_parts.append("Step 3 missing expected text content")
    else:
        feedback_parts.append(f"Step '{expected_steps[2]}' not found")

    # 7. Step 4 Correct (15 points)
    step4 = find_step(expected_steps[3])
    step4_correct = False
    if step4:
        if keywords.get('step4', '').lower() in step4.get('text_content', '').lower():
            step4_correct = True
            score += 15
            feedback_parts.append("Step 4 content verified")
        else:
            feedback_parts.append("Step 4 missing expected text content")
    else:
        feedback_parts.append(f"Step '{expected_steps[3]}' not found")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "monolithic_step_removed": not monolithic_found and step_count == 4,
            "order_correct": order_correct,
            "step1_correct": step1_correct,
            "step1_bolded": step1_bolding,
            "step2_correct": step2_correct,
            "step3_correct": step3_correct,
            "step4_correct": step4_correct
        }
    }