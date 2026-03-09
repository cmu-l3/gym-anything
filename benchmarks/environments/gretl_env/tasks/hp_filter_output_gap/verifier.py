#!/usr/bin/env python3
"""
Verifier for hp_filter_output_gap task.

Verification Strategy:
1. File Existence & Anti-Gaming: Check if files were created after task start.
2. Dataset Integrity (XML Parsing): Parse the output .gdt file (XML format) to extract series.
3. Mathematical Verification:
   - Check if Output Gap = (Cycle / Trend) * 100
   - Check if GDP approx Trend + Cycle
   - (Optional) Re-run HP filter using statsmodels to verify lambda=1600 usage.
4. Report Consistency: Parse the text report and verify the numbers match the dataset statistics.
"""

import json
import os
import re
import tempfile
import math
import numpy as np
import xml.etree.ElementTree as ET
from datetime import datetime

# Try to import statsmodels for ground truth HP filter calculation
STATSMODELS_AVAILABLE = False
try:
    from statsmodels.tsa.filters.hp_filter import hpfilter
    STATSMODELS_AVAILABLE = True
except ImportError:
    pass

def parse_gdt_file(file_path):
    """
    Parses a Gretl Data File (.gdt) which is XML-based.
    Returns a dictionary of variables and their data series.
    """
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
        
        # Check frequency (should be 4 for quarterly)
        freq = int(root.attrib.get('frequency', 0))
        start_obs = root.attrib.get('startobs', '')
        
        variables = {}
        
        # GDT format: <variables> <variable name="..."> ... </variables>
        # Data is in <observations> <obs>val1 val2 ...</obs> ... </observations>
        # OR data is inline inside variables?
        # Usually GDT XML structure:
        # <gretldata>
        #   <variables count="N">
        #     <variable name="var1" .../>
        #     ...
        #   </variables>
        #   <observations>
        #     <obs>val1_var1 val1_var2 ...</obs>
        #   </observations>
        # </gretldata>
        
        var_names = []
        for var in root.findall('.//variable'):
            var_names.append(var.attrib.get('name'))
            
        data = {name: [] for name in var_names}
        
        # Parse observations
        # <obs> values... </obs>
        obs_nodes = root.findall('.//obs')
        
        if not obs_nodes:
            return None, "No observations found in GDT"

        for obs in obs_nodes:
            text = obs.text.strip()
            vals = text.split()
            if len(vals) != len(var_names):
                continue # Skip malformed lines
            for i, val in enumerate(vals):
                try:
                    data[var_names[i]].append(float(val))
                except ValueError:
                    data[var_names[i]].append(None)
                    
        return data, None
        
    except ET.ParseError:
        return None, "XML Parse Error"
    except Exception as e:
        return None, str(e)

def extract_numbers_from_report(report_text):
    """Extracts potential statistics from the report text."""
    # Find numbers that look like stats
    # Look for specific keywords
    stats = {}
    
    text_lower = report_text.lower()
    
    # Lambda
    lambda_match = re.search(r'lambda\s*[=:]?\s*(\d+)', text_lower)
    if lambda_match:
        stats['lambda'] = int(lambda_match.group(1))
        
    # Mean
    mean_match = re.search(r'mean\s*[=:]?\s*([-+]?\d*\.\d+|\d+)', text_lower)
    if mean_match:
        stats['mean'] = float(mean_match.group(1))
        
    # Std Dev
    std_match = re.search(r'(std|standard)\.?\s*(dev|deviation)\.?\s*[=:]?\s*([-+]?\d*\.\d+|\d+)', text_lower)
    if std_match:
        stats['std'] = float(std_match.group(3))
        
    # Count negative
    neg_match = re.search(r'(negative|below).*(\d+)|(\d+).*(negative|below)', text_lower)
    # This is tricky regex, let's look for integers near "negative"
    neg_count = None
    tokens = text_lower.split()
    if 'negative' in tokens:
        idx = tokens.index('negative')
        # Look around
        for i in range(max(0, idx-5), min(len(tokens), idx+5)):
            if tokens[i].isdigit():
                neg_count = int(tokens[i])
                break
    stats['neg_count'] = neg_count

    # Largest negative date (format like 1982:1 or 2008:3)
    date_match = re.search(r'(\d{4}:\d)', text_lower)
    if date_match:
        stats['min_date'] = date_match.group(1)
        
    return stats

