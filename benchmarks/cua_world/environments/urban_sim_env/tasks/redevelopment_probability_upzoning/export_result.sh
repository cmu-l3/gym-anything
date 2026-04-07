#!/bin/bash
echo "=== Exporting redevelopment_probability_upzoning result ==="

source /workspace/scripts/task_utils.sh
activate_venv

take_screenshot /tmp/redev_upzoning_end.png

/opt/urbansim_env/bin/python3 << 'PYEOF'
import json, os, csv

task_start = int(open('/tmp/redev_upzoning_start_ts').read().strip()) if os.path.exists('/tmp/redev_upzoning_start_ts') else 0
gt = {}
if os.path.exists('/tmp/redev_upzoning_gt.json'):
    with open('/tmp/redev_upzoning_gt.json') as f:
        gt = json.load(f)

result = {
    "task_start": task_start,
    "gt": gt,
    # model_metrics.json
    "metrics_json_exists": False,
    "metrics_json_is_new": False,
    "metrics_has_auc": False,
    "metrics_has_n_train": False,
    "metrics_has_n_test": False,
    "metrics_has_coefficients": False,
    "metrics_has_intercept": False,
    "auc_score": None,
    "n_train": None,
    "n_test": None,
    "n_coefficients": 0,
    "coefficient_names": [],
    "intercept_value": None,
    # zone_development_impact.csv
    "csv_exists": False,
    "csv_is_new": False,
    "csv_row_count": 0,
    "csv_columns": [],
    "has_zone_id": False,
    "has_n_buildings": False,
    "has_expected_baseline": False,
    "has_expected_scenario": False,
    "has_development_uplift": False,
    "has_zone_median_income": False,
    "uplift_positive_count": 0,
    "uplift_negative_count": 0,
    "uplift_zero_count": 0,
    # chart
    "chart_exists": False,
    "chart_is_new": False,
    "chart_size_kb": 0,
    # notebook
    "notebook_executed_cells": 0
}

# --- model_metrics.json ---
metrics_path = "/home/ga/urbansim_projects/output/model_metrics.json"
if os.path.exists(metrics_path):
    result["metrics_json_exists"] = True
    result["metrics_json_is_new"] = int(os.path.getmtime(metrics_path)) > task_start
    try:
        with open(metrics_path) as f:
            metrics = json.load(f)
        result["metrics_has_auc"] = "auc_score" in metrics
        result["metrics_has_n_train"] = "n_train" in metrics
        result["metrics_has_n_test"] = "n_test" in metrics
        result["metrics_has_coefficients"] = "coefficients" in metrics and isinstance(metrics.get("coefficients"), dict)
        result["metrics_has_intercept"] = "intercept" in metrics

        if result["metrics_has_auc"]:
            try:
                result["auc_score"] = float(metrics["auc_score"])
            except (ValueError, TypeError):
                pass
        if result["metrics_has_n_train"]:
            try:
                result["n_train"] = int(metrics["n_train"])
            except (ValueError, TypeError):
                pass
        if result["metrics_has_n_test"]:
            try:
                result["n_test"] = int(metrics["n_test"])
            except (ValueError, TypeError):
                pass
        if result["metrics_has_coefficients"]:
            coeffs = metrics["coefficients"]
            result["n_coefficients"] = len(coeffs)
            result["coefficient_names"] = list(coeffs.keys())
        if result["metrics_has_intercept"]:
            try:
                result["intercept_value"] = float(metrics["intercept"])
            except (ValueError, TypeError):
                pass
    except Exception as e:
        result["metrics_error"] = str(e)

# --- zone_development_impact.csv ---
csv_path = "/home/ga/urbansim_projects/output/zone_development_impact.csv"
if os.path.exists(csv_path):
    result["csv_exists"] = True
    result["csv_is_new"] = int(os.path.getmtime(csv_path)) > task_start
    try:
        with open(csv_path) as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            cols = [c.lower().strip() for c in (reader.fieldnames or [])]
        result["csv_row_count"] = len(rows)
        result["csv_columns"] = cols
        result["has_zone_id"] = any('zone_id' in c for c in cols)
        result["has_n_buildings"] = any('n_buildings' in c or 'n_build' in c or 'num_build' in c or 'building_count' in c for c in cols)
        result["has_expected_baseline"] = any('baseline' in c for c in cols)
        result["has_expected_scenario"] = any('scenario' in c for c in cols)
        result["has_development_uplift"] = any('uplift' in c for c in cols)
        result["has_zone_median_income"] = any('median_income' in c or 'zone_median' in c for c in cols)

        # Analyze uplift direction
        uplift_col = next((c for c in (reader.fieldnames or []) if 'uplift' in c.lower()), None)
        if uplift_col and rows:
            try:
                for r in rows:
                    val = float(r.get(uplift_col, 0))
                    if val > 0.001:
                        result["uplift_positive_count"] += 1
                    elif val < -0.001:
                        result["uplift_negative_count"] += 1
                    else:
                        result["uplift_zero_count"] += 1
            except (ValueError, KeyError):
                pass
    except Exception as e:
        result["csv_error"] = str(e)

# --- chart ---
chart_path = "/home/ga/urbansim_projects/output/scenario_comparison_chart.png"
if os.path.exists(chart_path):
    result["chart_exists"] = True
    result["chart_is_new"] = int(os.path.getmtime(chart_path)) > task_start
    result["chart_size_kb"] = os.path.getsize(chart_path) / 1024

# --- notebook ---
nb_path = "/home/ga/urbansim_projects/notebooks/redevelopment_model.ipynb"
if os.path.exists(nb_path):
    try:
        with open(nb_path) as f:
            nb = json.load(f)
        code_cells = [c for c in nb.get('cells', []) if c.get('cell_type') == 'code']
        result["notebook_executed_cells"] = sum(
            1 for c in code_cells if c.get('execution_count') is not None
        )
    except Exception:
        pass

with open('/tmp/redev_upzoning_result.json', 'w') as f:
    json.dump(result, f, indent=2, default=str)
print("Result written to /tmp/redev_upzoning_result.json")
PYEOF

chmod 666 /tmp/redev_upzoning_result.json 2>/dev/null || true
cat /tmp/redev_upzoning_result.json
echo "=== Export complete ==="
