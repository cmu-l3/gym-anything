#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Fix Breaking Dependency Upgrade Task ==="

WORKSPACE_DIR="/home/ga/workspace/price_scraper"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
sudo -u ga mkdir -p "$WORKSPACE_DIR/scraper"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"

# Create UPGRADE_NOTES.md with breaking changes documentation
cat > "$WORKSPACE_DIR/UPGRADE_NOTES.md" << 'EOF'
# Requests Library Upgrade: 2.25.1 → 2.31.0

## Security Context

CVE-2023-32681: High-severity vulnerability in proxy authentication handling.
**Action Required**: Upgrade to requests>=2.31.0 immediately.

## Breaking Changes

### 1. Timeout Parameter (CRITICAL)

**Old API (2.25.1):**