def verify_hp_filter_output_gap(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Temporary files
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    temp_data_gdt = tempfile.NamedTemporaryFile(delete=False, suffix='.gdt').name
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt').name
    temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.inp').name

    score = 0
    feedback = []
    
    try:
        # 1. Load result JSON
        copy_from_env("/tmp/task_result.json", temp_result_json)
        with open(temp_result_json, 'r') as f:
            result = json.load(f)
            
        files = result.get('files', {})
        task_start = result.get('task_start_time', 0)
        
        # 2. Verify File Existence & Anti-Gaming (20 pts)
        files_exist = True
        for fname in ['script', 'dataset', 'report']:
            finfo = files.get(fname, {})
            if not finfo.get('exists'):
                feedback.append(f"Missing file: {fname}")
                files_exist = False
            elif finfo.get('mtime', 0) <= task_start:
                feedback.append(f"File {fname} was not created during task (timestamp check failed)")
                files_exist = False
            elif finfo.get('size', 0) < 10:
                feedback.append(f"File {fname} is empty")
                files_exist = False
        
        if files_exist:
            score += 20
            feedback.append("All required files created.")
        else:
            return {"passed": False, "score": score, "feedback": "; ".join(feedback)}

        # 3. Analyze Script Content (10 pts)
        copy_from_env("/home/ga/Documents/gretl_output/hp_analysis.inp", temp_script)
        with open(temp_script, 'r') as f:
            script_content = f.read().lower()
            
        if 'hp' in script_content and '1600' in script_content:
            score += 10
            feedback.append("Script contains HP filter command and lambda 1600.")
        elif 'hp' in script_content:
            score += 5
            feedback.append("Script contains HP filter command but lambda 1600 not found.")
        else:
            feedback.append("Script does not appear to use HP filter.")

        # 4. Analyze Dataset (40 pts)
        copy_from_env("/home/ga/Documents/gretl_output/usa_hp_decomposed.gdt", temp_data_gdt)
        data, err = parse_gdt_file(temp_data_gdt)
        
        if err:
            feedback.append(f"Failed to parse GDT dataset: {err}")
            stats_correct = False
        else:
            required_vars = ['gdp', 'hp_cycle', 'hp_trend', 'output_gap']
            missing_vars = [v for v in required_vars if v not in data]
            
            if missing_vars:
                feedback.append(f"Dataset missing variables: {missing_vars}")
                stats_correct = False
            else:
                score += 10 # Structure correct
                
                gdp = np.array(data['gdp'])
                cycle = np.array(data['hp_cycle'])
                trend = np.array(data['hp_trend'])
                gap = np.array(data['output_gap'])
                
                # Check 1: Additivity (gdp ~ trend + cycle)
                # Allow small floating point error
                recon_error = np.mean(np.abs(gdp - (trend + cycle)))
                if recon_error < 1.0:
                    score += 10
                    feedback.append("Cycle + Trend reconstructs GDP correctly.")
                else:
                    feedback.append(f"Cycle + Trend does not match GDP (MAE: {recon_error}).")
                    
                # Check 2: Output Gap Formula (gap = 100 * cycle / trend)
                calc_gap = 100 * cycle / trend
                gap_error = np.mean(np.abs(gap - calc_gap))
                if gap_error < 0.1:
                    score += 10
                    feedback.append("Output Gap formula is correct.")
                else:
                    feedback.append(f"Output Gap values incorrect (MAE: {gap_error}).")
                    
                # Check 3: HP Filter Lambda Verification (Ground Truth)
                if STATSMODELS_AVAILABLE:
                    gt_cycle, gt_trend = hpfilter(gdp, lamb=1600)
                    hp_error = np.mean(np.abs(cycle - gt_cycle))
                    if hp_error < 1.0: # Allow slight diffs between implementations
                        score += 10
                        feedback.append("HP Filter values match Ground Truth (lambda=1600).")
                    else:
                        feedback.append(f"HP Filter values diverge from lambda=1600 ground truth (MAE: {hp_error}).")
                else:
                    # Fallback if statsmodels missing: check if cycle is mean-reverting (mean near 0)
                    if abs(np.mean(cycle)) < 10:
                        score += 10
                        feedback.append("Cycle component is zero-mean (proxy verification).")
                
                # Calculate True Stats for Report Verification
                true_mean = np.mean(gap)
                true_std = np.std(gap, ddof=1) # Sample std dev usually
                true_neg_count = np.sum(gap < 0)
                
                # Find min date (date logic depends on start obs 1984:1)
                # 1984:1 is index 0
                min_idx = np.argmin(gap)
                
                # Convert index to quarter
                # 1984:1 -> 0
                total_quarters = min_idx
                years = 1984 + (total_quarters // 4)
                qtr = (total_quarters % 4) + 1
                true_min_date = f"{years}:{qtr}"
                
                stats_correct = True

        # 5. Analyze Report (30 pts)
        copy_from_env("/home/ga/Documents/gretl_output/hp_report.txt", temp_report)
        with open(temp_report, 'r') as f:
            report_text = f.read()
            
        if len(report_text) > 10:
            reported = extract_numbers_from_report(report_text)
            
            report_score = 0
            
            # Check Lambda
            if reported.get('lambda') == 1600:
                report_score += 5
            
            if stats_correct:
                # Check Mean (tolerance 0.1)
                if 'mean' in reported and abs(reported['mean'] - true_mean) < 0.1:
                    report_score += 5
                
                # Check Std (tolerance 0.1)
                if 'std' in reported and abs(reported['std'] - true_std) < 0.1:
                    report_score += 5
                    
                # Check Count (exact or off-by-one)
                if 'neg_count' in reported and abs(reported['neg_count'] - true_neg_count) <= 1:
                    report_score += 10
                elif 'neg_count' in reported:
                     # Partial credit for being close
                     if abs(reported['neg_count'] - true_neg_count) <= 5:
                         report_score += 5
                
                # Check Date
                if 'min_date' in reported and reported['min_date'] == true_min_date:
                    report_score += 5
            
            score += report_score
            feedback.append(f"Report analysis score: {report_score}/30")
            if stats_correct:
                feedback.append(f"Ground Truth: Mean={true_mean:.2f}, Std={true_std:.2f}, NegCount={true_neg_count}, MinDate={true_min_date}")
        else:
            feedback.append("Report file is empty or too short.")

    except Exception as e:
        score = 0
        feedback.append(f"Verification error: {str(e)}")
    finally:
        # Cleanup
        for f in [temp_result_json, temp_data_gdt, temp_report, temp_script]:
            if os.path.exists(f):
                os.unlink(f)

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }