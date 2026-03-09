#!/bin/bash
echo "=== Exporting building_market_segmentation result ==="

source /workspace/scripts/task_utils.sh
activate_venv

take_screenshot /tmp/building_segmentation_end.png

/opt/urbansim_env/bin/python3 << 'PYEOF'
import json, os, csv

task_start = int(open('/tmp/building_segmentation_start_ts').read().strip()) if os.path.exists('/tmp/building_segmentation_start_ts') else 0
gt = {}
if os.path.exists('/tmp/building_segmentation_gt.json'):
    with open('/tmp/building_segmentation_gt.json') as f:
        gt = json.load(f)

result = {
    "task_start": task_start,
    "gt": gt,
    "clusters_csv_exists": False,
    "clusters_csv_is_new": False,
    "clusters_csv_rows": 0,
    "clusters_has_building_id": False,
    "clusters_has_cluster_id": False,
    "clusters_has_price_per_sqft": False,
    "cluster_ids_found": [],
    "profiles_csv_exists": False,
    "profiles_csv_is_new": False,
    "profiles_csv_rows": 0,
    "profiles_has_cluster_id": False,
    "profiles_has_mean_price": False,
    "profiles_has_mean_age": False,
    "profiles_has_building_count": False,
    "price_ratio_max_min": None,
    "cluster_prices": [],
    "chart_exists": False,
    "chart_is_new": False,
    "chart_size_kb": 0,
    "notebook_executed_cells": 0
}

# --- building_clusters.csv ---
clusters_path = "/home/ga/urbansim_projects/output/building_clusters.csv"
if os.path.exists(clusters_path):
    result["clusters_csv_exists"] = True
    result["clusters_csv_is_new"] = int(os.path.getmtime(clusters_path)) > task_start
    try:
        with open(clusters_path) as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            cols = [c.lower().strip() for c in (reader.fieldnames or [])]
        result["clusters_csv_rows"] = len(rows)
        result["clusters_has_building_id"] = any('building_id' in c or c == 'building_id' for c in cols)
        result["clusters_has_cluster_id"] = any('cluster' in c for c in cols)
        result["clusters_has_price_per_sqft"] = any('price' in c and 'sqft' in c for c in cols)
        # Collect unique cluster IDs
        cl_col = next((c for c in (reader.fieldnames or []) if 'cluster' in c.lower()), None)
        if cl_col and rows:
            result["cluster_ids_found"] = list(set(r.get(cl_col, '') for r in rows if r.get(cl_col, '').strip()))
    except Exception as e:
        result["clusters_error"] = str(e)

# --- cluster_profiles.csv ---
profiles_path = "/home/ga/urbansim_projects/output/cluster_profiles.csv"
if os.path.exists(profiles_path):
    result["profiles_csv_exists"] = True
    result["profiles_csv_is_new"] = int(os.path.getmtime(profiles_path)) > task_start
    try:
        with open(profiles_path) as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            cols = [c.lower().strip() for c in (reader.fieldnames or [])]
        result["profiles_csv_rows"] = len(rows)
        result["profiles_has_cluster_id"] = any('cluster' in c for c in cols)
        result["profiles_has_mean_price"] = any('price' in c for c in cols)
        result["profiles_has_mean_age"] = any('age' in c or 'year' in c for c in cols)
        result["profiles_has_building_count"] = any('count' in c or 'n_' in c or '_n' in c for c in cols)

        # Compute price ratio between highest and lowest cluster
        price_col = next((c for c in (reader.fieldnames or []) if 'price' in c.lower()), None)
        if price_col and rows:
            try:
                prices = [float(r[price_col]) for r in rows if r.get(price_col, '').strip()]
                result["cluster_prices"] = prices
                if len(prices) >= 2:
                    prices_sorted = sorted(prices)
                    if prices_sorted[0] > 0:
                        result["price_ratio_max_min"] = prices_sorted[-1] / prices_sorted[0]
            except (ValueError, ZeroDivisionError):
                pass
    except Exception as e:
        result["profiles_error"] = str(e)

# --- chart ---
chart_path = "/home/ga/urbansim_projects/output/market_segmentation_chart.png"
if os.path.exists(chart_path):
    result["chart_exists"] = True
    result["chart_is_new"] = int(os.path.getmtime(chart_path)) > task_start
    result["chart_size_kb"] = os.path.getsize(chart_path) / 1024

# --- notebook ---
nb_path = "/home/ga/urbansim_projects/notebooks/market_segmentation.ipynb"
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

with open('/tmp/building_segmentation_result.json', 'w') as f:
    json.dump(result, f, indent=2, default=str)
print("Result written to /tmp/building_segmentation_result.json")
PYEOF

chmod 666 /tmp/building_segmentation_result.json 2>/dev/null || true
cat /tmp/building_segmentation_result.json
echo "=== Export complete ==="
