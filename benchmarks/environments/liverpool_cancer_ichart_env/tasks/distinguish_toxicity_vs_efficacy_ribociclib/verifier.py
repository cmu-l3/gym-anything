#!/usr/bin/env python3
"""
Verifier for distinguish_toxicity_vs_efficacy_ribociclib task.

Checks:
1. Output file exists.
2. Content correctly identifies Clarithromycin as Toxicity/Increased risk.
3. Content correctly identifies Rifampicin as Efficacy/Decreased risk.
4. VLM verifies agent actually looked at the details of both drugs.
"""

import json
import tempfile
import os
import logging
import re
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import VLM utils from framework
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
except ImportError:
    # Fallback for testing
    def sample_trajectory_frames(traj, n=5): return []
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}

def verify_ribociclib_risk_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # 1. Fetch Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Check File Existence (10 pts)
    if not result.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Report file not found at /sdcard/ribociclib_risk_analysis.txt"}
    
    score += 10
    content = result.get("file_content", "").lower()
    
    # 3. Check Content Logic (50 pts total)
    # drug 1: Clarithromycin -> Increased/Toxicity
    # drug 2: Rifampicin -> Decreased/Efficacy
    
    # We parse the file loosely. We look for the drug name, then look for keywords in proximity or in the whole text if simple.
    # Given the requested format, we can split by drug.
    
    clarith_keywords = ["clarithromycin"]
    rifamp_keywords = ["rifampicin", "rifampin"]
    
    toxicity_keywords = ["increase", "toxicity", "raise", "higher", "exposure"]
    efficacy_keywords = ["decrease", "efficacy", "failure", "reduce", "lower", "less"]
    
    # Check Clarithromycin logic (25 pts)
    clarith_segment_valid = False
    if any(k in content for k in clarith_keywords):
        # Check if it is associated with toxicity keywords AND NOT efficacy keywords (in close proximity)
        # For simplicity in this prompt, checking presence in the whole file if structured correctly.
        # But to be robust, let's assume the agent follows the "Drug: ... Risk: ..." structure.
        
        # Check if "clarithromycin" lines contain toxicity words
        clarith_lines = [line for line in content.split('\\n') if 'clarithromycin' in line or 'risk' in line]
        # This is hard to parse strictly without regex on the full blob.
        
        # Simple heuristic:
        # Does the text mentioning Clarithromycin also mention Increase/Toxicity?
        # Does the text mentioning Rifampicin also mention Decrease/Efficacy?
        
        # Let's split the text into two chunks if possible, or just regex.
        
        # Regex for Clarithromycin followed by risk description
        clarith_match = re.search(r"clarithromycin.*?(increased|toxicity|raise|high|exposure)", content, re.DOTALL)
        clarith_wrong = re.search(r"clarithromycin.*?(decreased|efficacy|failure|low)", content, re.DOTALL)
        
        if clarith_match and not clarith_wrong:
            score += 25
            clarith_segment_valid = True
            feedback_parts.append("Correctly identified Clarithromycin risk (Increased/Toxicity).")
        elif clarith_match and clarith_wrong:
            # Ambiguous
            score += 10
            feedback_parts.append("Clarithromycin risk mentioned but ambiguous.")
        else:
            feedback_parts.append("Failed to identify Clarithromycin risk correctly.")

    else:
        feedback_parts.append("Clarithromycin not mentioned in report.")

    # Check Rifampicin logic (25 pts)
    rifamp_segment_valid = False
    if any(k in content for k in rifamp_keywords):
        rif_match = re.search(r"rifamp.*?(decreased|efficacy|failure|low|reduce)", content, re.DOTALL)
        rif_wrong = re.search(r"rifamp.*?(increased|toxicity|raise|high)", content, re.DOTALL)
        
        if rif_match and not rif_wrong:
            score += 25
            rifamp_segment_valid = True
            feedback_parts.append("Correctly identified Rifampicin risk (Decreased/Efficacy).")
        elif rif_match and rif_wrong:
            score += 10
            feedback_parts.append("Rifampicin risk mentioned but ambiguous.")
        else:
            feedback_parts.append("Failed to identify Rifampicin risk correctly.")
    else:
        feedback_parts.append("Rifampicin not mentioned in report.")

    # 4. VLM Verification (40 pts)
    # Did they actually open the detail pages?
    # We need to see "Interaction Details" header AND ("Clarithromycin" OR "Rifampicin") in the frames.
    
    frames = sample_trajectory_frames(traj, n=8)
    if not frames:
        # Fallback if no frames available (shouldn't happen in real env)
        feedback_parts.append("No trajectory frames for VLM verification.")
    else:
        prompt = """
        Analyze these screenshots from a drug interaction app.
        I need to verify if the user viewed the detailed interaction text for specific drugs.
        
        Look for:
        1. A screen showing 'Interaction Details' (or similar header) with 'Clarithromycin'.
        2. A screen showing 'Interaction Details' (or similar header) with 'Rifampicin'.
        3. A screen showing 'Ribociclib'.
        
        Return JSON:
        {
          "viewed_clarithromycin_details": boolean,
          "viewed_rifampicin_details": boolean,
          "viewed_ribociclib": boolean
        }
        """
        
        vlm_res = query_vlm(images=frames, prompt=prompt)
        vlm_data = vlm_res.get('parsed', {})
        
        vlm_score = 0
        if vlm_data.get('viewed_ribociclib'): vlm_score += 10
        if vlm_data.get('viewed_clarithromycin_details'): vlm_score += 15
        if vlm_data.get('viewed_rifampicin_details'): vlm_score += 15
        
        score += vlm_score
        feedback_parts.append(f"VLM Verification Score: {vlm_score}/40")

    passed = (score >= 80) and clarith_segment_valid and rifamp_segment_valid

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }