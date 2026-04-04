#!/usr/bin/env python3
"""
Verifier for manual_style_rebranding task.
Checks:
1. Styles updated correctly (Normal, Heading 1).
2. New style 'WarningText' created with correct properties.
3. 'WarningText' applied to target paragraphs.
4. Direct formatting cleared (anti-gaming: ensuring styles are used, not manual overrides).
"""

import sys
import os
import logging
import json
import tempfile
import shutil

# Import shared utilities
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
try:
    from writer_verification_utils import copy_and_parse_document
except ImportError:
    # Fallback for standalone testing
    def copy_and_parse_document(path, copy_fn, file_format):
        return False, None, "Utils not found", None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_manual_style_rebranding(traj, env_info, task_info):
    """Verify the style rebranding task."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Documents/omnibase_rebranded.docx')
    
    # Check if file exists in result json first
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name) as f:
            result_data = json.load(f)
    except Exception:
        result_data = {}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result_data.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}

    # Load the document
    success, doc, error, temp_dir = copy_and_parse_document(output_path, copy_from_env, 'docx')
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Could not parse document: {error}"}

    score = 0
    feedback = []
    
    try:
        # 1. Check Normal Style Definition (15 pts)
        # Target: Liberation Serif, 11pt
        normal_style = doc.styles['Normal']
        normal_font = normal_style.font.name
        normal_size = normal_style.font.size.pt if normal_style.font.size else None
        
        if normal_font and 'Liberation Serif' in normal_font:
            score += 10
            feedback.append("Normal font correct.")
        else:
            feedback.append(f"Normal font incorrect ({normal_font}).")
            
        if normal_size == 11.0:
            score += 5
            feedback.append("Normal size correct.")
        else:
            feedback.append(f"Normal size incorrect ({normal_size}).")

        # 2. Check Heading 1 Style Definition (15 pts)
        # Target: Liberation Sans, 16pt, Dark Blue
        h1_style = doc.styles['Heading 1']
        h1_font = h1_style.font.name
        h1_size = h1_style.font.size.pt if h1_style.font.size else None
        h1_color = h1_style.font.color.rgb
        
        if h1_font and 'Liberation Sans' in h1_font:
            score += 5
            feedback.append("Heading 1 font correct.")
            
        if h1_size == 16.0:
            score += 5
            feedback.append("Heading 1 size correct.")
            
        # Blue check (approximate or exact)
        # 000080 is (0, 0, 128)
        if h1_color and (h1_color == (0, 0, 128) or h1_color == (0, 0, 139) or h1_color == (0, 51, 102)):
            score += 5
            feedback.append("Heading 1 color correct.")
        else:
            feedback.append(f"Heading 1 color mismatch ({h1_color}).")

        # 3. Check WarningText Style Creation (15 pts)
        warning_style = None
        if 'WarningText' in doc.styles:
            warning_style = doc.styles['WarningText']
            score += 5
            feedback.append("'WarningText' style exists.")
            
            if warning_style.font.italic:
                score += 5
                feedback.append("WarningText is italic.")
            
            # Check red color
            w_color = warning_style.font.color.rgb
            if w_color and (w_color == (255, 0, 0) or w_color == (204, 0, 0)):
                score += 5
                feedback.append("WarningText is red.")
        else:
            feedback.append("'WarningText' style missing.")

        # 4. Check Application to paragraphs (15 pts)
        warning_paras_found = 0
        warning_paras_styled = 0
        
        for para in doc.paragraphs:
            text = para.text.strip()
            if text.startswith("WARNING:"):
                warning_paras_found += 1
                if para.style.name == 'WarningText':
                    warning_paras_styled += 1
        
        if warning_paras_found == 3:
            if warning_paras_styled == 3:
                score += 15
                feedback.append("All 3 warnings have correct style applied.")
            elif warning_paras_styled > 0:
                score += 5
                feedback.append(f"Only {warning_paras_styled}/3 warnings styled.")
            else:
                feedback.append("No warnings have 'WarningText' style applied.")
        else:
            feedback.append(f"Could not find all warning paragraphs (found {warning_paras_found}).")

        # 5. Check Direct Formatting Cleared (Anti-Gaming) (30 pts)
        # If Direct Formatting is cleared, runs should NOT have font names set 
        # (they should inherit from style). The setup script injected 'Arial' manually.
        # If 'Arial' is still present in runs, they failed to clear formatting.
        
        clean_runs = 0
        total_runs_checked = 0
        failed_font = None
        
        for para in doc.paragraphs:
            # Skip empty paras
            if not para.text.strip(): 
                continue
                
            for run in para.runs:
                if not run.text.strip():
                    continue
                    
                total_runs_checked += 1
                # run.font.name should be None if inheriting from style
                # However, python-docx sometimes reports style font if explicitly set on run
                # We specifically check for the "bad" fonts we injected: Arial, Courier New
                # If the user updated the style correctly, the effective font is Liberation.
                # If the run says "Arial", they failed to clear.
                
                r_font = run.font.name
                if r_font and r_font in ['Arial', 'Courier New', 'Times New Roman']:
                    failed_font = r_font
                else:
                    clean_runs += 1
                    
        if total_runs_checked > 0:
            clean_pct = clean_runs / total_runs_checked
            if clean_pct > 0.95:
                score += 30
                feedback.append("Direct formatting cleared successfully.")
            elif clean_pct > 0.5:
                score += 10
                feedback.append(f"Partial direct formatting cleared ({int(clean_pct*100)}%). Found legacy font: {failed_font}")
            else:
                feedback.append(f"Direct formatting NOT cleared. Found legacy font: {failed_font}")
        else:
            score += 30 # No runs to check?

        # 6. Output file exists points (10 pts)
        score += 10

    except Exception as e:
        feedback.append(f"Verification error: {str(e)}")
        logger.error(f"Error during verification logic: {e}", exc_info=True)
    finally:
        # Cleanup
        if temp_dir and os.path.exists(temp_dir):
            shutil.rmtree(temp_dir)

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }