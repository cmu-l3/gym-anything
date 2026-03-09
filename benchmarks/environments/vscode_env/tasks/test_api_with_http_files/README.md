# REST API Testing with HTTP Files Task

**Difficulty**: 🟡 Medium  
**Skills**: HTTP protocol, REST APIs, VSCode HTTP files, API testing  
**Duration**: 300 seconds  
**Steps**: ~30

## Objective

Create an `.http` file in VSCode to test a REST API running locally. The task simulates a common backend developer workflow: testing API endpoints without leaving the editor.

## Scenario

You're developing a REST API locally (running on `http://localhost:3000`) and need to test multiple endpoints. Instead of using external tools like Postman or writing curl commands, you'll create HTTP request files in VSCode that can be:
- Easily executed with one click
- Shared with teammates via Git
- Configured for different environments

## Expected Workflow

1. Create a new file named `api-tests.http` in the workspace root
2. Define a variable for the base URL: `@baseUrl = http://localhost:3000`
3. Add HTTP requests for three endpoints:
   - `GET /api/users` - List all users
   - `POST /api/users` - Create a new user with JSON body
   - `GET /api/users/1` - Get specific user
4. Use `###` separators between requests
5. Add appropriate headers (Content-Type, Accept)
6. Save the file

## HTTP File Format Example
