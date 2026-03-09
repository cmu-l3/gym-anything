#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Format API Response Task ==="

WORKSPACE_DIR="/home/ga/workspace/api_project"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create minified API response (realistic cryptocurrency API data)
cat > "$WORKSPACE_DIR/api_response.json" << 'EOF'
{"status":"success","timestamp":1703001234567,"data":{"markets":{"BTC":{"usd":{"price":43250.75,"volume":28934567890,"change_24h":2.34,"high_24h":43890.12,"low_24h":42100.45,"market_cap":846789123456},"eur":{"price":39876.23,"volume":25678912345,"change_24h":2.28,"high_24h":40234.67,"low_24h":38901.34,"market_cap":780123456789}},"ETH":{"usd":{"price":2287.45,"volume":15678234567,"change_24h":1.89,"high_24h":2310.78,"low_24h":2245.12,"market_cap":274567123456},"eur":{"price":2108.92,"volume":14234567890,"change_24h":1.85,"high_24h":2129.34,"low_24h":2067.89,"market_cap":253456789012}}},"metadata":{"api_version":"2.0","rate_limit":{"remaining":4850,"reset_at":1703004834}}}}
EOF

# Create README with task instructions
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# API Integration Task

## Your Mission

You received a sample cryptocurrency API response in `api_response.json`, but it's minified and unreadable.

## Tasks

1. **Format the JSON file**
   - Open `api_response.json` (currently all on one line)
   - Use VSCode's Format Document feature to make it readable
   - Methods: Command Palette → "Format Document", or Shift+Alt+F

2. **Extract key data** into `price_summary.json`: