#!/bin/bash
set -e
echo "=== Setting up E-Commerce Order-to-Cash Audit Task ==="

source /workspace/scripts/task_utils.sh

DB_DIR="/home/ga/Documents/databases"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPT_DIR="/home/ga/Documents/scripts"

mkdir -p "$DB_DIR" "$EXPORT_DIR" "$SCRIPT_DIR"
chown -R ga:ga /home/ga/Documents

# Delete stale outputs BEFORE recording timestamp
rm -f "$DB_DIR/ecommerce.db"
rm -f "$EXPORT_DIR/anomaly_report.csv"
rm -f "$EXPORT_DIR/audit_summary.csv"
rm -f "$SCRIPT_DIR/audit_queries.sql"
rm -f /tmp/audit_ground_truth.json
rm -f /tmp/task_result.json