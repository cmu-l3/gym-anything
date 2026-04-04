#!/usr/bin/env python3
import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_architect_digital_products(traj, env_info, task_info):
    """
    Verify the configuration of digital products in Drupal Commerce.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Metadata expectations
    metadata = task_info.get('metadata', {})
    expected_terms = set(t.lower() for t in metadata.get('terms', ["PDF", "ePub", "MOBI"]))

    # Load Result
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []

    # 1. Vocabulary (10 pts)
    if result.get('vocab_exists'):
        score += 10
        feedback_parts.append("Vocabulary 'File Formats' created.")
    else:
        feedback_parts.append("Vocabulary 'File Formats' MISSING.")

    # 2. Terms (10 pts)
    # result['terms_found'] should be a list of strings
    found_terms = result.get('terms_found', [])
    if isinstance(found_terms, str):
        # Handle case where JSON_ARRAYAGG returned a string rep of json or just raw string
        try:
            found_terms = json.loads(found_terms)
        except:
            found_terms = []
    
    # Normalize found terms
    found_terms_lower = set(str(t).lower() for t in found_terms if t)
    
    # Check intersection
    common = expected_terms.intersection(found_terms_lower)
    if len(common) >= 3:
        score += 10
        feedback_parts.append("All taxonomy terms found.")
    elif len(common) > 0:
        score += 5
        feedback_parts.append(f"Some terms found ({len(common)}/3).")
    else:
        feedback_parts.append("No correct taxonomy terms found.")

    # 3. Digital Variation Type (20 pts)
    analysis = result.get('config_analysis', {})
    if result.get('variation_exists'):
        # Check shippable trait
        # If variation_shippable is False, that's GOOD (we want digital)
        # Note: The analysis script logic was: if b'commerce_shipping' in data -> True
        if not analysis.get('variation_shippable', True):
             score += 20
             feedback_parts.append("Digital Variation type created and is NOT shippable.")
        else:
             score += 10
             feedback_parts.append("Digital Variation type created, but 'Shippable' trait is still enabled.")
    else:
        feedback_parts.append("Digital Variation type MISSING.")

    # 4. Fields (40 pts split)
    # File Field (20 pts)
    if result.get('field_file_exists'):
        # Check type
        if analysis.get('file_field_type') == 'file':
            score += 20
            feedback_parts.append("Download File field configured correctly.")
        else:
            score += 10
            feedback_parts.append("Download File field exists but wrong type.")
    else:
        feedback_parts.append("Download File field MISSING.")

    # Format Field (20 pts)
    if result.get('field_format_exists'):
        if analysis.get('format_field_type') == 'entity_reference':
            score += 20
            feedback_parts.append("File Format field configured correctly.")
        else:
            score += 10
            feedback_parts.append("File Format field exists but wrong type.")
    else:
        feedback_parts.append("File Format field MISSING.")

    # 5. Product Type (20 pts) (Total max score was 100, logic check: 10+10+20+20+20 = 80. Need +20 for Product Type)
    if result.get('product_type_exists'):
        if analysis.get('product_uses_variation'):
            score += 20
            feedback_parts.append("Digital Product type created and linked to variation.")
        else:
            score += 10
            feedback_parts.append("Digital Product type created but linkage to variation not verified.")
    else:
        feedback_parts.append("Digital Product type MISSING.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }