#!/usr/bin/env python3
"""
Verifier for the optimize_data_pipeline task.

Checks whether the agent identified and fixed 5 performance anti-patterns
in the Python pandas data pipeline using AST analysis, and verifies that
the functional output remains identical to the ground truth.

Each of the 5 bottlenecks is worth 15 points (10 for AST fix, 5 for output correctness).
General execution and anti-gaming criteria make up the remaining 25 points.
Total 100 points. Pass threshold: 60.
"""

import os
import json
import ast
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ──────────────────────────────────────────────────────────
# AST Visitors for Anti-Pattern Detection
# ──────────────────────────────────────────────────────────

class ReadCsvInLoopVisitor(ast.NodeVisitor):
    def __init__(self):
        self.in_loop = False
        self.found = False

    def visit_For(self, node):
        old = self.in_loop
        self.in_loop = True
        self.generic_visit(node)
        self.in_loop = old

    def visit_While(self, node):
        self.visit_For(node)

    def visit_Call(self, node):
        if self.in_loop:
            if isinstance(node.func, ast.Attribute) and node.func.attr == 'read_csv':
                self.found = True
            elif isinstance(node.func, ast.Name) and node.func.id == 'read_csv':
                self.found = True
        self.generic_visit(node)


class IterrowsVisitor(ast.NodeVisitor):
    def __init__(self):
        self.found = False

    def visit_Attribute(self, node):
        if node.attr == 'iterrows':
            self.found = True
        self.generic_visit(node)


class NestedLoopVisitor(ast.NodeVisitor):
    def __init__(self):
        self.loop_depth = 0
        self.found_nested = False

    def visit_For(self, node):
        self.loop_depth += 1
        if self.loop_depth >= 2:
            self.found_nested = True
        self.generic_visit(node)
        self.loop_depth -= 1


class PlusEqualsVisitor(ast.NodeVisitor):
    def __init__(self):
        self.in_loop = False
        self.found = False

    def visit_For(self, node):
        old = self.in_loop
        self.in_loop = True
        self.generic_visit(node)
        self.in_loop = old

    def visit_While(self, node):
        self.visit_For(node)

    def visit_AugAssign(self, node):
        if self.in_loop and isinstance(node.op, ast.Add):
            self.found = True
        self.generic_visit(node)


class LoopExistenceVisitor(ast.NodeVisitor):
    def __init__(self):
        self.found = False

    def visit_For(self, node):
        self.found = True
        self.generic_visit(node)

    def visit_While(self, node):
        self.found = True
        self.generic_visit(node)


# ──────────────────────────────────────────────────────────
# Verification Logic
# ──────────────────────────────────────────────────────────

def compare_csv_strings(output_str, gt_str, tolerance=0.01):
    """Compare two CSV strings loosely (ignoring line endings and minor float diffs)."""
    if not output_str or not gt_str:
        return False
        
    out_lines = [l.strip() for l in output_str.strip().split('\n') if l.strip()]
    gt_lines = [l.strip() for l in gt_str.strip().split('\n') if l.strip()]
    
    if len(out_lines) != len(gt_lines):
        return False
        
    for l1, l2 in zip(out_lines, gt_lines):
        if l1 == l2:
            continue
            
        # Try to compare as lists of floats/strings if exact match fails
        p1 = l1.split(',')
        p2 = l2.split(',')
        if len(p1) != len(p2):
            return False
            
        for v1, v2 in zip(p1, p2):
            if v1 == v2:
                continue
            try:
                if abs(float(v1) - float(v2)) > tolerance:
                    return False
            except ValueError:
                return False
                
    return True


