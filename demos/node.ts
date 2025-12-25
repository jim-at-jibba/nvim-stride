// Demo file for testing stride.nvim with TypeScript/Node
// Run: :luafile demo.lua (from project root first)
// Then edit this file to test predictions

import express, { Request, Response } from "express";

// =============================================================================
// REPLACE ACTION TESTS (existing functionality)
// =============================================================================

// -----------------------------------------------------------------------------
// TEST 1: Variable rename propagation
// 1. Change "app" to "server" on line 18
// 2. Exit insert mode - stride predicts updating other "app" references
// 3. Press Tab to accept each suggestion
// -----------------------------------------------------------------------------

const server = express();
const PORT = 3000;

server.use(express.json());
server.listen(PORT, () => console.log(`Running on ${PORT}`));

// -----------------------------------------------------------------------------
// TEST 2: Function rename
// 1. Rename "validatePost" to "isValidPost" on line 34
// 2. Exit insert mode - stride suggests updating the call on line 40
// -----------------------------------------------------------------------------

interface Post {
  id: string;
  title: string;
  content: string;
  author: string;
}

const isValidPost = (post: Partial<Post>): boolean => {
  return !!(post.title && post.content);
};

const isPostValid = isValidPost({ title: "test", content: "content" });

// =============================================================================
// INSERT ACTION TESTS (new functionality)
// =============================================================================

// -----------------------------------------------------------------------------
// TEST 3: Interface property insertion
// HOW TO TEST:
// 1. Add "author: string;" after "content: string;" in Post interface (line 33)
// 2. Exit insert mode
// 3. Stride should suggest INSERTING "author: post.author" in createPost object
// 4. Press Tab to accept
//
// EXPECTED: Anchor="content: post.content!, author: post.author!", Position="after", Insert=", author: post.author!"
// -----------------------------------------------------------------------------

const createPost = (post: Partial<Post>): Post => {
  return {
    id: crypto.randomUUID(),
    title: post.title!,
    content: post.content!,
    author: post.author!,
    // <- insertion point for "author"
  };
};

// -----------------------------------------------------------------------------
// TEST 4: Function parameter insertion
// HOW TO TEST:
// 1. Add ", timeout?: number" after "userId: string" on line 78
// 2. Exit insert mode
// 3. Stride should suggest INSERTING ", 5000" at call sites
// 4. Press Tab to accept each insertion
//
// EXPECTED: Anchor='"user-123"', Position="after", Insert=", 5000"
// -----------------------------------------------------------------------------

const fetchUser = async (
  userId: string,
): Promise<{ id: string; name: string }> => {
  return { id: userId, name: "John" };
};

// Call sites that need the new parameter
const getUser1 = async () => await fetchUser("user-123");
const getUser2 = async () => await fetchUser("user-456");
const getUser3 = async () => await fetchUser("user-789");

// -----------------------------------------------------------------------------
// TEST 5: Object property insertion
// HOW TO TEST:
// 1. Add "timestamp: Date.now()," after "status: 200," on line 99
// 2. Exit insert mode
// 3. Stride should suggest inserting timestamp in similar response objects
//
// EXPECTED: Anchor="status: 200", Position="after", Insert=", timestamp: Date.now()"
// -----------------------------------------------------------------------------

const successResponse = {
  status: 200,
  // <- ADD "timestamp: Date.now()," HERE
  message: "OK",
};

const errorResponse = {
  status: 500,
  message: "Error",
};

const notFoundResponse = {
  status: 404,
  message: "Not found",
};

// -----------------------------------------------------------------------------
// TEST 6: Array element insertion
// HOW TO TEST:
// 1. Add "'debug'," after "'warning'," on line 123
// 2. Exit insert mode
// 3. Stride should suggest inserting in similar arrays
//
// EXPECTED: Anchor="'warning'", Position="after", Insert=", 'debug'"
// -----------------------------------------------------------------------------

const LOG_LEVELS = [
  "error",
  "warning",
  // <- ADD "'debug'," HERE
  "info",
];

const ALERT_TYPES = ["critical", "warning", "info"];

// -----------------------------------------------------------------------------
// TEST 7: Type union insertion
// HOW TO TEST:
// 1. Add "| 'pending'" after "'failed'" on line 145
// 2. Exit insert mode
// 3. Stride should suggest inserting in similar type definitions
//
// EXPECTED: Anchor="'failed'", Position="after", Insert=" | 'pending'"
// -----------------------------------------------------------------------------

type Status = "success" | "failed";

type RequestStatus = "success" | "failed";

// -----------------------------------------------------------------------------
// TEST 8: Generic type parameter insertion
// HOW TO TEST:
// 1. Add ", Error" after "string" in ApiResponse<string> on line 162
// 2. Exit insert mode
// 3. Stride should suggest inserting Error type in other usages
//
// EXPECTED: Anchor="string", Position="after", Insert=", Error"
// -----------------------------------------------------------------------------

interface ApiResponse<T> {
  data: T;
  error?: string;
}

const response1: ApiResponse<string> = { data: "hello" };
const response2: ApiResponse<string> = { data: "world" };
