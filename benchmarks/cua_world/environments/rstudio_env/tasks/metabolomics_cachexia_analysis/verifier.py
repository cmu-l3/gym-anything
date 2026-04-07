#!/usr/bin/env python3
"""
Verifier for metabolomics_cachexia_analysis task.

Verifies:
1. Deliverable existence and age (anti-gaming via mtime > start_time).
2. CSV Formatting: presence of required columns.
3. Statistical Accuracy: Computes ground truth Log2FC and p-values using pandas/scipy,
   then correlates with the agent's results.
4. Visual Output: VLM verification of the Volcano plot and trajectory.
"""

import os
import json
import tempfile
import logging
import pandas as pd
import numpy as np
from scipy import stats
from statsmodels.stats.multitest import multipletests

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Paths in the container
RESULT_JSON_PATH = "/tmp/metabolomics_result.json"
AGENT_CSV_PATH = "/tmp/agent_results.csv"
AGENT_PNG_PATH = "/tmp/agent_volcano.png"
ORIGINAL_DATA_PATH = "/tmp/original_data.csv"

# VLM Prompt
VLM_PROMPT = """You are evaluating a bioinformatics task in RStudio. 

The agent was required to generate a Volcano Plot for metabolomics data.
A Volcano Plot should be a scatter plot with:
- X-axis showing Fold Change or Log2 Fold Change (values typically negative and positive, e.g., -2 to 2)
- Y-axis showing -log10(p-value) (values starting from 0 extending upwards, e.g., 0 to 5+)
- Distinctly colored points for statistically significant metabolites (often in red, blue, or green) versus non-significant ones (often in grey/black).

Look at the trajectory frames and the final screenshot.
1. Did the agent write R code to compute statistics and generate a plot?
2. Does the final image actually show a Volcano Plot meeting the description above?
3. Ensure this is not just a placeholder, blank plot, or a completely different type of chart.

Respond in JSON format:
{
    "code_written": true/false,
    "is_volcano_plot": true/false,
    "has_distinct_colors_for_significance": true/false,
    "axes_look_correct": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation"
}
"""

def compute_ground_truth(data_path):
    """Computes expected Log2FC, p-values, and FDR based on task rules."""
    try:
        df = pd.read_csv(data_path)
        # Identify grouping column
        group_col = None
        for col in ['Muscle.wasting', 'Muscle wasting', 'Group', 'Patient Type']:
            if col in df.columns:
                group_col = col
                break
        
        if not group_col:
            return None, "Grouping column not found in raw dataset."

        # The rest of the columns (except Patient.ID) are metabolites
        exclude_cols = [group_col, 'Patient.ID', 'Patient ID', 'Sample']
        metabolites = [c for c in df.columns if c not in exclude_cols]

        results = []
        for met in metabolites:
            # 1. Extract
            vals = df[[group_col, met]].copy()
            vals[met] = pd.to_numeric(vals[met], errors='coerce')
            
            # 2. Impute missing with half min positive
            pos_vals = vals[vals[met] > 0][met]
            if len(pos_vals) > 0:
                min_pos = pos_vals.min()
                vals[met] = vals[met].fillna(min_pos / 2.0)
            
            # 3. Log2 Transform
            vals[met] = np.log2(vals[met].clip(lower=1e-9))
            
            # 4. Split groups
            cachexic = vals[vals[group_col].str.lower() == 'cachexic'][met].dropna()
            control = vals[vals[group_col].str.lower() == 'control'][met].dropna()
            
            if len(cachexic) < 2 or len(control) < 2:
                continue

            # 5. Welch's t-test
            t_stat, p_val = stats.ttest_ind(cachexic, control, equal_var=False)
            
            # 6. Log2FC
            log2fc = cachexic.mean() - control.mean()
            
            results.append({
                'metabolite': met,
                'gt_log2fc': log2fc,
                'gt_pval': p_val
            })
            
        res_df = pd.DataFrame(results).dropna()
        if len(res_df) == 0:
            return None, "Failed to compute stats for any metabolite."
            
        # 7. FDR
        _, fdr, _, _ = multipletests(res_df['gt_pval'], method='fdr_bh')
        res_df['gt_fdr'] = fdr
        return res_df, None
        
    except Exception as e:
        return None, f"Exception computing ground truth: {e}"

