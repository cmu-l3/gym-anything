import os, json, subprocess, csv, io

results = {}

# Check 1: Copper running
try:
    out = subprocess.check_output(["tasklist", "/FI", "IMAGENAME eq copper.exe"], text=True)
    results["check1_copper_running"] = "copper.exe" in out.lower()
except:
    results["check1_copper_running"] = False

# Check 2: Data files exist and valid
desktop = "C:\\Users\\Docker\\Desktop"
for fn in ["store_inventory.csv", "physical_count.csv"]:
    fp = os.path.join(desktop, fn)
    info = {"exists": os.path.exists(fp)}
    if info["exists"]:
        info["size"] = os.path.getsize(fp)
        with open(fp, encoding="utf-8-sig") as f:
            raw = f.read()
        lines = raw.strip().split("\n")
        info["line_count"] = len(lines)
        info["header"] = lines[0].strip()
        reader = csv.DictReader(io.StringIO(raw))
        rows = list(reader)
        info["row_count"] = len(rows)
        info["columns"] = list(rows[0].keys()) if rows else []
        if fn == "store_inventory.csv":
            info["sample_skus"] = [r.get("SKU", "") for r in rows[:5]]
            info["categories"] = list(set(r.get("Category", "") for r in rows))
        elif fn == "physical_count.csv":
            info["sample_skus"] = [r.get("SKU", "") for r in rows[:5]]
    results["check2_" + fn.replace(".", "_")] = info

# Check 3: Desktop writable
try:
    test_path = os.path.join(desktop, "_writetest_qir.tmp")
    with open(test_path, "w") as f:
        f.write("test")
    results["check3_desktop_writable"] = os.path.exists(test_path)
    os.remove(test_path)
except Exception as e:
    results["check3_desktop_writable"] = str(e)

# Check 4: Stale outputs cleared
results["check4_stale_final_inventory"] = os.path.exists(os.path.join(desktop, "final_inventory.csv"))
results["check4_stale_quarterly_close"] = os.path.exists(os.path.join(desktop, "quarterly_close.txt"))
results["check4_stale_result_json"] = os.path.exists("C:\\Users\\Docker\\quarterly_reconciliation_result.json")

# Check 5: Timestamp recorded
ts_path = "C:\\Users\\Docker\\task_start_ts_quarterly_reconciliation.txt"
results["check5_timestamp_exists"] = os.path.exists(ts_path)
if results["check5_timestamp_exists"]:
    with open(ts_path) as f:
        results["check5_timestamp_value"] = f.read().strip()

# Check 6: Key data elements
store_inv_path = os.path.join(desktop, "store_inventory.csv")
if os.path.exists(store_inv_path):
    with open(store_inv_path, encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        items_by_sku = {r["SKU"]: r for r in reader}
    results["check6_airpods_exists"] = "ELE-0086" in items_by_sku
    if results["check6_airpods_exists"]:
        results["check6_airpods_price"] = items_by_sku["ELE-0086"]["Price"]
        results["check6_airpods_name"] = items_by_sku["ELE-0086"]["Item Name"]
    results["check6_zipped_jacket_exists"] = "CLO-0011" in items_by_sku
    if results["check6_zipped_jacket_exists"]:
        results["check6_zipped_jacket_price"] = items_by_sku["CLO-0011"]["Price"]
    results["check6_black_leather_bag_exists"] = "CLO-0010" in items_by_sku
    if results["check6_black_leather_bag_exists"]:
        results["check6_black_leather_bag_price"] = items_by_sku["CLO-0010"]["Price"]
    results["check6_total_items"] = len(items_by_sku)

# Check 9: File writing for txt/csv
try:
    test_csv = os.path.join(desktop, "_csvtest_qir.csv")
    with open(test_csv, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["col1", "col2"])
        w.writerow(["val1", "val2"])
    results["check9_csv_write_ok"] = os.path.exists(test_csv) and os.path.getsize(test_csv) > 0
    os.remove(test_csv)
except Exception as e:
    results["check9_csv_write_ok"] = str(e)

# Copper data directory
copper_data = "C:\\ProgramData\\NCH Software\\Copper"
results["copper_data_dir_exists"] = os.path.exists(copper_data)
if results["copper_data_dir_exists"]:
    try:
        results["copper_data_contents"] = os.listdir(copper_data)
    except:
        results["copper_data_contents"] = "permission denied"

# Write results
out_path = "C:\\Users\\Docker\\Desktop\\checks_result_qir.json"
with open(out_path, "w") as f:
    json.dump(results, f, indent=2)
