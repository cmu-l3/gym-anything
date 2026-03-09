# FastAPI Debug Configuration Task

**Difficulty**: 🟡 Medium  
**Skills**: VSCode debugging, launch.json configuration, environment variables  
**Duration**: 300 seconds  
**Steps**: ~40

## Objective

Create a VSCode debug configuration for a FastAPI application that requires environment variables, command-line arguments, and a specific Python interpreter.

## Scenario

You're working on a FastAPI microservice that needs proper debugging setup. The application requires:
- Environment variable `DATABASE_URL` for database connection
- Command-line arguments `--config config.yaml --port 8080`
- Python interpreter from virtual environment (`.venv`)

Currently, debugging doesn't work because the environment isn't configured. Your task is to create a `.vscode/launch.json` file with a debug configuration named "FastAPI Debug" that includes all necessary settings.

## Expected Workflow

1. Create `.vscode/` directory in workspace (if it doesn't exist)
2. Create or open `.vscode/launch.json`
3. Add a debug configuration with:
   - Name: "FastAPI Debug"
   - Type: "python"
   - Request: "launch"
   - Program/module: app.py
   - Environment variable: DATABASE_URL=postgresql://localhost/testdb
   - Arguments: --config config.yaml --port 8080
   - Python path: .venv/bin/python (or similar)
4. Save the file

**Tip**: You can use Command Palette → "Debug: Open launch.json" to create the file with a template.

## Verification

Checks for:
1. `.vscode/launch.json` file exists
2. Configuration named "FastAPI Debug" exists
3. Environment variable DATABASE_URL is set correctly
4. Arguments include --config and --port
5. Python interpreter points to virtual environment
6. Valid JSON structure

**Pass Threshold**: 80% (5/6 criteria)