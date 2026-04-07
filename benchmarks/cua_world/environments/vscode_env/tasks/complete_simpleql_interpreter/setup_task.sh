#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Complete SimpleQL Interpreter Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

WORKSPACE_DIR="/home/ga/workspace/simpleql"
sudo -u ga mkdir -p "$WORKSPACE_DIR/data"
cd "$WORKSPACE_DIR"

# ─────────────────────────────────────────────────────────────
# 1. Create GRAMMAR.md
# ─────────────────────────────────────────────────────────────
sudo -u ga cat > "$WORKSPACE_DIR/GRAMMAR.md" << 'EOF'
# SimpleQL Grammar Specification

SimpleQL is a lightweight SQL-like language for querying JSON arrays of objects.

## EBNF Grammar