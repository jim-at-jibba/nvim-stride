// Fresh demo file for testing stride.nvim with TypeScript/Node
// Tests are designed to work with the current change tracking system

import express from "express";

// =============================================================================
// TEST 1: Variable rename (simple)
// 1. Change "app" on line 13 to "server" (just type over it)
// 2. Exit insert mode (Esc)
// 3. Stride should suggest replacing "app" on lines 16, 17
// =============================================================================

const server = express();
const PORT = 3000;

server.use(express.json());
server.listen(PORT, () => console.log(`Running on ${PORT}`));

// =============================================================================
// TEST 2: Function rename
// 1. Change "getUserById" to "fetchUser" on line 27
// 2. Exit insert mode
// 3. Stride should suggest replacing calls on lines 32, 33
// =============================================================================

interface User {
  id: string;
  name: string;
}

const getUserById = (id: string): User => {
  return { id, name: "Test User" };
};

const user1 = getUserById("123");
const user2 = getUserById("456");

// =============================================================================
// TEST 3: Constant rename
// 1. Change "MAX_RETRIES" to "RETRY_LIMIT" on line 43
// 2. Exit insert mode
// 3. Stride should suggest replacing usages on lines 46, 47, 51
// =============================================================================

const RETRY_LIMIT = 3;

const config = {
  retries: RETRY_LIMIT,
  timeout: RETRY_LIMIT * 1000,
};

function retry(fn: () => void) {
  for (let i = 0; i < RETRY_LIMIT; i++) {
    fn();
  }
}

// =============================================================================
// TEST 4: Type rename
// 1. Change "ApiResponse" to "Response" on line 62
// 2. Exit insert mode
// 3. Stride should suggest replacing usages on lines 67, 68
// =============================================================================

interface Response {
  data: unknown;
  status: number;
}

const successResponse: Response = { data: "ok", status: 200 };
const errorResponse: Response = { data: null, status: 500 };

// =============================================================================
// TEST 5: Method rename
// 1. Change "processItem" to "handleItem" on line 78
// 2. Exit insert mode
// 3. Stride should suggest replacing call on line 84
// =============================================================================

class ItemProcessor {
  handleItem(item: string): string {
    return item.toUpperCase();
  }
}

const processor = new ItemProcessor();
const result = processor.handleItem("test");

// =============================================================================
// TIPS FOR BEST RESULTS:
// - Use ciw (change inner word) to replace whole identifiers at once
// - Or use visual mode to select the word, then type replacement
// - Character-by-character editing now works thanks to change aggregation!
// =============================================================================
