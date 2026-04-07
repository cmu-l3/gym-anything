#!/usr/bin/env python3
import json
import os
import tempfile
import pandas as pd
import openpyxl
from openpyxl.formatting.rule import CellIsRule

def verify_fix_excel_sales_report(traj, env_info, task_info):
    """
    Verify the fix_excel_sales_report task.
    
    Criteria:
    1. Net Revenue Accuracy (30 pts): Returns are subtracted.
    2. Date Parsing (20 pts): DD/MM/YYYY handled correctly.
    3. Dynamic Formula (25 pts): Formula range matches data rows.
    4. Conditional Formatting (25 pts): >500 is Green.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Setup temp files
    tmp_xlsx = tempfile.mktemp(suffix='.xlsx')
    tmp_csv = tempfile.mktemp(suffix='.csv')
    tmp_json = tempfile.mktemp(suffix='.json')

    try:
        # Fetch files
        copy_from_env("/tmp/weekly_sales_report.xlsx", tmp_xlsx)
        copy_from_env("/tmp/transactions.csv", tmp_csv)
        copy_from_env("/tmp/task_result.json", tmp_json)
        
        # Read JSON result
        with open(tmp_json, 'r') as f:
            res_data = json.load(f)
            
        if not res_data.get('script_ran_successfully'):
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Agent's script failed to run or did not generate the output file."
            }
            
        # Load Data for Ground Truth
        # Note: In the task setup, dates are DD/MM/YYYY HH:MM
        df_truth = pd.read_csv(tmp_csv)
        # Fix date parsing for ground truth
        df_truth['InvoiceDate'] = pd.to_datetime(df_truth['InvoiceDate'], dayfirst=True)
        # Calculate expected metrics
        # Revenue = Quantity * UnitPrice (Quantity can be negative)
        df_truth['Revenue'] = df_truth['Quantity'] * df_truth['UnitPrice']
        expected_total_revenue = df_truth['Revenue'].sum()
        
        # Load Agent's Excel Output using pandas for data check
        # Use openpyxl for formula/formatting check
        wb = openpyxl.load_workbook(tmp_xlsx)
        ws = wb['Sales']
        
        # Read data via pandas from the excel to check values
        df_agent = pd.read_excel(tmp_xlsx)
        
        score = 0
        feedback = []

        # --- Criterion 1: Revenue Accuracy (30 pts) ---
        # The agent should calculate Revenue column. We check the sum.
        # Column names might vary slightly, but 'TotalRevenue' or 'Revenue' is expected.
        rev_col = None
        for col in df_agent.columns:
            if 'revenue' in col.lower():
                rev_col = col
                break
        
        if rev_col:
            agent_total = df_agent[rev_col].sum()
            # Allow small float diff
            if abs(agent_total - expected_total_revenue) < 1.0:
                score += 30
                feedback.append("Revenue calculation correct (Returns subtracted).")
            else:
                feedback.append(f"Revenue incorrect. Expected ~{expected_total_revenue:.2f}, got {agent_total:.2f}. Check if abs() was removed.")
        else:
            feedback.append("Revenue column not found in output.")

        # --- Criterion 2: Date Parsing (20 pts) ---
        # Check if InvoiceDate is datetime and matches ground truth
        # We pick a row with Day > 12 to verify DD/MM vs MM/DD
        # Find a row where Day > 12 in Ground Truth
        check_mask = df_truth['InvoiceDate'].dt.day > 12
        if check_mask.any():
            check_idx = check_mask.idxmax()
            expected_date = df_truth.loc[check_idx, 'InvoiceDate']
            
            # Agent date at this index
            if 'InvoiceDate' in df_agent.columns:
                agent_date = df_agent.loc[check_idx, 'InvoiceDate']
                # Pandas read_excel usually converts to timestamp
                if isinstance(agent_date, pd.Timestamp):
                    if agent_date.date() == expected_date.date():
                        score += 20
                        feedback.append("Date parsing correct.")
                    else:
                        feedback.append(f"Date mismatch. Expected {expected_date.date()}, got {agent_date.date()}. Format likely wrong.")
                else:
                    feedback.append("InvoiceDate column is not datetime format.")
            else:
                feedback.append("InvoiceDate column missing.")
        else:
            # Fallback if random data didn't generate >12th day (unlikely but safe)
            score += 20 
            feedback.append("Date parsing check skipped (no >12th day sample).")

        # --- Criterion 3: Dynamic Formula (25 pts) ---
        # Find the formula cell. It should be at max_row + 2 usually, or simply check the string content of cells
        # The data has ~150 rows. The bug had hardcoded 100.
        # We look for a cell starting with "=AVERAGE"
        formula_correct = False
        data_rows = len(df_truth)
        
        # Scan cells in the bottom area
        for row in ws.iter_rows(min_row=len(df_truth), max_col=10, max_row=len(df_truth)+5):
            for cell in row:
                if isinstance(cell.value, str) and str(cell.value).startswith("=AVERAGE"):
                    # Check if range covers data_rows
                    # Expected range example: G2:G152 (if 150 data rows + 1 header)
                    expected_end = str(data_rows + 1) # Excel row index
                    if expected_end in cell.value and "100" not in cell.value:
                        formula_correct = True
                        break
        
        if formula_correct:
            score += 25
            feedback.append("Dynamic formula logic detected.")
        else:
            feedback.append(f"Dynamic formula not found or still hardcoded (Expected to cover ~{data_rows} rows).")

        # --- Criterion 4: Conditional Formatting (25 pts) ---
        # Check conditional formatting rules
        # We look for a rule that highlights > 500
        cf_correct = False
        
        # ws.conditional_formatting is a collection of ConditionalFormatting objects
        for cf in ws.conditional_formatting:
            # Each cf has rules
            for rule in cf.rules:
                if isinstance(rule, CellIsRule):
                    # We want operator='greaterThan' and formula=['500']
                    if rule.operator == 'greaterThan' and '500' in rule.formula:
                        cf_correct = True
                        break
        
        if cf_correct:
            score += 25
            feedback.append("Conditional formatting rule correct (> 500).")
        else:
            feedback.append("Conditional formatting incorrect (Expected > 500).")

        return {
            "passed": score >= 75,
            "score": score,
            "feedback": " ".join(feedback)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        # Cleanup
        for f in [tmp_xlsx, tmp_csv, tmp_json]:
            if os.path.exists(f):
                os.unlink(f)

if __name__ == "__main__":
    # Test stub
    pass