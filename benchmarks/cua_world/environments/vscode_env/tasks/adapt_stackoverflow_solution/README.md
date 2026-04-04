# Adapt Stack Overflow Solution Task

**Difficulty**: 🟡 Medium  
**Skills**: Code adaptation, framework knowledge, convention adherence, integration  
**Duration**: 720 seconds  
**Steps**: ~150

## Objective

Adapt a Stack Overflow Express.js rate limiting solution to work with Fastify while following team coding conventions.

## Scenario

You found a highly-rated Stack Overflow answer with perfect rate limiting code... but it's for Express.js and your project uses Fastify. You need to adapt it to:
- Work with Fastify (not Express)
- Follow team conventions (documented in `CONVENTIONS.md`)
- Use config-driven values (from `config/rate_limit.config.js`)
- Credit the source
- Integrate with existing server

## Expected Workflow

1. Read `CONVENTIONS.md` to understand team standards
2. Review the Express example in `src/utils/rate_limiter_example.js`
3. Review config values in `config/rate_limit.config.js`
4. Create Fastify-compatible rate limiter in `src/middleware/rate_limiter.js`:
   - Import configuration from config file
   - Convert Express middleware to Fastify plugin/hook
   - Use camelCase naming
   - Name error handler with `handle` prefix
   - Add JSDoc attribution to Stack Overflow
   - Use async/await pattern
5. Update `src/server.js` to integrate rate limiter
6. Clean up the example file (delete or move to `docs/references/`)

## Verification

Checks for:
1. Rate limiter file exists
2. Imports from config file
3. No hardcoded values (100, 60000, etc.)
4. Uses config values
5. No Express-specific code
6. Uses Fastify patterns
7. Has Stack Overflow attribution
8. Error handler naming convention
9. Server integration
10. Example file cleanup

**Pass Threshold**: 70% (7/10 criteria)