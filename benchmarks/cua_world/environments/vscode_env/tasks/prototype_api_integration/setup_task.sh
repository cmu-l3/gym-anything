#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Prototype API Integration Task ==="

WORKSPACE_DIR="/home/ga/workspace/weather_integration"
TASK_ASSETS="/workspace/tasks/prototype_api_integration/assets"

# Create workspace
sudo -u ga mkdir -p "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"

# Install REST Client extension if not present
echo "Installing REST Client extension..."
su - ga -c "DISPLAY=:1 code --install-extension humao.rest-client" || true
sleep 2

# Copy API documentation reference
if [ -f "$TASK_ASSETS/openweathermap_api_docs.md" ]; then
    sudo -u ga cp "$TASK_ASSETS/openweathermap_api_docs.md" "$WORKSPACE_DIR/API_DOCS.md"
    echo "API documentation copied"
else
    echo "⚠️ Warning: API docs not found, creating minimal version"
    cat > "$WORKSPACE_DIR/API_DOCS.md" << 'EOF'
# OpenWeatherMap API Quick Reference

Base URL: https://api.openweathermap.org/data/2.5

Authentication: Add appid=YOUR_API_KEY as query parameter

Endpoints:
- GET /weather - Current weather (params: q=city or lat/lon, units=metric/imperial)
- GET /forecast - 5-day forecast (same params)
- GET /geo/1.0/direct - Geocoding (params: q=city, limit=5)
EOF
fi

# Provide API key in config file
cat > "$WORKSPACE_DIR/.env" << 'EOF'
# OpenWeatherMap API Key (free tier)
OPENWEATHER_API_KEY=a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6

# Note: This is a sample key for prototyping
# Get your own at: https://openweathermap.org/appid
EOF

# Create starter file with template
cat > "$WORKSPACE_DIR/weather_api.http" << 'EOF'
### OpenWeatherMap API Testing
### Documentation: See API_DOCS.md in this directory
### API Key stored in .env file

# TODO: Configure API key variable (get from .env file)
@apiKey = YOUR_API_KEY
@baseUrl = https://api.openweathermap.org/data/2.5

### TODO: Test current weather endpoint
# Add request here

EOF

# Create README with task instructions
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Weather API Integration Prototype

## Goal
Explore OpenWeatherMap API to validate it meets our requirements.

## Tasks
1. Get API key from `.env` file
2. Edit `weather_api.http` with REST Client syntax
3. Test these endpoints:
   - Current weather: GET /weather
   - 5-day forecast: GET /forecast
   - Geocoding: GET /geo/1.0/direct
4. Try different query patterns:
   - City name: ?q=London
   - Coordinates: ?lat=51.5&lon=-0.1
   - Units: ?units=metric
5. Document with comments (#)
6. Save the file

## REST Client Tips
- Use ### to separate requests
- Click "Send Request" to execute
- Variables: @name = value
- Comments: # text
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Initialize git repo for version tracking
cd "$WORKSPACE_DIR"
sudo -u ga git init
sudo -u ga git config user.name "GA User"
sudo -u ga git config user.email "ga@example.com"
sudo -u ga git add .
sudo -u ga git commit -m "Initial API prototype setup" || true

# Open VSCode in workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$WORKSPACE_DIR/weather_api.http'" &
wait_for_vscode 25
wait_for_window "Visual Studio Code" 30

# Click center to focus desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Prototype API Integration Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Review API_DOCS.md for endpoint details"
echo "  2. Get API key from .env file (OPENWEATHER_API_KEY)"
echo "  3. Edit weather_api.http to add HTTP requests"
echo "  4. Test 3+ endpoints: /weather, /forecast, /geo/1.0/direct"
echo "  5. Use different query patterns (city, coordinates, units)"
echo "  6. Add comments documenting responses"
echo "  7. Save file (Ctrl+S)"
echo ""
echo "Workspace: $WORKSPACE_DIR"