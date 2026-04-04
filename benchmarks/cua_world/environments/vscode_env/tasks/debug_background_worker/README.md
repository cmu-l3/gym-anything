# Debug Background Worker Task

**Difficulty**: 🟡 Medium  
**Skills**: Background process debugging, debug configuration, YAML config, job queue understanding  
**Duration**: 300 seconds  
**Steps**: ~35

## Objective

Debug a background worker that processes image thumbnails. The worker is failing due to a configuration bug. Set up proper debugging infrastructure, identify and fix the configuration issue, and verify the worker can successfully process jobs.

## Scenario

You're maintaining an e-commerce platform's thumbnail generation service. QA reports that uploaded product images aren't generating thumbnails, causing broken product pages. The worker logs show: `Error processing job: Invalid dimensions`. Your task is to:

1. Set up a debug configuration for the background worker
2. Identify the configuration bug in `config.yaml`
3. Fix the invalid configuration value
4. Verify the worker can process jobs successfully

## Expected Workflow

1. **Examine the codebase**
   - Open `worker.py` to understand the job processing logic
   - Review `config.yaml` to find configuration issues
   - Check `queue.json` to see pending jobs

2. **Create debug configuration**
   - Create `.vscode/launch.json` 
   - Add a Python debug configuration that targets `worker.py`
   - Configuration should be named something like "Debug Thumbnail Worker"

3. **Fix configuration bug**
   - Open `config.yaml`
   - Find `thumbnail_width: 0` (invalid - must be positive)
   - Change to valid value like `thumbnail_width: 200`
   - Save the file

4. **Test the worker**
   - Ensure there's at least one pending job in `queue.json`
   - Run the worker (either via debug config or manually: `python worker.py`)
   - Verify job status changes to "completed" in `queue.json`
   - Check that thumbnail file appears in `output/` directory

## Files Structure
