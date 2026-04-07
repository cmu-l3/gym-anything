#!/bin/bash
echo "=== Exporting supplier_procurement_setup results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Read baseline
INITIAL_SUPPLIERS=$(cat /tmp/initial_supplier_count.txt 2>/dev/null || echo "0")
CURRENT_SUPPLIERS=$(snipeit_db_query "SELECT COUNT(*) FROM suppliers WHERE deleted_at IS NULL" | tr -d '[:space:]')

# Export Suppliers table to TSV for verifier
# Replace any internal tabs/newlines in fields to avoid breaking TSV structure
snipeit_db_query "SELECT 
    REPLACE(REPLACE(IFNULL(name,''), '\t', ' '), '\n', ' ') as name,
    REPLACE(REPLACE(IFNULL(city,''), '\t', ' '), '\n', ' ') as city,
    REPLACE(REPLACE(IFNULL(state,''), '\t', ' '), '\n', ' ') as state,
    REPLACE(REPLACE(IFNULL(zip,''), '\t', ' '), '\n', ' ') as zip,
    REPLACE(REPLACE(IFNULL(email,''), '\t', ' '), '\n', ' ') as email,
    REPLACE(REPLACE(IFNULL(phone,''), '\t', ' '), '\n', ' ') as phone,
    REPLACE(REPLACE(IFNULL(url,''), '\t', ' '), '\n', ' ') as url,
    REPLACE(REPLACE(IFNULL(notes,''), '\t', ' '), '\n', ' ') as notes
    FROM suppliers WHERE deleted_at IS NULL" > /tmp/suppliers_dump.tsv

# Export Assets table with Supplier Join to TSV for verifier
snipeit_db_query "SELECT 
    a.asset_tag, 
    REPLACE(REPLACE(IFNULL(a.order_number,''), '\t', ' '), '\n', ' ') as order_number,
    REPLACE(REPLACE(IFNULL(s.name,''), '\t', ' '), '\n', ' ') as supplier_name
    FROM assets a 
    LEFT JOIN suppliers s ON a.supplier_id = s.id 
    WHERE a.asset_tag LIKE 'PROC-00%' AND a.deleted_at IS NULL" > /tmp/assets_dump.tsv

# Export basic metadata JSON
cat > /tmp/task_result.json << EOF
{
  "initial_suppliers": $INITIAL_SUPPLIERS,
  "current_suppliers": $CURRENT_SUPPLIERS,
  "task_start_time": $(cat /tmp/task_start_time.txt 2>/dev/null || echo "0"),
  "task_end_time": $(date +%s)
}
EOF

# Ensure all files have permissive permissions for the verifier
chmod 666 /tmp/suppliers_dump.tsv /tmp/assets_dump.tsv /tmp/task_result.json 2>/dev/null || true

echo "Data exported to /tmp/suppliers_dump.tsv and /tmp/assets_dump.tsv"
echo "=== supplier_procurement_setup export complete ==="