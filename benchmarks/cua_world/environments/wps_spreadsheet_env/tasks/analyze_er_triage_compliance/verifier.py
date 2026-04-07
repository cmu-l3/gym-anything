#!/usr/bin/env python3
"""
Verifier for analyze_er_triage_compliance task.
Evaluates formula correctness, conditional logic, and aggregations using robust Dataframe comparisons.
"""

import sys
import os
import json
import tempfile
import logging
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Verify we can import pandas (standard in host env)
try:
    import pandas as pd
except ImportError:
    logger.error("Pandas is not available in the verifier environment!")
    pd = None

def verify_er_triage(traj, env_info, task_info):
    """Verify SLA compliance calculations and aggregations."""
    if not pd:
        return {"passed": False, "score": 0, "feedback": "Pandas missing from verifier"}

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100

    # 1. Fetch JSON execution metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            meta_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read metadata: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if not meta_result.get("file_modified", False):
        feedback_parts.append("File was NOT modified during the task (anti-gaming)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    else:
        score += 10
        feedback_parts.append("File modified successfully")

    # 2. Fetch the target Excel file
    temp_excel = tempfile.NamedTemporaryFile(delete=False, suffix='.xlsx')
    try:
        copy_from_env("/home/ga/Documents/ed_encounters_august.xlsx", temp_excel.name)

        # Parse with pandas
        xl = pd.ExcelFile(temp_excel.name)
        sheets = xl.sheet_names

        # Validate Encounters sheet
        if 'Encounters' not in sheets:
            feedback_parts.append("'Encounters' sheet missing")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

        df = xl.parse('Encounters')
        cols = [str(c).lower().strip() for c in df.columns]

        # Ensure original data shapes are preserved
        if len(df) < 400:
            feedback_parts.append("Data loss detected in 'Encounters' sheet")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

        # Re-calculate Ground Truth for verification
        df['Arrival_Time'] = pd.to_datetime(df.iloc[:, 1], errors='coerce')
        df['Provider_Seen_Time'] = pd.to_datetime(df.iloc[:, 3], errors='coerce')
        df['Discharge_Time'] = pd.to_datetime(df.iloc[:, 4], errors='coerce')
        df['ESI_Level'] = pd.to_numeric(df.iloc[:, 5], errors='coerce')

        gt_wait = (df['Provider_Seen_Time'] - df['Arrival_Time']).dt.total_seconds() / 60.0
        gt_los = (df['Discharge_Time'] - df['Arrival_Time']).dt.total_seconds() / 3600.0

        def get_gt_sla(row):
            esi = row['ESI_Level']
            wait = row['gt_wait']
            if pd.isna(esi) or pd.isna(wait): return "Unknown"
            if esi <= 3:
                return "Compliant" if wait <= 60 else "Breach"
            else:
                return "Compliant" if wait <= 120 else "Breach"

        df['gt_wait'] = gt_wait
        df['gt_los'] = gt_los
        df['gt_sla'] = df.apply(get_gt_sla, axis=1)

        # Check Column G: Wait Minutes
        wait_col_idx = -1
        for i, c in enumerate(cols):
            if 'wait' in c and 'min' in c:
                wait_col_idx = i
                break

        if wait_col_idx >= 0:
            agent_wait = pd.to_numeric(df.iloc[:, wait_col_idx], errors='coerce')
            # Compare allowing 1 minute rounding difference
            match_rate = np.isclose(agent_wait.fillna(-999), gt_wait.fillna(-999), atol=1.5).mean()
            if match_rate > 0.95:
                score += 10
                feedback_parts.append("Wait Minutes calculated accurately")
            else:
                feedback_parts.append(f"Wait Minutes incorrect (Accuracy: {match_rate:.0%})")
        else:
            feedback_parts.append("Missing Wait_Minutes column")

        # Check Column H: LOS Hours
        los_col_idx = -1
        for i, c in enumerate(cols):
            if 'los' in c and 'hour' in c:
                los_col_idx = i
                break

        if los_col_idx >= 0:
            agent_los = pd.to_numeric(df.iloc[:, los_col_idx], errors='coerce')
            match_rate = np.isclose(agent_los.fillna(-999), gt_los.fillna(-999), atol=0.1).mean()
            if match_rate > 0.95:
                score += 10
                feedback_parts.append("LOS Hours calculated accurately")
            else:
                feedback_parts.append(f"LOS Hours incorrect (Accuracy: {match_rate:.0%})")
        else:
            feedback_parts.append("Missing LOS_Hours column")

        # Check Column I: SLA Status
        sla_col_idx = -1
        for i, c in enumerate(cols):
            if 'sla' in c or 'status' in c:
                sla_col_idx = i
                break

        if sla_col_idx >= 0:
            agent_sla = df.iloc[:, sla_col_idx].astype(str).str.strip().str.title()
            # Agent outputs might be Breach/Compliant
            match_mask = (agent_sla == df['gt_sla'])
            match_rate = match_mask.mean()
            
            if match_rate > 0.95:
                score += 30
                feedback_parts.append("SLA Status conditional logic applied perfectly")
            elif match_rate > 0.5:
                score += 15
                feedback_parts.append(f"SLA Status partially correct (Accuracy: {match_rate:.0%})")
            else:
                feedback_parts.append(f"SLA Status logic failed (Accuracy: {match_rate:.0%})")
        else:
            feedback_parts.append("Missing SLA_Status column")

        # 3. Check Acuity Summary sheet
        summary_sheet_name = [s for s in sheets if 'acuity' in s.lower() and 'summary' in s.lower()]
        if summary_sheet_name:
            df_sum = xl.parse(summary_sheet_name[0])
            score += 10
            feedback_parts.append("Acuity Summary sheet created")
            
            # Identify columns
            cols_sum = [str(c).lower().strip() for c in df_sum.columns]
            
            # Ground truth aggregations
            gt_counts = df['ESI_Level'].value_counts().to_dict()
            gt_avgs = df.groupby('ESI_Level')['gt_wait'].mean().to_dict()
            gt_breaches = df[df['gt_sla'] == 'Breach'].groupby('ESI_Level').size().to_dict()
            
            # Extract agent aggregations
            agent_totals_correct = 0
            agent_breaches_correct = 0
            
            try:
                # Assuming ESI levels are in first column
                for _, row in df_sum.iterrows():
                    try:
                        esi = int(row.iloc[0])
                        if 1 <= esi <= 5:
                            # Look for total patients
                            for idx, c in enumerate(cols_sum):
                                if 'total' in c or 'patient' in c:
                                    agent_total = float(row.iloc[idx])
                                    if np.isclose(agent_total, gt_counts.get(esi, 0), atol=2):
                                        agent_totals_correct += 1
                                elif 'breach' in c:
                                    agent_breach = float(row.iloc[idx])
                                    if np.isclose(agent_breach, gt_breaches.get(esi, 0), atol=2):
                                        agent_breaches_correct += 1
                    except (ValueError, TypeError):
                        continue
                        
                if agent_totals_correct >= 4:
                    score += 10
                    feedback_parts.append("Patient totals aggregated correctly")
                
                if agent_breaches_correct >= 4:
                    score += 10
                    feedback_parts.append("Breach counts aggregated correctly")
                    
            except Exception as e:
                feedback_parts.append(f"Could not parse summary data values: {e}")
        else:
            feedback_parts.append("Acuity Summary sheet NOT found")

        # 4. Trajectory Check (VLM to ensure active workflow)
        query_vlm = env_info.get('query_vlm')
        if query_vlm:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=4)
            vlm_prompt = "Look at these screenshots. Did the user type or edit spreadsheet formulas related to Wait Times, LOS, or SLA logic? Respond in JSON format: {'formula_editing_visible': true/false}"
            try:
                vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
                if vlm_result.get("success") and vlm_result.get("parsed", {}).get("formula_editing_visible", False):
                    score += 10
                    feedback_parts.append("VLM confirmed formula editing trajectory")
                else:
                    feedback_parts.append("VLM did not detect active formula editing")
            except Exception as e:
                logger.error(f"VLM error: {e}")
        else:
            # Grant trajectory points if VLM is unavailable but file was modified and scored well
            if score >= 60:
                score += 10

    except Exception as e:
        logger.error(f"Verification parsing error: {e}", exc_info=True)
        return {"passed": False, "score": score, "feedback": f"Excel evaluation error: {e}"}
    finally:
        if os.path.exists(temp_excel.name):
            os.unlink(temp_excel.name)

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }