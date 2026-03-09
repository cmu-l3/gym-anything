# Environment Config Setup Task

**Difficulty**: 🟡 Medium  
**Skills**: Code analysis, environment configuration, file creation, debugging  
**Duration**: 240 seconds  
**Steps**: ~20

## Objective

Set up environment variable configuration for a Node.js application that won't run without a proper `.env` file. This task simulates the common real-world scenario of setting up a project for local development.

## Scenario

You've cloned a Node.js application repository. When you try to run `npm start`, the application crashes with errors about missing environment variables. The README mentions setting up a `.env` file but doesn't specify what variables are needed. You must analyze the code to understand requirements.

## Expected Workflow

1. **Analyze the codebase**: Use VSCode search (Ctrl+Shift+F) to find all `process.env` references
2. **Identify required variables**: Look for variables without default values (these will crash if missing)
3. **Create .env file**: Create a new file named `.env` in the project root
4. **Add configuration**: Write KEY=VALUE pairs for required variables
5. **Test application**: Run `npm start` to verify the app starts successfully

## Required Environment Variables

Search the code to find these (hint: check `server.js` and `config.js`):
- **PORT**: Port number for the server (e.g., 3000)
- **DATABASE_URL**: Database connection string (e.g., postgresql://localhost:5432/testdb)
- **API_KEY**: API authentication key (e.g., test_key_12345)
- **NODE_ENV**: Environment name (e.g., development)

## .env File Format
