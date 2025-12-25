// Demo file for testing stride.nvim with TypeScript/Node
// Run: :luafile demo.lua (from project root first)
// Then edit this file to test predictions

import express, { Request, Response, NextFunction } from "express";

// -----------------------------------------------------------------------------
// TEST 1: Variable rename propagation
// 1. Change "app" to "server"
// 2. Exit insert mode - stride predicts updating other "app" references
// 3. Press Tab to accept
// -----------------------------------------------------------------------------

const app = express();
const PORT = 3000;

app.use(express.json());

// -----------------------------------------------------------------------------
// TEST 2: Interface property rename
// 1. Change "userId" to "authorId" in the interface
// 2. Exit insert mode - stride suggests updating usages
// -----------------------------------------------------------------------------

interface Post {
  id: string;
  title: string;
  content: string;
  userId: string;
  createdAt: Date;
}

const posts: Post[] = [];

// -----------------------------------------------------------------------------
// TEST 3: Function rename
// 1. Rename "validatePost" to "checkPost"
// 2. Exit insert mode - stride suggests updating the call below
// -----------------------------------------------------------------------------

const validatePost = (post: Partial<Post>): boolean => {
  if (!post.title || post.title.length < 3) {
    return false;
  }
  if (!post.content || post.content.length < 10) {
    return false;
  }
  if (!post.userId) {
    return false;
  }
  return true;
};

app.post("/posts", (req: Request, res: Response) => {
  const post = req.body as Partial<Post>;

  if (!validatePost(post)) {
    return res.status(400).json({ error: "Invalid post data" });
  }

  const newPost: Post = {
    id: crypto.randomUUID(),
    title: post.title!,
    content: post.content!,
    userId: post.userId!,
    createdAt: new Date(),
  };

  posts.push(newPost);
  res.status(201).json(newPost);
});

// -----------------------------------------------------------------------------
// TEST 4: Error message rename
// 1. Change "not found" to "does not exist"
// 2. Exit insert mode - stride suggests updating similar messages
// -----------------------------------------------------------------------------

app.get("/posts/:id", (req: Request, res: Response) => {
  const post = posts.find((p) => p.id === req.params.id);

  if (!post) {
    return res.status(404).json({ error: "Post not found" });
  }

  res.json(post);
});

app.delete("/posts/:id", (req: Request, res: Response) => {
  const index = posts.findIndex((p) => p.id === req.params.id);

  if (index === -1) {
    return res.status(404).json({ error: "Post not found" });
  }

  posts.splice(index, 1);
  res.status(204).send();
});

// Error handler
const errorHandler = (
  err: Error,
  req: Request,
  res: Response,
  next: NextFunction
) => {
  console.error(err.stack);
  res.status(500).json({ error: "Internal server error" });
};

app.use(errorHandler);

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
