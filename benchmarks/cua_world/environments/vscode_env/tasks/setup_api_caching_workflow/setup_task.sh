#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up API Caching Workflow Task ==="

WORKSPACE_DIR="/home/ga/workspace/weather_app"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create API configuration file
cat > "$WORKSPACE_DIR/api_config.json" << 'EOF'
{
  "api_name": "OpenWeatherMap",
  "base_url": "https://api.openweathermap.org/data/2.5/weather",
  "api_key": "demo_key_12345_replace_with_real_key",
  "rate_limit": "60 calls per hour (free tier)",
  "docs_url": "https://openweathermap.org/api"
}
EOF

# Create locations test file
cat > "$WORKSPACE_DIR/locations.txt" << 'EOF'
London
Tokyo
Paris
New York
Sydney
Berlin
Mumbai
Toronto
Singapore
InvalidCity123
EOF

# Create a sample response template for reference
cat > "$WORKSPACE_DIR/sample_response_format.json" << 'EOF'
{
  "coord": {"lon": -0.1257, "lat": 51.5085},
  "weather": [{"id": 800, "main": "Clear", "description": "clear sky"}],
  "main": {
    "temp": 283.15,
    "feels_like": 281.5,
    "temp_min": 282.15,
    "temp_max": 284.15,
    "pressure": 1013,
    "humidity": 72
  },
  "name": "London",
  "cod": 200
}
EOF

# Create instructions file
cat > "$WORKSPACE_DIR/INSTRUCTIONS.md" << 'EOF'
# Weather App API Caching Setup

## Problem
You keep hitting the OpenWeatherMap API rate limit (60 calls/hour) while testing.
This is blocking development progress.

## Your Task
Set up a local caching workflow so you can test unlimited times without hitting rate limits.

## Steps
1. Install a REST client extension (REST Client, Thunder Client, etc.)
2. Create request files to call the weather API
3. Create a cache directory (responses/, mocks/, or cache/)
4. Save at least 5 API responses as JSON files with descriptive names
5. Include both success responses AND error responses (404, 429)
6. Create a .env file with cache configuration (USE_CACHE=true, etc.)
7. Document the workflow in cache_README.md or comments

## API Details
- Endpoint: https://api.openweathermap.org/data/2.5/weather?q={city}&appid={key}
- API key and config: see api_config.json
- Test cities: see locations.txt
- Sample response format: see sample_response_format.json

## Example Cache Structure