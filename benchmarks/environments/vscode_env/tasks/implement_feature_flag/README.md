# Implement Feature Flag Task

**Difficulty**: 🟡 Medium  
**Skills**: Feature flags, environment variables, conditional logic, deployment strategy, logging  
**Duration**: 900 seconds (15 minutes)  
**Steps**: ~100

## Objective

Implement a feature flag system to safely control the rollout of a new Stripe payment integration in a Flask application. This task simulates a real-world deployment scenario where code must be deployed to production but features should be toggled on/off without redeployment.

## Real-World Context

You're a backend engineer at an e-commerce company. Your team has finished implementing a new Stripe payment integration to replace the legacy payment processor. However, stakeholders are nervous about switching all traffic immediately. They want to:

1. Deploy the code to production NOW (release train waits for no one)
2. Keep the new Stripe integration disabled initially
3. Enable it with a simple configuration change (no redeployment)
4. Have an emergency "kill switch" if something goes wrong
5. See clear logs showing which payment processor is being used

## Initial State

The workspace contains:
- `app.py` - Flask application with `/checkout` endpoint (currently uses only legacy processor)
- `payment_processor.py` - Contains both `process_payment_legacy()` and `process_payment_stripe()` functions
- `.env.example` - Template for environment variables
- `requirements.txt` - Python dependencies

## Goal State

After completing the task, you should have:

1. **Created `.env` file** with `USE_STRIPE_PAYMENT=false` (or `true`)
2. **Implemented feature flag logic** in `app.py` that reads the environment variable
3. **Modified `/checkout` endpoint** to conditionally use Stripe or legacy processor based on flag
4. **Added logging** to track which payment processor is being used
5. **Both code paths functional** - app works regardless of flag state

## Expected Implementation

### 1. Create `.env` file
