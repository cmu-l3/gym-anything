# Extract Hardcoded Secrets Task

**Difficulty**: 🟡 Medium  
**Skills**: Security best practices, environment variables, refactoring, Git  
**Duration**: 180 seconds  
**Steps**: ~25

## Objective

Refactor a Python script to extract a hardcoded API key into an environment variable file, following security best practices.

## Scenario

You've accidentally hardcoded an API key in `main.py` and are about to commit. This is a critical security issue. You need to:

1. Extract the secret to a `.env` file
2. Update `.gitignore` to prevent committing secrets
3. Refactor the code to load from environment variables
4. Ensure the hardcoded key is completely removed

## Expected Workflow

1. Identify the hardcoded API key in `main.py`
2. Create `.env` file with: `API_KEY=<the_key_value>`
3. Open `.gitignore` and add `.env` to it
4. Modify `main.py` to:
   - Import `os` and `load_dotenv` from `dotenv`
   - Call `load_dotenv()`
   - Replace hardcoded key with `os.getenv("API_KEY")`
5. Save all files

## Verification

Checks for:
1. `.env` file exists with correct API key
2. `.gitignore` includes `.env`
3. Hardcoded secret removed from `main.py`
4. Code properly imports and uses environment variables

**Pass Threshold**: 100% (all 4 criteria must pass for security)