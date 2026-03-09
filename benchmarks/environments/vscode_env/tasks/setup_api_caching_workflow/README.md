# Setup API Caching Workflow Task

**Difficulty**: 🟡 Medium  
**Skills**: Extension management, REST clients, file organization, configuration, documentation  
**Duration**: 240 seconds  
**Steps**: ~40

## Objective

Configure a development workflow that caches API responses locally to work around rate limits. The agent must set up a REST client, make API calls, save responses to a cache directory, create configuration files, and document the workflow.

## Scenario

You're building a weather dashboard that integrates with the OpenWeatherMap API (free tier: 60 calls/hour). You keep hitting rate limits while testing different locations and error cases, which is blocking development. You need to set up response caching so you can iterate quickly without burning through your quota.

## Expected Workflow

1. **Install REST Client Extension**
   - Use Command Palette (Ctrl+Shift+P) → "Extensions: Install Extensions"
   - Search for and install "REST Client" (by Huachao Mao) OR "Thunder Client" OR similar
   
2. **Create Request Files**
   - Create `.http` files (for REST Client) or equivalent request definitions
   - Define API requests for different cities/scenarios
   
3. **Create Cache Directory**
   - Create a `responses/`, `mocks/`, or `cache/` directory in the workspace
   
4. **Make API Calls and Save Responses**
   - Execute requests to get real API responses
   - Save at least 5 different responses as JSON files with meaningful names
   - Include both success (200) and error (404, 429) responses
   - Example names: `london_sunny.json`, `tokyo_rainy.json`, `rate_limit_429.json`
   
5. **Create Configuration**
   - Create `.env` file with cache toggle settings
   - Example: `USE_CACHE=true`, `CACHE_DIR=responses`
   
6. **Document the Workflow**
   - Create `cache_README.md` or add substantial comments in `.http` files
   - Explain how to toggle between cached and real API mode
   - Document when to refresh cached data

## Verification

Checks for:
1. REST client extension installed (REST Client, Thunder Client, or Postman)
2. Request files exist (`.http`, `.rest`, or equivalent)
3. Cache directory exists (`responses/`, `mocks/`, or `cache/`)
4. At least 5 cached JSON response files present
5. Configuration file exists (`.env` or `api_config.json` with cache settings)
6. Documentation present (README or comments explaining workflow)
7. Response diversity (both success and error responses cached)

**Pass Threshold**: 71% (5/7 criteria)