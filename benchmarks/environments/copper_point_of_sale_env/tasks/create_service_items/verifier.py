#!/usr/bin/env python3
import json
import os
import sqlite3
import tempfile
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_service_items(traj, env_info, task_info):
    """
    Verify that 3 service items were created correctly in Copper POS.
    Checks: Existence, Price, and Stock Management flag (must be disabled/service).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata
    expected_items = task_info.get('metadata', {}).get('items', [])
    
    score = 0
    feedback = []
    
    # 1. Get Task Result JSON (Timing)
    task_result = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
        temp_json_path = f.name
    
    try:
        copy_from_env("/tmp/task_result.json", temp_json_path)
        with open(temp_json_path, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load task result JSON: {e}")
    finally:
        if os.path.exists(temp_json_path):
            os.unlink(temp_json_path)

    # 2. Get Database File
    # We try to copy the snapshot created by export_result.sh
    # Windows path inside container: C:\Temp\copper_snapshot.db
    # copy_from_env handles the container-to-host transfer.
    
    with tempfile.NamedTemporaryFile(delete=False, suffix='.db') as db_file:
        local_db_path = db_file.name

    db_copied = False
    try:
        # Try specific path set in export script
        copy_from_env("C:\\Temp\\copper_snapshot.db", local_db_path)
        db_copied = True
    except Exception:
        # Fallback: Try common live paths
        try:
            copy_from_env("C:\\ProgramData\\NCH Software\\Copper\\Shared\\copper.db", local_db_path)
            db_copied = True
        except Exception as e:
            feedback.append(f"Could not retrieve database: {e}")

    if notdb_copied:
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve Copper database for verification."}

    # 3. Inspect Database
    try:
        conn = sqlite3.connect(local_db_path)
        cursor = conn.cursor()
        
        # List tables to debug if schema differs
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
        tables = [row[0] for row in cursor.fetchall()]
        logger.info(f"Tables found: {tables}")
        
        # Identify Items table
        # NCH Copper usually uses 'Items' or 'Objects' table. 
        # Columns often: ItemName, ItemCode, UnitValue (Price), ManageStock (or similar)
        
        items_table = "Items" if "Items" in tables else None
        if not items_table:
            # Fallback search
            for t in tables:
                if "Item" in t:
                    items_table = t
                    break
        
        if not items_table:
            return {"passed": False, "score": 0, "feedback": f"Could not find Items table in DB. Tables: {tables}"}

        # Query items
        # We need to find columns.
        cursor.execute(f"PRAGMA table_info({items_table})")
        columns = [row[1] for row in cursor.fetchall()]
        logger.info(f"Columns in {items_table}: {columns}")
        
        # Map columns
        col_code = next((c for c in columns if "Code" in c), "ItemCode")
        col_name = next((c for c in columns if "Name" in c or "Desc" in c), "ItemName")
        col_price = next((c for c in columns if "Price" in c or "Value" in c), "UnitValue")
        # Stock flag: ManageStock, Service, IsService, StockControl?
        col_stock = next((c for c in columns if "Stock" in c or "Service" in c), None)
        
        logger.info(f"Mapped columns: Code={col_code}, Name={col_name}, Price={col_price}, StockFlag={col_stock}")

        # Check each expected item
        items_created_score = 0
        items_price_score = 0
        items_config_score = 0
        
        for item in expected_items:
            code = item['code']
            price = item['price']
            
            # Query
            cursor.execute(f"SELECT {col_name}, {col_price}, {col_stock} FROM {items_table} WHERE {col_code}=?", (code,))
            row = cursor.fetchone()
            
            if row:
                items_created_score += 10 # 30 pts total
                
                # Check Price
                # Price might be stored as cents or float
                db_price = row[1]
                if abs(float(db_price) - price) < 0.01:
                    items_price_score += 6.66 # 20 pts total
                else:
                    feedback.append(f"Item {code}: Price mismatch (Expected {price}, Got {db_price})")
                
                # Check Stock Configuration
                # Expecting 'ManageStock' to be 0/False, or 'IsService' to be 1/True
                # We need to know which semantics apply based on column name
                stock_val = row[2]
                is_service_correct = False
                
                if col_stock:
                    if "Service" in col_stock:
                        # Likely 'IsService' -> Expect 1
                        if stock_val in [1, '1', True, 'True']:
                            is_service_correct = True
                    else:
                        # Likely 'ManageStock' -> Expect 0
                        if stock_val in [0, '0', False, 'False', None]:
                            is_service_correct = True
                
                if is_service_correct:
                    items_config_score += 16.66 # 50 pts total
                else:
                    feedback.append(f"Item {code}: Incorrect type (Expected Service/No-Stock, Got {col_stock}={stock_val})")
            else:
                feedback.append(f"Item {code}: Not found in database")

        conn.close()
        
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Database inspection failed: {str(e)}"}
    finally:
        if os.path.exists(local_db_path):
            os.unlink(local_db_path)

    # Calculate final scores
    # Rounding to nearest integer
    total_score = int(items_created_score + items_price_score + items_config_score)
    
    # 3 items * 10 = 30
    # 3 items * 6.66 = 20
    # 3 items * 16.66 = 50
    # Total = 100
    
    if total_score > 100: total_score = 100
    
    # Pass threshold: 80 (Need most things correct, especially service config)
    passed = total_score >= 80
    
    if passed:
        feedback.insert(0, "Task passed successfully.")
    else:
        feedback.insert(0, "Task failed.")
        
    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }