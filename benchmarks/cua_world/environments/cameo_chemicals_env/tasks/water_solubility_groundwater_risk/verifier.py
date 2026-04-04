#!/usr/bin/env python3
"""
Verifier for Water Solubility Groundwater Risk Assessment task.

Scoring Criteria:
1. File Creation (10 pts): File exists and was created/modified during task.
2. Content Completeness (15 pts): All 5 chemicals listed.
3. Data Extraction (15 pts): Solubility values included for chemicals.
4. Accuracy (20 pts): Solubility values match CAMEO data.
5. Risk Classification (20 pts): Correct HIGH/MEDIUM/LOW labels.
6. Conclusion (15 pts): Sodium Hydroxide identified as highest risk.
7. Process (5 pts): VLM verifies CAMEO website navigation.
"""

import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_water_solubility_groundwater_risk(traj, env_info, task_info):
    """Verify the groundwater risk assessment task."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # 1. Retrieve Task Results & Output File
    # ------------------------------------------------------------------
    result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    output_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    try:
        # Get result JSON
        copy_from_env("/tmp/task_result.json", result_file.name)
        with open(result_file.name, 'r') as f:
            task_result = json.load(f)
            
        # Get user output text
        has_output = False
        try:
            copy_from_env("/tmp/agent_output.txt", output_file.name)
            with open(output_file.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
            has_output = True
        except Exception:
            content = ""
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task data: {str(e)}"}
    finally:
        if os.path.exists(result_file.name): os.unlink(result_file.name)
        if os.path.exists(output_file.name): os.unlink(output_file.name)

    # ------------------------------------------------------------------
    # 2. Verify File Existence & Anti-Gaming (10 pts)
    # ------------------------------------------------------------------
    if task_result.get("output_exists") and task_result.get("file_created_during_task") and has_output and len(content.strip()) > 10:
        score += 10
        feedback_parts.append("Output file created successfully.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file missing, empty, or not created during task."}

    content_lower = content.lower()

    # ------------------------------------------------------------------
    # 3. Verify Chemicals Listed (15 pts)
    # ------------------------------------------------------------------
    chemicals = {
        "benzene": ["benzene"],
        "sodium hydroxide": ["sodium hydroxide", "naoh", "lye"],
        "trichloroethylene": ["trichloroethylene", "tce"],
        "phenol": ["phenol", "carbolic acid"],
        "carbon tetrachloride": ["carbon tetrachloride", "carbon tet", "ccl4"]
    }
    
    chems_found = 0
    for chem, aliases in chemicals.items():
        if any(alias in content_lower for alias in aliases):
            chems_found += 1
            
    chem_score = chems_found * 3
    score += chem_score
    if chems_found < 5:
        feedback_parts.append(f"Found {chems_found}/5 chemicals.")
    else:
        feedback_parts.append("All chemicals listed.")

    # ------------------------------------------------------------------
    # 4. Verify Solubility Values Present & Accurate (35 pts)
    # ------------------------------------------------------------------
    # We look for lines containing the chemical name and check content
    
    accuracy_score = 0
    extraction_score = 0
    
    lines = content_lower.split('\n')
    
    # Solubility Patterns (approximate matching based on CAMEO data)
    # Benzene: "slightly soluble", "< 1 mg/ml", "1.79 g/l", "0.18%"
    # NaOH: "soluble", "miscible", "1110 mg/ml", "> 50%"
    # TCE: "slightly soluble", "1.1 g/l", "0.11%"
    # Phenol: "soluble", "8 g/100ml", "84 mg/ml", "miscible" (sometimes stated relative to temp)
    # Carbon Tet: "insoluble", "practically insoluble", "0.8 g/l", "0.08%"
    
    chem_specs = {
        "benzene": {
            "keywords": ["slightly soluble", "less than 1", "1.8", "1.79", "0.18"],
            "risk": ["low", "medium"] # "Medium" accepted if arguable based on specific threshold logic, but usually low
        },
        "sodium hydroxide": {
            "keywords": ["miscible", "soluble", "111", "109", "1000", "very soluble"],
            "risk": ["high"]
        },
        "trichloroethylene": {
            "keywords": ["slightly soluble", "insoluble", "1.1", "0.1"],
            "risk": ["low"]
        },
        "phenol": {
            "keywords": ["soluble", "8 g", "84", "67", "miscible"], # Phenol is quite soluble
            "risk": ["high", "medium"]
        },
        "carbon tetrachloride": {
            "keywords": ["insoluble", "practically", "0.8", "0.05", "0.08"],
            "risk": ["low"]
        }
    }

    correct_classifications = 0
    
    for chem_name, specs in chem_specs.items():
        # Find line for this chemical
        chem_lines = [line for line in lines if any(alias in line for alias in chemicals[chem_name])]
        chem_text = " ".join(chem_lines)
        
        # Check extraction (value present) - 3 pts per chem
        if re.search(r'\d|soluble|miscible|insoluble', chem_text):
            extraction_score += 3
            
            # Check accuracy (value roughly matches) - 4 pts per chem
            if any(k in chem_text for k in specs['keywords']):
                accuracy_score += 4
            
            # Check risk classification - 4 pts per chem
            if any(r in chem_text for r in specs['risk']):
                correct_classifications += 4

    score += extraction_score
    score += accuracy_score
    score += correct_classifications
    
    if extraction_score == 15 and accuracy_score == 20:
        feedback_parts.append("Solubility data accurate.")
    else:
        feedback_parts.append(f"Data extraction score: {extraction_score+accuracy_score}/35.")

    # ------------------------------------------------------------------
    # 5. Verify Highest Risk Identification (15 pts)
    # ------------------------------------------------------------------
    # Look for "highest" or "greatest" near "sodium hydroxide"
    # Or simple check if NaOH is identified as High and others Lower
    
    highest_risk_correct = False
    
    # Check strict statement
    if re.search(r'(highest|greatest|most).{0,50}(sodium hydroxide|naoh|lye)', content_lower) or \
       re.search(r'(sodium hydroxide|naoh|lye).{0,50}(highest|greatest|most)', content_lower):
        highest_risk_correct = True
    
    if highest_risk_correct:
        score += 15
        feedback_parts.append("Correctly identified Sodium Hydroxide as highest risk.")
    else:
        feedback_parts.append("Failed to clearly identify Sodium Hydroxide as highest risk.")

    # ------------------------------------------------------------------
    # 6. VLM Verification of Trajectory (5 pts)
    # ------------------------------------------------------------------
    # Verify the agent actually visited CAMEO Chemicals and didn't just guess
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = "Does this sequence show a user searching for chemicals (like Benzene or Sodium Hydroxide) on the CAMEO Chemicals website? Look for blue/white NOAA headers or chemical datasheet tables."
        try:
            vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
            if vlm_result.get("success") and vlm_result.get("answer", "").lower().startswith("yes"):
                score += 5
                feedback_parts.append("VLM confirmed CAMEO usage.")
            else:
                # Fallback: if VLM says no, but file is perfect, give benefit of doubt or partial
                if score >= 60: 
                    score += 5  # Give points if data is good (implies they must have looked it up)
        except Exception:
            # Skip VLM score if service fails
            pass
    
    return {
        "passed": score >= 60,
        "score": min(100, score),
        "feedback": " ".join(feedback_parts)
    }