def verify_metabolomics_cachexia(traj, env_info, task_info):
    """Main verification logic."""
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    feedback = []
    score = 0
    
    # 1. Retrieve Result JSON
    with tempfile.NamedTemporaryFile(delete=False) as f:
        tmp_json = f.name
    try:
        copy_from_env(RESULT_JSON_PATH, tmp_json)
        with open(tmp_json, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve export JSON: {e}"}
    finally:
        if os.path.exists(tmp_json): os.unlink(tmp_json)

    # Base checks
    if not result_meta.get("script_modified"):
        feedback.append("Agent did not write code in the provided script.")
    else:
        feedback.append("Script was modified.")

    csv_exists = result_meta.get("csv_exists") and result_meta.get("csv_is_new")
    plot_exists = result_meta.get("plot_exists") and result_meta.get("plot_is_new")

    # 2. Verify CSV Accuracy
    if csv_exists:
        score += 10
        feedback.append("Output CSV exists and is new (+10).")
        
        with tempfile.TemporaryDirectory() as td:
            local_agent_csv = os.path.join(td, "agent.csv")
            local_raw_data = os.path.join(td, "raw.csv")
            
            try:
                copy_from_env(AGENT_CSV_PATH, local_agent_csv)
                copy_from_env(ORIGINAL_DATA_PATH, local_raw_data)
                
                agent_df = pd.read_csv(local_agent_csv)
                gt_df, err = compute_ground_truth(local_raw_data)
                
                # Check Columns
                required_cols = ['metabolite', 'log2_fc', 'p_value', 'fdr', 'significant']
                agent_cols = [c.lower() for c in agent_df.columns]
                missing = [c for c in required_cols if c not in agent_cols]
                
                if not missing:
                    score += 15
                    feedback.append("CSV has all required columns (+15).")
                else:
                    feedback.append(f"CSV missing columns: {missing}")
                
                # Statistical correlation
                if gt_df is not None and len(agent_df) > 0:
                    # Clean up names for merging
                    # Agent might have preserved R's safe names (e.g., "X1.Methylhistidine")
                    # We will match on rows assuming order is preserved or try to merge loosely
                    gt_df['match_key'] = gt_df['metabolite'].str.replace(r'[^a-zA-Z0-9]', '', regex=True).str.lower()
                    
                    # Find agent metabolite column
                    met_col = next((c for c in agent_df.columns if c.lower() == 'metabolite'), agent_df.columns[0])
                    p_col = next((c for c in agent_df.columns if c.lower() == 'p_value'), None)
                    fc_col = next((c for c in agent_df.columns if c.lower() == 'log2_fc'), None)
                    fdr_col = next((c for c in agent_df.columns if c.lower() == 'fdr'), None)
                    
                    agent_df['match_key'] = agent_df[met_col].astype(str).str.replace(r'[^a-zA-Z0-9]', '', regex=True).str.lower()
                    
                    merged = pd.merge(gt_df, agent_df, on='match_key', how='inner')
                    
                    if len(merged) > 10:
                        # Check P-value correlation
                        if p_col:
                            corr_p = np.corrcoef(merged['gt_pval'], merged[p_col])[0, 1]
                            if corr_p > 0.95:
                                score += 20
                                feedback.append("P-values strongly correlate with ground truth (+20).")
                            elif corr_p > 0.5:
                                score += 10
                                feedback.append(f"P-values partially correlate (r={corr_p:.2f}) (+10).")
                            else:
                                feedback.append(f"P-values do not match expected (r={corr_p:.2f}).")
                                
                        # Check Log2FC direction
                        if fc_col:
                            # Sometimes direction is flipped if agent did Control - Cachexic
                            corr_fc = np.corrcoef(merged['gt_log2fc'], merged[fc_col])[0, 1]
                            if corr_fc > 0.95:
                                score += 15
                                feedback.append("Log2FC matches expected direction and magnitude (+15).")
                            elif corr_fc < -0.95:
                                score += 5
                                feedback.append("Log2FC is inverted (Control vs Cachexic instead of Cachexic vs Control) (+5).")
                            else:
                                feedback.append(f"Log2FC does not match expected (r={corr_fc:.2f}).")
                                
                        # Check FDR correlation
                        if fdr_col:
                            corr_fdr = np.corrcoef(merged['gt_fdr'], merged[fdr_col])[0, 1]
                            if corr_fdr > 0.95:
                                score += 10
                                feedback.append("FDR values correctly computed (+10).")
                            else:
                                feedback.append("FDR values do not match BH correction expectations.")
                    else:
                        feedback.append(f"Could only match {len(merged)} metabolites for verification. Check naming.")
                else:
                    feedback.append(f"Ground truth generation failed or agent CSV empty: {err}")
                    
            except Exception as e:
                feedback.append(f"Error during CSV verification: {e}")
    else:
        feedback.append("Output CSV was not found or was not created during the task.")

    # 3. Verify Plot via Size and VLM
    if plot_exists:
        if result_meta.get("plot_size_bytes", 0) > 15000:
            score += 10
            feedback.append("Volcano plot PNG exists and has substantial size (+10).")
            
            if query_vlm:
                try:
                    from gym_anything.vlm import get_final_screenshot, sample_trajectory_frames
                    frames = sample_trajectory_frames(traj, n=3)
                    final = get_final_screenshot(traj)
                    
                    vlm_res = query_vlm(
                        prompt=VLM_PROMPT,
                        images=frames + [final] if final else frames
                    )
                    
                    if vlm_res.get("success"):
                        vlm_data = vlm_res.get("parsed", {})
                        if vlm_data.get("is_volcano_plot"):
                            score += 10
                            feedback.append("VLM confirmed plot is a valid Volcano plot (+10).")
                            if vlm_data.get("has_distinct_colors_for_significance"):
                                score += 10
                                feedback.append("VLM confirmed significant features are distinctly colored (+10).")
                        else:
                            feedback.append("VLM did not recognize the image as a Volcano plot.")
                    else:
                        feedback.append("VLM query failed.")
                except Exception as e:
                    feedback.append(f"VLM verification error: {e}")
        else:
            feedback.append("Volcano plot file is too small (might be empty or invalid).")
    else:
        feedback.append("Volcano plot PNG was not found or not created during task.")

    # Pass threshold: must have the basic CSV and plot, plus some accuracy
    passed = score >= 65 and csv_exists and plot_exists
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": "\n".join(feedback)
    }