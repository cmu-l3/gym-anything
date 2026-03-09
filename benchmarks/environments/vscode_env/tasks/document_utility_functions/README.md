# Document Utility Functions Task

**Difficulty**: 🟡 Medium  
**Skills**: Code comprehension, JSDoc documentation, TypeScript, IntelliSense  
**Duration**: 300 seconds  
**Steps**: ~30

## Objective

Add comprehensive JSDoc documentation to three undocumented TypeScript utility functions to enable IntelliSense tooltips and improve code maintainability.

## Scenario

You've just joined a team and been assigned to extend their TypeScript utilities library. The code works correctly but lacks documentation - when you hover over function calls, VSCode shows no helpful information. Your tech lead has asked you to document three specific utility functions with proper JSDoc comments before starting your feature work.

## Functions to Document

1. **`formatCurrency(amount: number, locale?: string): string`**
   - Formats a number as currency with locale support
   
2. **`debounce<T>(func: T, wait: number): T`**
   - Creates a debounced version of a function
   
3. **`deepMerge(target: any, source: any): any`**
   - Recursively merges two objects

## Required JSDoc Elements

For each function, add:
- **Description**: Clear explanation of what the function does (at least one substantive sentence)
- **@param** tags: For each parameter with type and description
- **@returns** tag: Description of return value
- **@example** tag: At least one usage example for `formatCurrency` and `debounce`

## Expected Workflow

1. Open `/home/ga/workspace/utils/helpers.ts`
2. Read and understand each function's implementation
3. Add JSDoc comment blocks above each function
4. Include all required tags with accurate descriptions
5. Save the file (Ctrl+S)

## Verification

Checks for:
1. JSDoc comments present for all three functions
2. All required tags present (@param, @returns, @example where needed)
3. Parameter names in @param match actual function parameters
4. Descriptions are substantive (not generic "does stuff")
5. Proper JSDoc syntax (/** ... */)

**Pass Threshold**: 85% (most criteria met for all functions)

## Example JSDoc Format
