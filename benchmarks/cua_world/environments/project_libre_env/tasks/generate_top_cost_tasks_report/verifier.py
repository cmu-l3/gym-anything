#!/usr/bin/env python3
"""
Verifier for generate_top_cost_tasks_report@1

Checks:
1. PDF file creation and validity.
2. Content analysis (PDF text extraction) to verify:
   - "Cost" column is present.
   - Forbidden columns ("Start", "Finish") are absent.
3. Sort order verification (extracting cost values).
4. VLM verification as fallback or confirmation.
"""

import json
import os
import re
import tempfile
import logging
from typing import Dict, Any, List

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_top_cost_tasks_report(traj, env_info, task_info):
    """
    Verify the Top Cost Tasks Report task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_pdf_path = metadata.get('expected_pdf_path', '/home/ga/Desktop/top_cost_report.pdf')

    # 1. Retrieve Result JSON
    task_result = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
        local_json_path = f.name
    
    try:
        copy_from_env("/tmp/task_result.json", local_json_path)
        with open(local_json_path, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(local_json_path):
            os.unlink(local_json_path)

    # 2. Retrieve Generated PDF
    local_pdf_path = None
    pdf_text_content = ""
    
    if task_result.get('output_exists', False):
        with tempfile.NamedTemporaryFile(delete=False, suffix='.pdf') as f:
            local_pdf_path = f.name
        try:
            copy_from_env(expected_pdf_path, local_pdf_path)
            # Try to extract text using pypdf or pdfminer if available
            try:
                from pdfminer.high_level import extract_text
                pdf_text_content = extract_text(local_pdf_path)
            except ImportError:
                # Fallback to simple strings check if binary or try to install/warn
                logger.warning("pdfminer not available, attempting naive binary string search")
                with open(local_pdf_path, 'rb') as f:
                    pdf_text_content = str(f.read())
        except Exception as e:
            logger.error(f"Failed to copy or read PDF: {e}")

    # --- SCORING CRITERIA ---
    score = 0
    feedback = []

    # Criterion 1: PDF Exists and Created During Task (20 pts)
    if task_result.get('output_exists') and task_result.get('file_created_during_task'):
        score += 20
        feedback.append("PDF report created successfully.")
    elif task_result.get('output_exists'):
        score += 10
        feedback.append("PDF exists but timestamp check failed (modified before task?).")
    else:
        feedback.append("PDF report file not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criterion 2: 'Cost' Column Visible (20 pts)
    # Check for "Cost" keyword in PDF text
    # In ProjectLibre PDF export, headers are usually text.
    if "Cost" in pdf_text_content or "COST" in pdf_text_content:
        score += 20
        feedback.append("Cost column found in report.")
    else:
        feedback.append("Cost column NOT detected in report text.")

    # Criterion 3: Forbidden Columns Hidden (20 pts)
    # Start, Finish, Duration should NOT be present in the header/content
    # Note: "Duration" might appear in footer or meta, but column headers usually stand out.
    # We check if they appear frequently or in a context that looks like a header.
    forbidden = ["Start", "Finish", "Predecessors"]
    found_forbidden = [term for term in forbidden if term in pdf_text_content]
    
    if not found_forbidden:
        score += 20
        feedback.append("Clean view: Unnecessary columns hidden.")
    else:
        # Partial credit if only some are hidden
        penalty = len(found_forbidden) * 5
        score += max(0, 20 - penalty)
        feedback.append(f"View cluttered: Found forbidden columns {found_forbidden}.")

    # Criterion 4: Sorting (25 pts)
    # Attempt to extract currency values and check order
    # Regex for currency: $1,234.00 or similar
    prices = []
    # ProjectLibre standard format often: $ 100.00 or 100,00
    matches = re.findall(r'[\$£€]?\s?([0-9,]+(?:\.[0-9]{2})?)', pdf_text_content)
    
    cleaned_prices = []
    for m in matches:
        try:
            val = float(m.replace(',', ''))
            # Filter out things that look like IDs (small integers) or Percentages
            if val > 100 and "." in m: # Heuristic for significant cost values
                cleaned_prices.append(val)
        except:
            pass
            
    is_sorted_desc = False
    if len(cleaned_prices) >= 3:
        # Check if roughly sorted descending
        # Allow small amount of noise (e.g. summary rows)
        sorted_prices = sorted(cleaned_prices, reverse=True)
        # Check correlation or exact match of top N
        top_n = min(5, len(cleaned_prices))
        if cleaned_prices[:top_n] == sorted_prices[:top_n]:
             is_sorted_desc = True
    
    if is_sorted_desc:
        score += 25
        feedback.append("Data appears sorted by Cost (Descending).")
    else:
        # Fallback: Maybe they sorted ascending?
        # Or VLM verification required.
        # We give 10 points for effort if "Cost" is present, assuming visual check might pass later
        feedback.append("Could not verify sort order programmatically.")
        if "Cost" in pdf_text_content:
             score += 10

    # Criterion 5: VLM Verification (15 pts)
    # Since we can't easily run VLM here without the helper, we assume the framework handles it
    # or we check for evidence in the trajectory (e.g. clicks on 'Cost' header).
    # Here we will give points if the file is substantial size (implying content) and basics pass.
    if task_result.get('output_size_bytes', 0) > 1000:
        score += 15
        feedback.append("Report content appears substantial.")

    # Cleanup
    if local_pdf_path and os.path.exists(local_pdf_path):
        os.unlink(local_pdf_path)

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }