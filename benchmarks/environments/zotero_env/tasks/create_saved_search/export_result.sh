#!/bin/bash
# Export result for create_saved_search task

echo "=== Exporting create_saved_search result ==="

DB="/home/ga/Zotero/zotero.sqlite"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_end_screenshot.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

sleep 2

python3 << 'PYEOF'
import sqlite3
import json

DB = "/home/ga/Zotero/zotero.sqlite"

TARGET_NAME = "Papers Since 2010"

result = {
    "search_found": False,
    "search_name": None,
    "search_id": None,
    "conditions": [],
    "condition_count": 0,
    "has_date_condition": False,
    "has_year_threshold": False,
    "year_threshold_value": None,
    "all_searches": [],
}

try:
    conn = sqlite3.connect(DB, timeout=10)
    cur = conn.cursor()

    # Get all saved searches
    cur.execute("SELECT savedSearchID, savedSearchName FROM savedSearches WHERE libraryID=1")
    all_searches = cur.fetchall()
    result["all_searches"] = [{"id": r[0], "name": r[1]} for r in all_searches]

    # Find our target search (exact name or close match)
    target = None
    for sid, name in all_searches:
        if name == TARGET_NAME:
            target = (sid, name)
            break

    # If not exact match, try case-insensitive or similar
    if not target:
        for sid, name in all_searches:
            if name.lower() == TARGET_NAME.lower():
                target = (sid, name)
                break

    # If still not found, try "since 2010" partial match
    if not target:
        for sid, name in all_searches:
            if "2010" in name and ("since" in name.lower() or "after" in name.lower() or "paper" in name.lower()):
                target = (sid, name)
                break

    if target:
        sid, name = target
        result["search_found"] = True
        result["search_name"] = name
        result["search_id"] = sid

        # Get conditions
        cur.execute(
            "SELECT searchConditionID, condition, operator, value FROM savedSearchConditions WHERE savedSearchID=? ORDER BY searchConditionID",
            (sid,)
        )
        conds = cur.fetchall()
        result["conditions"] = [
            {"id": r[0], "condition": r[1], "operator": r[2], "value": r[3]}
            for r in conds
        ]
        result["condition_count"] = len(result["conditions"])

        # Check if any condition involves date/year
        date_keywords = {"date", "year", "dateadded", "pubdate"}
        threshold_operators = {"isafter", "isgreater", "is greater than", "is after",
                               "isgreaterthan", ">", ">=", "isafterdate"}

        for cond in result["conditions"]:
            cond_field = (cond["condition"] or "").lower()
            cond_op = (cond["operator"] or "").lower().replace(" ", "")
            cond_val = (cond["value"] or "")

            if any(k in cond_field for k in date_keywords):
                result["has_date_condition"] = True

                # Check if value implies year >= 2010
                val_str = cond_val.strip()
                # Try to extract year from value
                import re
                year_match = re.search(r'\b(19|20)\d{2}\b', val_str)
                if year_match:
                    year_in_val = int(year_match.group())
                    result["year_threshold_value"] = year_in_val
                    # Valid threshold: value of 2009 with isAfter, OR 2010 with isAfter/>=
                    if year_in_val >= 2009 and year_in_val <= 2015:
                        result["has_year_threshold"] = True

                # Some Zotero versions use date strings like "2009-12-31"
                if "2009" in val_str or "2010" in val_str:
                    result["has_year_threshold"] = True

    conn.close()
except Exception as e:
    result["error"] = str(e)
    import traceback
    result["traceback"] = traceback.format_exc()

with open("/tmp/create_saved_search_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Search found: {result['search_found']}")
print(f"Search name: {result['search_name']}")
print(f"Conditions: {result['conditions']}")
print(f"Has date condition: {result['has_date_condition']}")
print(f"Has year threshold: {result['has_year_threshold']}")
print(f"All searches: {result['all_searches']}")
PYEOF

echo "=== Export Complete: create_saved_search ==="
