# Prototype API Integration Task

**Difficulty**: 🟡 Medium  
**Skills**: HTTP requests, REST Client, API exploration, documentation  
**Duration**: 900 seconds (15 minutes)  
**Steps**: ~100

## Objective

Prototype integration with the OpenWeatherMap API using VSCode's REST Client extension. Create a collection of HTTP requests that test multiple endpoints, demonstrate different query patterns, and document the API behavior for your team.

## Context

Your team needs to integrate a weather forecasting feature. The PM wants a prototype by tomorrow's standup showing that the OpenWeatherMap API can provide the required data. Rather than diving into production code, you'll explore the API interactively first.

## Expected Workflow

1. Review `API_DOCS.md` for endpoint information
2. Get API key from `.env` file
3. Edit `weather_api.http` to add HTTP requests
4. Test at least 3 different endpoints:
   - Current weather
   - 5-day forecast
   - Geocoding (city name → coordinates)
5. Use different query patterns (city name, coordinates, units)
6. Add comments documenting responses
7. Save the file (Ctrl+S)

## REST Client Syntax
