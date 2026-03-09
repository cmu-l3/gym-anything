#!/usr/bin/env python3
"""
Verifier for piecewise_spline_food task.

Checks:
1. Regression output file exists and contains correct OLS results for the spline model.
2. Slope output file exists and contains the correct calculated marginal effect.
3. Files were created during the task.
"""

import json
import os
import tempfile
import logging
import re
import math
import pandas as pd
import numpy as np
import statsmodels.api as sm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Raw data from food.gdt (Hill, Griffiths, Lim, Table 2.1)
# food_exp (y), income (x)
RAW_DATA = [
    (115.22, 3.69), (135.98, 4.39), (119.34, 4.75), (114.96, 6.03),
    (187.05, 12.47), (243.43, 12.98), (109.71, 3.15), (197.23, 12.00),
    (263.29, 16.31), (251.84, 12.13), (147.22, 7.99), (230.77, 12.63),
    (182.43, 8.93), (248.13, 10.01), (220.84, 8.79), (337.62, 19.06),
    (167.38, 9.09), (217.37, 10.91), (327.28, 15.18), (355.76, 20.01),
    (176.17, 9.69), (352.86, 20.00), (192.43, 7.63), (207.39, 12.80),
    (321.62, 15.29), (274.54, 15.72), (312.05, 22.66), (261.74, 13.59),
    (263.99, 11.51), (296.24, 17.70), (265.30, 13.85), (313.18, 14.12),
    (300.68, 21.23), (279.22, 16.54), (374.22, 24.22), (377.52, 24.16),
    (260.35, 17.32), (382.14, 25.51), (374.76, 25.08), (404.90, 26.75)
]

def calculate_ground_truth():
    """Calculates the expected OLS coefficients for the spline model."""
    df = pd.DataFrame(RAW_DATA, columns=['food_exp', 'income'])
    
    # Create spline variable: max(0, income - 20)
    df['income_over_20'] = df['income'].apply(lambda x: max(0, x - 20))
    
    # Add constant
    X = df[['income', 'income_over_20']]
    X = sm.add_constant(X)
    y = df['food_exp']
    
    model = sm.OLS(y, X).fit()
    
    return {
        'const': model.params['const'],
        'income': model.params['income'],
        'income_over_20': model.params['income_over_20'],
        'high_income_slope': model.params['income'] + model.params['income_over_20']
    }

def verify_piecewise_spline_food(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Calculate Ground Truth
    try:
        gt = calculate_ground_truth()
        logger.info(f"Ground Truth: {gt}")
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verifier error calculating ground truth: {e}"}

    # 2. Get Agent Metadata
    temp_meta = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_meta.name)
        with open(temp_meta.name, 'r') as f:
            metadata = json.load(f)
    except Exception:
        metadata = {}
    finally:
        if os.path.exists(temp_meta.name):
            os.unlink(temp_meta.name)

    score = 0
    feedback = []

    # 3. Check Regression Output File
    reg_file_exists = metadata.get('regression_output_exists', False)
    reg_created_during = metadata.get('regression_created_during_task', False)
    
    if not reg_file_exists:
        feedback.append("Regression output file not found.")
    elif not reg_created_during:
        feedback.append("Regression output file timestamp invalid (not created during task).")
    else:
        score += 10 # File exists and is new
        
        # Verify Content
        temp_reg = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/home/ga/Documents/gretl_output/spline_regression.txt", temp_reg.name)
            with open(temp_reg.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
            
            # Look for coefficients in the text output
            # Gretl output typically looks like:
            #            coefficient   std. error   t-ratio   p-value 
            #  -------------------------------------------------------
            #  const       85.0       ...
            #  income      10.0       ...
            #  income_over_20  -5.0   ...
            
            # Simple regex to find numbers near variable names
            # We look for the variable name, followed by some spaces, then a float
            
            # Check for spline variable existence (agent might name it differently, but instruction said 'income_over_20')
            if 'income_over_20' in content:
                score += 10
                feedback.append("Spline variable 'income_over_20' found in output.")
            else:
                feedback.append("Spline variable 'income_over_20' NOT found in output.")

            # Parse coefficients
            # We use a broad regex to capture the first number after the variable name
            coef_income_match = re.search(r'income\s+([+-]?\d+\.\d+)', content)
            coef_spline_match = re.search(r'income_over_20\s+([+-]?\d+\.\d+)', content)
            
            valid_coefs = False
            if coef_income_match and coef_spline_match:
                try:
                    agent_income = float(coef_income_match.group(1))
                    agent_spline = float(coef_spline_match.group(1))
                    
                    # Check accuracy (tolerance 1.0 for output formatting variations)
                    if math.isclose(agent_income, gt['income'], abs_tol=1.0):
                        score += 20
                        feedback.append(f"Income coefficient correct ({agent_income}).")
                    else:
                        feedback.append(f"Income coefficient incorrect. Expected ~{gt['income']:.2f}, got {agent_income}.")

                    if math.isclose(agent_spline, gt['income_over_20'], abs_tol=1.0):
                        score += 20
                        valid_coefs = True
                        feedback.append(f"Spline coefficient correct ({agent_spline}).")
                    else:
                        feedback.append(f"Spline coefficient incorrect. Expected ~{gt['income_over_20']:.2f}, got {agent_spline}.")
                except ValueError:
                    feedback.append("Could not parse coefficients from output.")
            else:
                feedback.append("Could not find coefficient values in regression output.")

        except Exception as e:
            feedback.append(f"Error analyzing regression file: {e}")
        finally:
            if os.path.exists(temp_reg.name):
                os.unlink(temp_reg.name)

    # 4. Check Slope Calculation Output
    slope_file_exists = metadata.get('slope_output_exists', False)
    if slope_file_exists:
        temp_slope = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/home/ga/Documents/gretl_output/high_income_slope.txt", temp_slope.name)
            with open(temp_slope.name, 'r') as f:
                slope_text = f.read().strip()
            
            # Try to parse a number
            match = re.search(r'([+-]?\d+\.?\d*)', slope_text)
            if match:
                agent_slope = float(match.group(1))
                if math.isclose(agent_slope, gt['high_income_slope'], abs_tol=0.5):
                    score += 40
                    feedback.append(f"High income slope calculation correct ({agent_slope}).")
                else:
                    feedback.append(f"High income slope incorrect. Expected ~{gt['high_income_slope']:.2f}, got {agent_slope}.")
            else:
                feedback.append("Could not find a valid number in slope output file.")
        except Exception as e:
            feedback.append(f"Error reading slope file: {e}")
        finally:
            if os.path.exists(temp_slope.name):
                os.unlink(temp_slope.name)
    else:
        feedback.append("High income slope output file not found.")

    # Final Evaluation
    # Max score: 10 (file exists) + 10 (var name) + 20 (income coef) + 20 (spline coef) + 40 (slope calc) = 100
    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }