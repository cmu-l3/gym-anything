#!/usr/bin/env python3
"""
Verifier for hpv_integration_mapping task.

Verification Strategy:
1. Programmatic: Check for the exported GenBank file and its creation time.
2. Programmatic: Parse GenBank features to find `Human_DNA` and `HPV16_DNA`.
3. Programmatic: Verify coordinate ranges against the known breakpoint.
4. Programmatic: Parse the text report for the breakpoint coordinate and gene list.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def find_feature_coords(features_text, feature_name):
    """Parse GenBank features block to extract coordinates for a given feature name."""
    # Split by lines starting with standard indentation for new feature keys
    # "     " (5 spaces) followed by word characters
    blocks = re.split(r'\n     (?=[a-zA-Z])', '\n' + features_text)
    
    for block in blocks:
        if feature_name.lower() in block.lower():
            # Look for coordinate ranges like 1..2000
            match = re.search(r'(\d+)\.\.(\d+)', block)
            if match:
                return int(match.group(1)), int(match.group(2))
    return None, None

def verify_hpv_integration_mapping(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0

    # 1. Retrieve the exported result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/hpv_integration_mapping_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to read result data: {e}. Agent likely did not export anything."
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Retrieve Ground Truth data
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt = {}
    try:
        copy_from_env("/tmp/hpv_integration_mapping_gt.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load ground truth, using fallbacks: {e}")
        gt = {
            "human_start": 1,
            "human_end": 2000,
            "viral_start": 2001,
            "viral_end": 5500,
            "breakpoint": 2000,
            "expected_genes": ["E2", "E4", "E5"]
        }
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    # Criteria 1: GenBank File Exists and is valid (10 pts)
    if result.get("gb_exists"):
        score += 10
        feedback_parts.append("Annotated GenBank file exists (+10)")
        if not result.get("gb_created_during_task"):
            feedback_parts.append("WARNING: File was not created during this task session")
    else:
        feedback_parts.append("GenBank file MISSING (0)")

    # Criteria 2: Human DNA Annotation (20 pts)
    human_start, human_end = find_feature_coords(result.get("features_section", ""), "Human_DNA")
    if human_start is not None and human_end is not None:
        score += 10
        feedback_parts.append("Human_DNA annotation found (+10)")
        
        # Verify coordinates (Allow +/- 10 bp tolerance for alignment ambiguities)
        if abs(human_start - gt["human_start"]) <= 10 and abs(human_end - gt["human_end"]) <= 10:
            score += 10
            feedback_parts.append("Human_DNA coordinates correct (+10)")
        else:
            feedback_parts.append(f"Human_DNA coords incorrect: {human_start}..{human_end} (expected ~{gt['human_start']}..{gt['human_end']})")
    else:
        feedback_parts.append("Human_DNA annotation MISSING (0)")

    # Criteria 3: Viral DNA Annotation (20 pts)
    viral_start, viral_end = find_feature_coords(result.get("features_section", ""), "HPV16_DNA")
    if viral_start is not None and viral_end is not None:
        score += 10
        feedback_parts.append("HPV16_DNA annotation found (+10)")
        
        if abs(viral_start - gt["viral_start"]) <= 10 and abs(viral_end - gt["viral_end"]) <= 10:
            score += 10
            feedback_parts.append("HPV16_DNA coordinates correct (+10)")
        else:
            feedback_parts.append(f"HPV16_DNA coords incorrect: {viral_start}..{viral_end} (expected ~{gt['viral_start']}..{gt['viral_end']})")
    else:
        feedback_parts.append("HPV16_DNA annotation MISSING (0)")

    # Criteria 4: Text Report Exists (10 pts)
    report_content = result.get("report_content", "")
    if result.get("report_exists"):
        score += 10
        feedback_parts.append("Integration report exists (+10)")
    else:
        feedback_parts.append("Integration report MISSING (0)")

    # Criteria 5: Breakpoint Identified in Report (25 pts)
    if report_content:
        # Search for 2000 or 2001
        bp = str(gt["breakpoint"])
        bp_plus_one = str(gt["breakpoint"] + 1)
        
        if re.search(rf'\b({bp}|{bp_plus_one})\b', report_content):
            score += 25
            feedback_parts.append("Correct breakpoint coordinate found in report (+25)")
        else:
            # Check if they found an incorrect number
            nums = re.findall(r'\b\d{4}\b', report_content)
            if nums:
                feedback_parts.append(f"Incorrect breakpoint reported. Found {nums[:2]} (expected ~{bp})")
            else:
                feedback_parts.append("No coordinate found in report")

    # Criteria 6: Preserved Genes Identified (15 pts)
    if report_content:
        genes_found = 0
        for gene in gt["expected_genes"]:
            if re.search(rf'\b{gene}\b', report_content, re.IGNORECASE):
                genes_found += 1
        
        if genes_found > 0:
            gene_pts = genes_found * 5
            score += gene_pts
            feedback_parts.append(f"Identified {genes_found}/{len(gt['expected_genes'])} preserved genes (+{gene_pts})")
        else:
            feedback_parts.append("Did not identify correct preserved genes in report")

    # Final Evaluation
    key_criteria_met = (human_start is not None or viral_start is not None) and result.get("report_exists", False)
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }