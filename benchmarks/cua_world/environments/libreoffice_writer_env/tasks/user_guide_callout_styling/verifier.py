#!/usr/bin/env python3
"""
Verifier for user_guide_callout_styling task.
Verifies paragraph borders, shading, fonts, and marker removal in DOCX output.
"""

import json
import os
import sys
import logging
from typing import Dict, List, Tuple, Any

# Add utils directory to path to import writer verification utils
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from writer_verification_utils import (
    copy_and_parse_document,
    vlm_verify_screenshot,
    check_heading_styles
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- Helper Functions for XML Analysis ---

def get_paragraph_properties(para) -> Dict[str, Any]:
    """Extract formatting properties from a paragraph's XML."""
    props = {
        'borders': {'left': None},
        'shading': None,
        'text': para.text,
        'style': para.style.name if para.style else None
    }
    
    # Access the underlying XML element (CT_P)
    p_element = para._element
    pPr = p_element.pPr
    
    if pPr is None:
        return props

    # Check Borders (w:pBdr/w:left)
    if pPr.pBdr is not None and pPr.pBdr.left is not None:
        border = pPr.pBdr.left
        props['borders']['left'] = {
            'val': border.val,
            'color': border.color,
            'sz': border.sz,  # in 1/8 points
            'space': border.space
        }

    # Check Shading (w:shd)
    if pPr.shd is not None:
        shd = pPr.shd
        props['shading'] = {
            'val': shd.val,
            'color': shd.color,
            'fill': shd.fill
        }

    return props

def get_run_fonts(para) -> List[str]:
    """Get list of font names used in paragraph runs."""
    fonts = []
    # Check paragraph style font first
    if para.style and para.style.font and para.style.font.name:
        fonts.append(para.style.font.name)
        
    # Check individual runs
    for run in para.runs:
        if run.font.name:
            fonts.append(run.font.name)
        # Also check XML for rFonts if python-docx abstraction misses it
        elif run._element.rPr is not None and run._element.rPr.rFonts is not None:
            rFonts = run._element.rPr.rFonts
            if rFonts.ascii: fonts.append(rFonts.ascii)
            elif rFonts.hAnsi: fonts.append(rFonts.hAnsi)
            
    return [f.lower() for f in fonts]

def analyze_color(hex_color: str) -> str:
    """Classify a hex color into a family (blue, red, green, gray)."""
    if not hex_color or hex_color == 'auto':
        return 'none'
    
    try:
        # Normalize hex
        hex_color = hex_color.replace('#', '')
        if len(hex_color) != 6:
            return 'unknown'
            
        r = int(hex_color[0:2], 16)
        g = int(hex_color[2:4], 16)
        b = int(hex_color[4:6], 16)
        
        # Simple dominance heuristics
        if r > g + 30 and r > b + 30: return 'red'
        if g > r + 30 and g > b + 30: return 'green'
        if b > r + 30 and b > g + 30: return 'blue'
        
        # Gray check (channels close to each other)
        if abs(r - g) < 30 and abs(r - b) < 30 and abs(g - b) < 30:
            return 'gray'
        
        # Yellow check (high R and G, low B)
        if r > 150 and g > 150 and b < 100:
            return 'yellow' # Accepted for warning background
            
        return 'mixed'
    except:
        return 'error'

# --- Main Verifier ---

def verify_user_guide_styling(traj, env_info, task_info):
    """
    Verify the User Guide styling task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_structure = metadata.get('heading_structure', {})
    
    # Target text fragments to identify paragraphs (since markers are removed)
    target_texts = {
        'NOTE': metadata.get('target_texts_note', []),
        'WARNING': metadata.get('target_texts_warning', []),
        'TIP': metadata.get('target_texts_tip', []),
        'CODE': metadata.get('target_texts_code', [])
    }

    # Load result JSON for basic checks
    task_result = {}
    try:
        import tempfile
        tfile = tempfile.NamedTemporaryFile(delete=False)
        tfile.close()
        copy_from_env("/tmp/task_result.json", tfile.name)
        with open(tfile.name) as f:
            task_result = json.load(f)
        os.unlink(tfile.name)
    except Exception as e:
        logger.warning(f"Could not load task_result.json: {e}")

    # 1. Check file existence and creation (8 points)
    score = 0
    feedback = []
    
    if not task_result.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Output file git_guide_styled.docx not found."}
    
    score += 4
    if task_result.get('created_during_task'):
        score += 4
    else:
        feedback.append("Output file timestamp indicates it wasn't modified during task.")

    # 2. Parse Document
    output_path = metadata.get('output_path', '/home/ga/Documents/git_guide_styled.docx')
    success, doc, err, temp_dir = copy_and_parse_document(output_path, copy_from_env, 'docx')
    
    if not success:
        return {"passed": False, "score": score, "feedback": f"Failed to parse output document: {err}"}

    try:
        # 3. Check Headings (10 points)
        matched_headings, total_headings, _ = check_heading_styles(doc, expected_structure)
        heading_score = 0
        if total_headings > 0:
            heading_score = min(10, int((matched_headings / total_headings) * 10))
        score += heading_score
        if heading_score < 10:
            feedback.append(f"Heading styles incomplete: {matched_headings}/{total_headings} correct.")
        else:
            feedback.append("Headings correct.")

        # 4. Check Callouts (60 points total)
        # Categories: NOTE (Blue), WARNING (Red), TIP (Green), CODE (Mono/Gray)
        
        # Helper to find para by content
        def find_para_by_content(fragment):
            for p in doc.paragraphs:
                if fragment[:30] in p.text: # Match first 30 chars
                    return p
            return None

        # Check NOTE (20 pts: 12 border, 8 shading)
        note_hits = 0
        note_border = 0
        note_shade = 0
        for txt in target_texts['NOTE']:
            p = find_para_by_content(txt)
            if p:
                props = get_paragraph_properties(p)
                # Check left border (blue)
                lb = props['borders']['left']
                if lb and lb['val'] != 'nil' and analyze_color(lb['color']) == 'blue':
                    note_border += 1
                
                # Check shading (blue)
                sh = props['shading']
                if sh and sh['fill'] and analyze_color(sh['fill']) == 'blue':
                    note_shade += 1
                note_hits += 1

        if note_hits > 0:
            score += min(12, int((note_border / note_hits) * 12))
            score += min(8, int((note_shade / note_hits) * 8))
            feedback.append(f"NOTE styling: {note_border}/{note_hits} borders, {note_shade}/{note_hits} shading.")

        # Check WARNING (20 pts: 12 border, 8 shading)
        warn_hits = 0
        warn_border = 0
        warn_shade = 0
        for txt in target_texts['WARNING']:
            p = find_para_by_content(txt)
            if p:
                props = get_paragraph_properties(p)
                # Check left border (red)
                lb = props['borders']['left']
                if lb and lb['val'] != 'nil' and analyze_color(lb['color']) == 'red':
                    warn_border += 1
                
                # Check shading (red or yellow/orange)
                sh = props['shading']
                if sh and sh['fill']:
                    fam = analyze_color(sh['fill'])
                    if fam in ['red', 'yellow']:
                        warn_shade += 1
                warn_hits += 1

        if warn_hits > 0:
            score += min(12, int((warn_border / warn_hits) * 12))
            score += min(8, int((warn_shade / warn_hits) * 8))
            feedback.append(f"WARNING styling: {warn_border}/{warn_hits} borders, {warn_shade}/{warn_hits} shading.")

        # Check TIP (20 pts: 12 border, 8 shading)
        tip_hits = 0
        tip_border = 0
        tip_shade = 0
        for txt in target_texts['TIP']:
            p = find_para_by_content(txt)
            if p:
                props = get_paragraph_properties(p)
                # Check left border (green)
                lb = props['borders']['left']
                if lb and lb['val'] != 'nil' and analyze_color(lb['color']) == 'green':
                    tip_border += 1
                
                # Check shading (green)
                sh = props['shading']
                if sh and sh['fill'] and analyze_color(sh['fill']) == 'green':
                    tip_shade += 1
                tip_hits += 1
        
        if tip_hits > 0:
            score += min(12, int((tip_border / tip_hits) * 12))
            score += min(8, int((tip_shade / tip_hits) * 8))
            feedback.append(f"TIP styling: {tip_border}/{tip_hits} borders, {tip_shade}/{tip_hits} shading.")

        # Check CODE (18 pts: 12 font, 6 shading)
        code_hits = 0
        code_font = 0
        code_shade = 0
        mono_fonts = ['courier', 'mono', 'consolas', 'source code']
        
        for txt in target_texts['CODE']:
            p = find_para_by_content(txt)
            if p:
                # Check font
                fonts = get_run_fonts(p)
                if any(any(m in f for m in mono_fonts) for f in fonts):
                    code_font += 1
                
                # Check shading (gray)
                props = get_paragraph_properties(p)
                sh = props['shading']
                if sh and sh['fill'] and analyze_color(sh['fill']) == 'gray':
                    code_shade += 1
                code_hits += 1

        if code_hits > 0:
            score += min(12, int((code_font / code_hits) * 12))
            score += min(6, int((code_shade / code_hits) * 6))
            feedback.append(f"CODE styling: {code_font}/{code_hits} monospace, {code_shade}/{code_hits} shading.")

        # 5. Check Marker Removal (4 points)
        markers_remaining = 0
        full_text = '\n'.join([p.text for p in doc.paragraphs])
        for marker in ['[NOTE]', '[WARNING]', '[TIP]', '[CODE]']:
            if marker in full_text:
                markers_remaining += 1
        
        if markers_remaining == 0:
            score += 4
            feedback.append("All markers removed.")
        else:
            feedback.append(f"Markers remaining: {markers_remaining}.")

        # 6. VLM Validation (Secondary Check - up to 10 points bonus/penalty logic could go here, 
        # but for this structure we stick to strict scoring within 100)
        # We will log it but not affect score heavily unless score is border-line
        
        vlm_res = vlm_verify_screenshot(env_info, traj, 
            "Do you see paragraphs with colored vertical lines on the left? "
            "Are there gray blocks of code? "
            "Respond JSON: {'colored_borders_visible': bool, 'code_blocks_visible': bool}")
        
        if vlm_res and vlm_res.get('colored_borders_visible'):
            feedback.append("VLM confirms visible borders.")

    except Exception as e:
        logger.error(f"Verification error: {e}")
        feedback.append(f"Verification error: {str(e)}")
    
    finally:
        # Cleanup
        from writer_verification_utils import cleanup_verification_temp
        if temp_dir:
            cleanup_verification_temp(temp_dir)

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }