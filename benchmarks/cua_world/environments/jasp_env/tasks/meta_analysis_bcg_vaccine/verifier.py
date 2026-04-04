#!/usr/bin/env python3
"""
Verifier for Meta-Analysis BCG Vaccine task.

Verification Logic:
1. Check if the JASP file exists and is a valid ZIP archive (JASP format).
2. Inspect internal JSON/content of JASP file for specific analysis configurations:
   - Analysis type: Meta-analysis
   - Variables: ES (Effect Size), SE (Standard Error)
   - Moderator/Covariate: alloc
   - Plots: Forest Plot, Funnel Plot
3. Verify the text report contains a plausible p-value for the moderator.
4. Verify via VLM that the Forest Plot is visible in the trajectory.
"""

import json
import os
import zipfile
import tempfile
import re
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_meta_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    score = 0
    feedback_parts = []
    
    # =========================================================
    # 1. Retrieve Result JSON & Files
    # =========================================================
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_jasp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.jasp')
    temp_report_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    try:
        # Get metadata JSON
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            result_data = json.load(f)
            
        # Get JASP file
        jasp_exists = result_data.get('jasp_file_exists', False)
        if jasp_exists:
            try:
                copy_from_env(metadata['expected_jasp_path'], temp_jasp_file.name)
            except Exception:
                jasp_exists = False
                feedback_parts.append("Failed to copy JASP file")

        # Get Report file
        report_exists = result_data.get('report_exists', False)
        if report_exists:
            try:
                copy_from_env(metadata['expected_report_path'], temp_report_file.name)
            except Exception:
                report_exists = False

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error retrieving files: {e}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)

    # =========================================================
    # 2. Verify JASP File Content (40 points)
    # =========================================================
    analysis_configured = False
    moderator_found = False
    plots_found = False

    if jasp_exists:
        score += 10
        feedback_parts.append("JASP file created")
        
        if result_data.get('jasp_file_created_during_task', False):
            score += 10
            feedback_parts.append("File created during task")

        # Inspect JASP internal structure
        # JASP files are ZIPs containing analysis definitions
        try:
            with zipfile.ZipFile(temp_jasp_file.name, 'r') as z:
                # Search through all files in the archive for keywords
                # We look for JSON files or the analysis state
                content_found = ""
                for filename in z.namelist():
                    if filename.endswith('.json') or filename.endswith('analysis'):
                        try:
                            with z.open(filename) as f:
                                content_found += f.read().decode('utf-8', errors='ignore')
                        except:
                            pass
                
                # Check for Meta Analysis configuration
                # JASP internal keys often look like "metaAnalysis", "effectSize", etc.
                if "metaAnalysis" in content_found or "Meta-Analysis" in content_found:
                    analysis_configured = True
                    score += 10
                    feedback_parts.append("Meta-Analysis module used")
                
                # Check for Covariate/Moderator 'alloc'
                if "alloc" in content_found and ("covariates" in content_found.lower() or "moderators" in content_found.lower()):
                    moderator_found = True
                    score += 20
                    feedback_parts.append("Moderator 'alloc' configured")
                
                # Check for Plots
                if "forestPlot" in content_found and "funnelPlot" in content_found:
                    plots_found = True
                    score += 10
                    feedback_parts.append("Forest and Funnel plots enabled")
                    
        except zipfile.BadZipFile:
            feedback_parts.append("JASP file is not a valid ZIP archive")
    else:
        feedback_parts.append("JASP file NOT found")

    # =========================================================
    # 3. Verify Report Content (20 points)
    # =========================================================
    report_valid = False
    if report_exists:
        try:
            with open(temp_report_file.name, 'r') as f:
                content = f.read().lower()
            
            # Look for a number
            match = re.search(r"0\.\d+", content)
            if match:
                p_val = float(match.group(0))
                # Known truth: alloc is significant (p < 0.05, often ~0.006)
                if 0.0 <= p_val <= 0.06:
                    score += 20
                    report_valid = True
                    feedback_parts.append(f"Reported valid significant p-value: {p_val}")
                else:
                    score += 5
                    feedback_parts.append(f"Reported p-value {p_val} seems incorrect (expected < 0.05)")
            else:
                feedback_parts.append("Report exists but no p-value found")
        except Exception:
            feedback_parts.append("Could not read report file")
    else:
        feedback_parts.append("Report file NOT found")

    # Clean up temp files
    if os.path.exists(temp_jasp_file.name):
        os.unlink(temp_jasp_file.name)
    if os.path.exists(temp_report_file.name):
        os.unlink(temp_report_file.name)

    # =========================================================
    # 4. VLM Verification (20 points)
    # =========================================================
    # Check if Forest Plot was visible at any point
    frames = sample_trajectory_frames(traj, n=5)
    
    vlm_prompt = """
    Review these screenshots of JASP statistical software.
    1. Is a "Forest Plot" visible? (A plot with horizontal lines and a diamond at the bottom)
    2. Are there Study Labels on the plot (names like "Aronson", "Ferguson")?
    3. Is a "Funnel Plot" visible? (A triangular scatter plot)
    
    Return JSON: {"forest_plot_visible": bool, "study_labels_visible": bool, "funnel_plot_visible": bool}
    """
    
    vlm_score = 0
    try:
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        parsed = vlm_res.get('parsed', {})
        
        if parsed.get('forest_plot_visible', False):
            vlm_score += 10
            feedback_parts.append("VLM confirmed Forest Plot visibility")
        
        if parsed.get('funnel_plot_visible', False):
            vlm_score += 10
            feedback_parts.append("VLM confirmed Funnel Plot visibility")
            
        score += vlm_score
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback points if programmatic checks passed strongly
        if analysis_configured and plots_found:
            score += 10
            feedback_parts.append("Skipped VLM (programmatic checks passed)")

    # =========================================================
    # Final Scoring
    # =========================================================
    # Passing logic: Must have configured analysis + moderator + report OR analysis + moderator + VLM confirmation
    # Threshold 80 implies high standard
    
    passed = score >= 80 and analysis_configured and moderator_found
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }