#!/usr/bin/env python3
"""
Verifier for Corporate MSA Formatting task.

Checks applied paragraph styles, text alignments, and specific text emphasis (bolding).
Uses `python-docx` for robust programmatic validation of the underlying XML.
"""

import os
import json
import logging
import tempfile
import sys
import subprocess

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Ensure python-docx is available in the verifier environment (host)
try:
    import docx
except ImportError:
    logger.info("Installing python-docx for verification...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "python-docx"])
    import docx

def get_real_alignment(p):
    """Robustly extracts alignment from a python-docx paragraph including XML fallbacks."""
    if p.alignment is not None:
        return p.alignment
    # Fallback checking the raw XML 
    jc = p._p.find('.//w:jc', namespaces=p._p.nsmap)
    if jc is not None:
        val = jc.get('{http://schemas.openxmlformats.org/wordprocessingml/2006/main}val')
        if val == 'center': return 1
        if val == 'both': return 3  # Justified
    return 0


def verify_msa_formatting(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env not available"}

    feedback_parts = []
    score = 0
    max_score = 100

    # 1. Read the export result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Validate output exists (10 points)
    if not result.get('output_exists'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Target file 'formatted_msa_final.docx' was not created or saved."
        }
    
    if not result.get('file_created_during_task'):
        feedback_parts.append("WARNING: File timestamp check failed (Anti-gaming)")
    else:
        score += 10
        feedback_parts.append("File successfully created/saved (10/10)")

    # 2. Extract and parse the DOCX file
    temp_docx = tempfile.NamedTemporaryFile(delete=False, suffix='.docx')
    try:
        copy_from_env("/home/ga/Documents/TextDocuments/formatted_msa_final.docx", temp_docx.name)
        doc = docx.Document(temp_docx.name)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to parse output document: {e}"}
    finally:
        if os.path.exists(temp_docx.name):
            os.unlink(temp_docx.name)

    # Verification Variables
    title_centered = False
    h1_count = 0
    h2_count = 0
    body_justified_count = 0
    bold_terms_found = set()
    terms_to_bold = ["Confidential Information", "Deliverables", "Effective Date"]

    # Iterate through document to evaluate styling
    for p in doc.paragraphs:
        text = p.text.strip()
        if not text:
            continue
            
        align_val = get_real_alignment(p)

        # A. Check Title Alignment (15 pts)
        if "MASTER SERVICE AGREEMENT" in text.upper():
            if align_val == 1:  # WD_ALIGN_PARAGRAPH.CENTER
                title_centered = True
        
        # B. Check Headings (H1 = 20 pts, H2 = 20 pts)
        if p.style.name.startswith('Heading 1'):
            if text[0].isdigit() and "." in text and text.isupper():
                h1_count += 1
        elif p.style.name.startswith('Heading 2'):
            if text[0].isdigit() and "." in text and not text.isupper():
                h2_count += 1

        # C. Check Body Justification (20 pts)
        # Body paragraphs are usually longer clauses (length > 50)
        if len(text) > 50 and not p.style.name.startswith('Heading'):
            if align_val == 3:  # WD_ALIGN_PARAGRAPH.JUSTIFY
                body_justified_count += 1
                
        # D. Check Bolding for Defined Terms (15 pts)
        # Combine all bold text in the paragraph to handle terms split across runs
        bold_text = "".join([run.text for run in p.runs if run.bold])
        for term in terms_to_bold:
            if term in text and term in bold_text:
                bold_terms_found.add(term)

    # Calculate Scores
    if title_centered:
        score += 15
        feedback_parts.append("Title is centered (15/15)")
    else:
        feedback_parts.append("Title is not centered (0/15)")

    if h1_count >= 5:
        score += 20
        feedback_parts.append(f"H1 applied correctly to {h1_count} articles (20/20)")
    else:
        feedback_parts.append(f"H1 applied to only {h1_count}/7 articles (0/20)")

    if h2_count >= 5:
        score += 20
        feedback_parts.append(f"H2 applied correctly to {h2_count} sub-sections (20/20)")
    else:
        feedback_parts.append(f"H2 applied to only {h2_count}/7 sub-sections (0/20)")

    if body_justified_count >= 5:
        score += 20
        feedback_parts.append(f"Body paragraphs are justified ({body_justified_count} found) (20/20)")
    else:
        feedback_parts.append(f"Body paragraphs are not justified (found {body_justified_count}) (0/20)")

    if len(bold_terms_found) == 3:
        score += 15
        feedback_parts.append("All defined terms successfully bolded (15/15)")
    else:
        feedback_parts.append(f"Bolded terms found: {len(bold_terms_found)}/3 (0/15)")

    # Pass threshold: 70 points (agent did majority of formatting)
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }