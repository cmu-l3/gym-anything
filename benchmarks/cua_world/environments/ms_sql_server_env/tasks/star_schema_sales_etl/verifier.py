"""
Verifier for star_schema_sales_etl task.

Occupation: Data Warehouse Engineer (SOC 15-1252.00)
Context: Build a star schema data warehouse from AdventureWorks2022 OLTP
         with DimDate, DimProduct, DimCustomer, FactSales, and a stored
         procedure to load everything. Revenue must reconcile within $0.01.
"""
import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70


def verify_star_schema_sales_etl(traj, env_info, task_info):
    """
    Score the star_schema_sales_etl task.

    Expected objects in AdventureWorks2022:
    - DW schema
    - DW.DimDate table
    - DW.DimProduct table (with surrogate key)
    - DW.DimCustomer table (with surrogate key)
    - DW.FactSales table
    - DW.usp_LoadStarSchema stored procedure
    - CSV export at /home/ga/Documents/exports/dw_revenue_summary.csv
    """
    copy_from_env = env_info.get("copy_from_env")

    # ── Copy result JSON from VM ─────────────────────────────────────────────
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/star_schema_result.json", tmp.name)
    except Exception as e:
        os.unlink(tmp.name)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"No result file found. export_result.sh may not have run. Error: {e}",
            "subscores": {},
        }

    try:
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        os.unlink(tmp.name)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not parse result JSON: {e}",
            "subscores": {},
        }
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    feedback_parts = []
    subscores = {}

    def g(key, default=0):
        return result.get(key, default)

    # ── GATE: Wrong-target detection ─────────────────────────────────────────
    schema_exists = g("schema_exists", False)
    dimdate_exists = g("dimdate_exists", False)
    fact_exists = g("fact_exists", False)

    if not schema_exists and not dimdate_exists and not fact_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "GATE FAIL: No DW schema or tables found in AdventureWorks2022. "
                "The agent may have worked on the wrong database or created no objects."
            ),
            "subscores": {"gate": 0},
        }

    # ── Criterion 1: DW Schema (3 pts) ───────────────────────────────────────
    if schema_exists:
        score += 3
        subscores["schema"] = 3
        feedback_parts.append("PASS: DW schema exists.")
    else:
        subscores["schema"] = 0
        feedback_parts.append("FAIL: DW schema not found.")

    # ── Criterion 2: DimDate (15 pts) ────────────────────────────────────────
    dimdate_score = 0

    if dimdate_exists:
        dimdate_score += 2
        feedback_parts.append("PASS: DW.DimDate table exists.")

        rows = g("dimdate_rows")
        if 1826 <= rows <= 1827:
            dimdate_score += 3
            feedback_parts.append(f"PASS: DimDate has {rows} rows (correct).")
        elif rows > 1500:
            dimdate_score += 1
            feedback_parts.append(f"PARTIAL: DimDate has {rows} rows (expected ~1826).")
        else:
            feedback_parts.append(f"FAIL: DimDate has {rows} rows (expected ~1826).")

        fy = g("dimdate_fy_test")
        if fy == 2014:
            dimdate_score += 5
            feedback_parts.append("PASS: FiscalYear for 2013-07-15 = 2014 (correct).")
        else:
            feedback_parts.append(f"FAIL: FiscalYear for 2013-07-15 = {fy} (expected 2014).")

        fq = g("dimdate_fq_test")
        if fq == 2:
            dimdate_score += 3
            feedback_parts.append("PASS: FiscalQuarter for 2013-10-15 = Q2 (correct).")
        else:
            feedback_parts.append(f"FAIL: FiscalQuarter for 2013-10-15 = {fq} (expected 2).")

        wk = g("dimdate_weekend")
        if wk == 1:
            dimdate_score += 2
            feedback_parts.append("PASS: IsWeekend for 2013-01-05 (Saturday) = 1 (correct).")
        elif wk != -1:
            feedback_parts.append(f"FAIL: IsWeekend for 2013-01-05 (Saturday) = {wk} (expected 1).")
    else:
        feedback_parts.append("FAIL: DW.DimDate table not found.")

    score += dimdate_score
    subscores["dimdate"] = dimdate_score

    # ── Criterion 3: DimProduct (12 pts) ─────────────────────────────────────
    dimprod_score = 0

    if g("dimprod_exists", False):
        dimprod_score += 2
        feedback_parts.append("PASS: DW.DimProduct table exists.")

        ref_p = g("ref_products", 504)
        dp = g("dimprod_rows")
        if dp == ref_p:
            dimprod_score += 3
            feedback_parts.append(f"PASS: DimProduct has {dp} rows (matches source).")
        elif dp > 0 and abs(dp - ref_p) <= 5:
            dimprod_score += 1
            feedback_parts.append(f"PARTIAL: DimProduct has {dp} rows (expected {ref_p}).")
        else:
            feedback_parts.append(f"FAIL: DimProduct has {dp} rows (expected {ref_p}).")

        null_sub = g("ref_null_subcat", 209)
        uncat = g("dimprod_uncategorized")
        if null_sub > 0 and uncat >= null_sub - 5:
            dimprod_score += 3
            feedback_parts.append(f"PASS: {uncat} products mapped to 'Uncategorized'.")
        elif uncat > 0:
            dimprod_score += 1
            feedback_parts.append(f"PARTIAL: Only {uncat} products mapped to 'Uncategorized' (expected ~{null_sub}).")
        else:
            feedback_parts.append("FAIL: No products mapped to 'Uncategorized' for NULL categories.")

        if g("dimprod_has_sk", False):
            dimprod_score += 2
            feedback_parts.append("PASS: DimProduct has ProductSK surrogate key.")
        else:
            feedback_parts.append("FAIL: DimProduct missing ProductSK surrogate key.")

        gen = g("dimprod_general")
        if gen > 0:
            dimprod_score += 2
            feedback_parts.append(f"PASS: {gen} products mapped to 'General' subcategory.")
        else:
            feedback_parts.append("FAIL: No products mapped to 'General' for NULL subcategories.")
    else:
        feedback_parts.append("FAIL: DW.DimProduct table not found.")

    score += dimprod_score
    subscores["dimproduct"] = dimprod_score

    # ── Criterion 4: DimCustomer (10 pts) ────────────────────────────────────
    dimcust_score = 0

    if g("dimcust_exists", False):
        dimcust_score += 2
        feedback_parts.append("PASS: DW.DimCustomer table exists.")

        ref_c = g("ref_customers")
        dc = g("dimcust_rows")
        if dc == ref_c:
            dimcust_score += 2
            feedback_parts.append(f"PASS: DimCustomer has {dc} rows (matches source).")
        elif dc > 0 and abs(dc - ref_c) <= 10:
            dimcust_score += 1
            feedback_parts.append(f"PARTIAL: DimCustomer has {dc} rows (expected {ref_c}).")
        else:
            feedback_parts.append(f"FAIL: DimCustomer has {dc} rows (expected {ref_c}).")

        stores = g("dimcust_stores")
        indiv = g("dimcust_individuals")
        if stores > 0 and indiv > 0:
            dimcust_score += 2
            feedback_parts.append(f"PASS: Both customer types present ({indiv} Individual, {stores} Store).")
        else:
            feedback_parts.append(f"FAIL: Missing customer types (Individual={indiv}, Store={stores}).")

        prefix = g("dimcust_store_prefix")
        if prefix > 0:
            dimcust_score += 2
            feedback_parts.append(f"PASS: {prefix} store customers have 'Store:' name prefix.")
        else:
            feedback_parts.append("FAIL: No store customers with 'Store:' name prefix.")

        if g("dimcust_has_sk", False):
            dimcust_score += 2
            feedback_parts.append("PASS: DimCustomer has CustomerSK surrogate key.")
        else:
            feedback_parts.append("FAIL: DimCustomer missing CustomerSK surrogate key.")
    else:
        feedback_parts.append("FAIL: DW.DimCustomer table not found.")

    score += dimcust_score
    subscores["dimcustomer"] = dimcust_score

    # ── Criterion 5: FactSales existence + volume (8 pts) ────────────────────
    fact_score = 0

    if fact_exists:
        fact_score += 2
        feedback_parts.append("PASS: DW.FactSales table exists.")

        ref_l = g("ref_lineitems", 121317)
        fr = g("fact_rows")
        if fr == ref_l:
            fact_score += 4
            feedback_parts.append(f"PASS: FactSales has {fr} rows (matches source).")
        elif fr > 0 and abs(fr - ref_l) / max(ref_l, 1) < 0.01:
            fact_score += 2
            feedback_parts.append(f"PARTIAL: FactSales has {fr} rows (expected {ref_l}).")
        elif fr > 0:
            fact_score += 1
            feedback_parts.append(f"PARTIAL: FactSales has {fr} rows (expected {ref_l}).")
        else:
            feedback_parts.append("FAIL: FactSales is empty.")

        cols = g("fact_cols")
        if cols >= 10:
            fact_score += 2
            feedback_parts.append(f"PASS: FactSales has {cols} columns.")
        else:
            feedback_parts.append(f"FAIL: FactSales has only {cols} columns (expected 10+).")
    else:
        feedback_parts.append("FAIL: DW.FactSales table not found.")

    score += fact_score
    subscores["factsales"] = fact_score

    # ── Criterion 6: Revenue reconciliation (15 pts — GATE) ──────────────────
    reconciliation_passed = False
    recon_score = 0

    try:
        diff = float(g("linetotal_diff", 999999))
    except (ValueError, TypeError):
        diff = 999999

    if diff <= 0.01:
        recon_score = 15
        reconciliation_passed = True
        feedback_parts.append(f"PASS: LineTotal reconciliation exact (diff=${diff:.2f}).")
    elif diff <= 1.0:
        recon_score = 10
        reconciliation_passed = True
        feedback_parts.append(f"PARTIAL: LineTotal diff ${diff:.2f} (within $1).")
    elif diff <= 100.0:
        recon_score = 5
        feedback_parts.append(f"PARTIAL: LineTotal diff ${diff:.2f} (within $100).")
    else:
        feedback_parts.append(f"FAIL: Revenue reconciliation failed (diff=${diff}).")

    score += recon_score
    subscores["reconciliation"] = recon_score

    # ── Criterion 7: Surrogate key integrity (10 pts) ────────────────────────
    sk_score = 0
    op = g("orphan_prod", -1)
    oc = g("orphan_cust", -1)
    od = g("orphan_odate", -1)
    os_ = g("orphan_sdate", -1)

    if op == 0 and oc == 0 and od == 0 and os_ == 0:
        sk_score = 10
        feedback_parts.append("PASS: No orphaned surrogate keys in FactSales.")
    elif op == 0 and oc == 0 and od == 0:
        sk_score = 8
        feedback_parts.append(f"PARTIAL: ShipDateKey has {os_} orphans (other keys clean).")
    elif op == 0 and oc == 0:
        sk_score = 5
        feedback_parts.append(f"PARTIAL: DateKey orphans (order={od}, ship={os_}), product/customer clean.")
    elif op >= 0:
        sk_score = 2
        feedback_parts.append(f"FAIL: Orphaned keys: product={op}, customer={oc}, orderdate={od}, shipdate={os_}.")
    else:
        feedback_parts.append("FAIL: Could not check surrogate key integrity.")

    score += sk_score
    subscores["surrogate_keys"] = sk_score

    # ── Criterion 8: Tax/freight allocation (7 pts) ──────────────────────────
    alloc_score = 0
    try:
        td = float(g("tax_diff", 999999))
        fd = float(g("freight_diff", 999999))
    except (ValueError, TypeError):
        td = fd = 999999

    if td <= 1.0 and fd <= 1.0:
        alloc_score = 7
        feedback_parts.append(f"PASS: Tax/freight allocation reconciles (tax_diff=${td:.2f}, freight_diff=${fd:.2f}).")
    elif td <= 10.0 and fd <= 10.0:
        alloc_score = 4
        feedback_parts.append(f"PARTIAL: Tax/freight close (tax_diff=${td:.2f}, freight_diff=${fd:.2f}).")
    elif td <= 100.0 and fd <= 100.0:
        alloc_score = 2
        feedback_parts.append(f"PARTIAL: Tax/freight off (tax_diff=${td:.2f}, freight_diff=${fd:.2f}).")
    else:
        feedback_parts.append(f"FAIL: Tax/freight allocation far off (tax_diff={td}, freight_diff={fd}).")

    score += alloc_score
    subscores["allocation"] = alloc_score

    # ── Criterion 9: Stored procedure exists (5 pts) ────────────────────────
    if g("proc_exists", False):
        score += 5
        subscores["stored_proc"] = 5
        feedback_parts.append("PASS: DW.usp_LoadStarSchema procedure exists.")
    else:
        subscores["stored_proc"] = 0
        feedback_parts.append("FAIL: DW.usp_LoadStarSchema procedure not found.")

    # ── Criterion 10: CSV export (10 pts) ────────────────────────────────────
    csv_score = 0
    csv_exists = g("csv_exists", False)
    csv_rows = g("csv_rows", 0)
    csv_created = g("csv_created_during_task", False)

    if csv_exists:
        csv_score += 3
        feedback_parts.append("PASS: CSV file exists.")
    else:
        feedback_parts.append("FAIL: CSV not found at /home/ga/Documents/exports/dw_revenue_summary.csv.")

    if csv_exists and csv_created:
        csv_score += 2
        feedback_parts.append("PASS: CSV created during task session.")
    elif csv_exists:
        feedback_parts.append("FAIL: CSV exists but not created during this session.")

    if csv_exists and csv_rows >= 5:
        csv_score += 5
        feedback_parts.append(f"PASS: CSV has {csv_rows} rows (header + data).")
    elif csv_exists and csv_rows >= 2:
        csv_score += 3
        feedback_parts.append(f"PARTIAL: CSV has only {csv_rows} rows.")
    elif csv_exists:
        feedback_parts.append("FAIL: CSV is empty or has only a header.")

    score += csv_score
    subscores["csv_export"] = csv_score

    # ── Final verdict ────────────────────────────────────────────────────────
    # Total possible: 3 + 15 + 12 + 10 + 8 + 15 + 10 + 7 + 5 + 10 = 95
    passed = score >= PASS_THRESHOLD and reconciliation_passed
    feedback = " | ".join(feedback_parts)

    if passed:
        feedback = f"PASSED ({score}/95): " + feedback
    else:
        feedback = f"FAILED ({score}/95, need {PASS_THRESHOLD} + reconciliation): " + feedback

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "subscores": subscores,
    }