def verify_pipeline_optimization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/pipeline_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    source_code = data.get("source_code", {})
    modified_files = data.get("file_modified_after_start", {})
    outputs = data.get("outputs", {})
    ground_truth = data.get("ground_truth", {})
    
    score = 0
    feedback_parts = []
    
    # ── B1: data_loader.py (No repeated CSV reads in loop)
    code = source_code.get("pipeline/data_loader.py", "")
    try:
        tree = ast.parse(code)
        visitor = ReadCsvInLoopVisitor()
        visitor.visit(tree)
        if not visitor.found:
            score += 10
            feedback_parts.append("[+] B1 (AST): No I/O in loop (10/10)")
        else:
            feedback_parts.append("[-] B1 (AST): read_csv found inside loop (0/10)")
    except Exception as e:
        feedback_parts.append(f"[-] B1 (AST): Failed to parse data_loader.py ({e})")

    if compare_csv_strings(outputs.get("department_summary.csv"), ground_truth.get("department_summary.csv")):
        score += 5
        feedback_parts.append("[+] B1 (Output): department_summary.csv matches ground truth (5/5)")
    else:
        feedback_parts.append("[-] B1 (Output): department_summary.csv mismatch or missing (0/5)")


    # ── B2: sales_aggregator.py (No iterrows usage)
    code = source_code.get("pipeline/sales_aggregator.py", "")
    try:
        tree = ast.parse(code)
        visitor = IterrowsVisitor()
        visitor.visit(tree)
        if not visitor.found:
            score += 10
            feedback_parts.append("[+] B2 (AST): iterrows removed (10/10)")
        else:
            feedback_parts.append("[-] B2 (AST): iterrows still used (0/10)")
    except Exception as e:
        feedback_parts.append(f"[-] B2 (AST): Failed to parse sales_aggregator.py ({e})")

    # Output correctly matches for aggregation (covered by B1 output check usually, but we give points here for logic)
    # Re-using the same output file check to award points for B2 correctness
    if compare_csv_strings(outputs.get("department_summary.csv"), ground_truth.get("department_summary.csv")):
        score += 5
        feedback_parts.append("[+] B2 (Output): Aggregation output is correct (5/5)")
    else:
        feedback_parts.append("[-] B2 (Output): Aggregation output mismatch (0/5)")


    # ── B3: invoice_matcher.py (No nested loops)
    code = source_code.get("pipeline/invoice_matcher.py", "")
    try:
        tree = ast.parse(code)
        visitor = NestedLoopVisitor()
        visitor.visit(tree)
        if not visitor.found_nested:
            score += 10
            feedback_parts.append("[+] B3 (AST): No O(n^2) nested loops found (10/10)")
        else:
            feedback_parts.append("[-] B3 (AST): Nested loops still present (0/10)")
    except Exception as e:
        feedback_parts.append(f"[-] B3 (AST): Failed to parse invoice_matcher.py ({e})")

    # Order-independent CSV check for matched invoices
    out_matched = outputs.get("matched_invoices.csv", "")
    gt_matched = ground_truth.get("matched_invoices.csv", "")
    if out_matched and gt_matched:
        out_lines = sorted([l.strip() for l in out_matched.strip().split('\n') if l.strip()])
        gt_lines = sorted([l.strip() for l in gt_matched.strip().split('\n') if l.strip()])
        if out_lines == gt_lines:
            score += 5
            feedback_parts.append("[+] B3 (Output): matched_invoices.csv matches (5/5)")
        else:
            feedback_parts.append("[-] B3 (Output): matched_invoices.csv mismatch (0/5)")
    else:
        feedback_parts.append("[-] B3 (Output): matched_invoices.csv missing (0/5)")


    # ── B4: report_builder.py (No string += in loop)
    code = source_code.get("pipeline/report_builder.py", "")
    try:
        tree = ast.parse(code)
        visitor = PlusEqualsVisitor()
        visitor.visit(tree)
        if not visitor.found:
            score += 10
            feedback_parts.append("[+] B4 (AST): String += inside loop removed (10/10)")
        else:
            feedback_parts.append("[-] B4 (AST): String += still used in loop (0/10)")
    except Exception as e:
        feedback_parts.append(f"[-] B4 (AST): Failed to parse report_builder.py ({e})")

    out_report = outputs.get("sales_report.txt", "")
    gt_report = ground_truth.get("sales_report.txt", "")
    if out_report and gt_report and out_report.strip() == gt_report.strip():
        score += 5
        feedback_parts.append("[+] B4 (Output): sales_report.txt matches perfectly (5/5)")
    else:
        feedback_parts.append("[-] B4 (Output): sales_report.txt mismatch or missing (0/5)")


    # ── B5: trend_calculator.py (No manual loop for cumsum)
    code = source_code.get("pipeline/trend_calculator.py", "")
    try:
        tree = ast.parse(code)
        visitor = LoopExistenceVisitor()
        visitor.visit(tree)
        if not visitor.found:
            score += 10
            feedback_parts.append("[+] B5 (AST): Manual iteration loop removed (10/10)")
        else:
            feedback_parts.append("[-] B5 (AST): Loop still exists in trend calculator (0/10)")
    except Exception as e:
        feedback_parts.append(f"[-] B5 (AST): Failed to parse trend_calculator.py ({e})")

    if compare_csv_strings(outputs.get("trends.csv"), ground_truth.get("trends.csv")):
        score += 5
        feedback_parts.append("[+] B5 (Output): trends.csv matches ground truth (5/5)")
    else:
        feedback_parts.append("[-] B5 (Output): trends.csv mismatch or missing (0/5)")


    # ── General execution and anti-gaming
    all_modified = all(modified_files.values())
    if all_modified:
        score += 10
        feedback_parts.append("[+] Anti-Gaming: All 5 files modified during task (10/10)")
    else:
        feedback_parts.append("[-] Anti-Gaming: Not all files were modified (0/10)")

    run_log = data.get("pipeline_run_log", "")
    if "Pipeline finished successfully" in run_log:
        score += 15
        feedback_parts.append("[+] Pipeline Execution: Script ran successfully without errors (15/15)")
    else:
        feedback_parts.append("[-] Pipeline Execution: Script failed or timed out (0/15)")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }