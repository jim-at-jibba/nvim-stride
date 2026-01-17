# Testing Checklist: Treesitter Context Extraction

## Prerequisites

- [ ] Plugin installed and loaded in Neovim
- [ ] Cerebras API key set (`vim.g.stride_cerebras_api_key` or environment variable)
- [ ] mode configured to `"refactor"` or `"both"` in `require('stride').setup()`

## Test Cases

### 1. Function Detection (Lua)

**Steps:**
1. Open a Lua file with multiple functions:
   ```lua
   local M = {}

   function M.add(a, b)
     return a + b
   end

   function M.multiply(x, y)
     return x * y
   end

   return M
   ```
2. Place cursor inside `M.multiply` function
3. Type to trigger refactor prediction (e.g., `return x *`)
4. **Verify:** API request includes `function_name: "multiply"` and `file_context` with function body

### 2. Function Detection (TypeScript/JavaScript)

**Steps:**
1. Open a TypeScript file with functions:
   ```typescript
   function calculateSum(nums: number[]): number {
     const total = nums.reduce((a, b) => a + b, 0);
     return total;
   }

   function calculateAverage(nums: number[]): number {
     return calculateSum(nums) / nums.length;
   }
   ```
2. Place cursor inside `calculateAverage`
3. Trigger prediction
4. **Verify:** API request includes `function_name: "calculateAverage"` with TypeScript context

### 3. Function Detection (Python)

**Steps:**
1. Open a Python file with functions:
   ```python
   def process_data(items):
       return [item.upper() for item in items]

   def format_results(results):
       return ", ".join(results)
   ```
2. Place cursor inside `process_data`
3. Trigger prediction
4. **Verify:** API request includes `function_name: "process_data"` with Python context

### 4. AGENTS.md Context Enabled

**Steps:**
1. Create `AGENTS.md` in project root with:
   ```markdown
   Use snake_case for function names.
   Prefer pure functions without side effects.
   ```
2. Configure:
   ```lua
   require('stride').setup({
     context_files = { "AGENTS.md" }
   })
   ```
3. Reload plugin
4. Open any file and trigger prediction
5. **Verify:** API request includes `context` field with AGENTS.md content (capped at 2000 chars)

### 5. AGENTS.md Disabled (Default)

**Steps:**
1. Remove `context_files` from config or set to `false`
2. Reload plugin
3. Trigger prediction
4. **Verify:** API request does NOT include `context` field
5. **Verify:** Predictions still work normally

### 6. V1 Completion Mode

**Steps:**
1. Configure:
   ```lua
   require('stride').setup({
     mode = "completion"
   })
   ```
2. Reload plugin
3. Enter insert mode and type
4. **Verify:** Ghost text completions appear (V1 behavior)
5. **Verify:** No treesitter context extraction occurs (check logs)

### 7. Edge Cases

#### File Not in Function
1. Open file with code outside any function
2. Place cursor at top level
3. Trigger prediction
4. **Verify:** API request omits `function_name` and `file_context` but still includes `cursor_context`

#### Treesitter Unavailable
1. Open file with unsupported filetype (or disable treesitter)
2. Trigger prediction
3. **Verify:** No errors, prediction falls back to cursor-only context
4. **Verify:** Logs show warning about treesitter failure

#### Large AGENTS.md
1. Create `AGENTS.md` with >2000 characters
2. Enable `context_files = { "AGENTS.md" }`
3. Trigger prediction
4. **Verify:** `context` field is capped at 2000 characters
5. **Verify:** Content truncated at word boundary (not mid-word)

## Additional Verification

- [ ] Check `:messages` for any errors during testing
- [ ] Verify API payloads using network debugging (or enable debug logging)
- [ ] Test with multiple files open simultaneously
- [ ] Verify performance is acceptable with context extraction enabled
