// Demo file for testing stride.nvim with React/TSX
// Run: :luafile demo.lua (from project root first)
// Then edit this file to test predictions

import React, { useState, useEffect } from "react";

// =============================================================================
// REPLACE ACTION TESTS (existing functionality)
// =============================================================================

// -----------------------------------------------------------------------------
// TEST 1: Variable rename propagation
// 1. Change "count" to "counter" on line 27
// 2. Exit insert mode - stride predicts updating other "count" references
// 3. Press Tab to accept each suggestion
// -----------------------------------------------------------------------------

export const Counter: React.FC = () => {
  const [count, setCount] = useState(0);

  return (
    <div>
      <h2>Count: {count}</h2>
      <button onClick={() => setCount(count + 1)}>+</button>
      <button onClick={() => setCount(count - 1)}>-</button>
    </div>
  );
};


// -----------------------------------------------------------------------------
// TEST 2: Function rename
// 1. Rename "fetchUser" to "getUser" on line 40
// 2. Exit insert mode - stride suggests updating the call on line 47
// -----------------------------------------------------------------------------

interface User {
  id: number;
  name: string;
  email: string;
}

const fetchUser = async (id: number): Promise<User> => {
  const response = await fetch(`/api/users/${id}`);
  return response.json();
};

export const UserProfile: React.FC<{ userId: number }> = ({ userId }) => {
  const [user, setUser] = useState<User | null>(null);

  useEffect(() => {
    fetchUser(userId).then(setUser);
  }, [userId]);

  if (!user) return <div>Loading...</div>;
  return <div>{user.name}</div>;
};


// =============================================================================
// INSERT ACTION TESTS (new functionality)
// =============================================================================

// -----------------------------------------------------------------------------
// TEST 3: Interface property insertion
// HOW TO TEST:
// 1. Add "lastName: string;" after "name: string;" in User interface (line 39)
// 2. Exit insert mode
// 3. Stride should suggest INSERTING "lastName: user.lastName" in JSX
// 4. Press Tab to accept
//
// EXPECTED: Anchor="{user.name}", Position="after", Insert=" {user.lastName}"
// -----------------------------------------------------------------------------


// -----------------------------------------------------------------------------
// TEST 4: Component prop insertion
// HOW TO TEST:
// 1. Add "disabled?: boolean;" after "onClick" in ButtonProps (line 88)
// 2. Exit insert mode
// 3. Stride should suggest INSERTING "disabled={false}" at Button usages
// 4. Press Tab to accept each insertion
//
// EXPECTED: Anchor='onClick={handleClick}', Position="after", Insert=" disabled={false}"
// -----------------------------------------------------------------------------

interface ButtonProps {
  label: string;
  onClick: () => void;
  // <- ADD "disabled?: boolean;" HERE
}

const Button: React.FC<ButtonProps> = ({ label, onClick }) => (
  <button onClick={onClick}>{label}</button>
);

const handleClick = () => console.log("clicked");

// Button usages that need disabled prop inserted
const buttons = (
  <>
    <Button label="Save" onClick={handleClick} />
    <Button label="Cancel" onClick={handleClick} />
    <Button label="Delete" onClick={handleClick} />
  </>
);


// -----------------------------------------------------------------------------
// TEST 5: JSX attribute insertion
// HOW TO TEST:
// 1. Add 'aria-label="card"' after 'className="card"' on line 117
// 2. Exit insert mode
// 3. Stride should suggest inserting aria-label in similar elements
//
// EXPECTED: Anchor='className="card"', Position="after", Insert=' aria-label="card"'
// -----------------------------------------------------------------------------

interface CardProps {
  title: string;
  content: string;
}

const Card: React.FC<CardProps> = ({ title, content }) => (
  <div className="card">
    <h3>{title}</h3>
    <p>{content}</p>
  </div>
);

const AnotherCard: React.FC<CardProps> = ({ title, content }) => (
  <div className="card">
    <h4>{title}</h4>
    <span>{content}</span>
  </div>
);


// -----------------------------------------------------------------------------
// TEST 6: Hook dependency insertion
// HOW TO TEST:
// 1. Add ", count" after "userId" in useEffect dependency array (line 51)
// 2. Exit insert mode
// 3. Stride should suggest inserting in similar dependency arrays
//
// EXPECTED: Anchor="userId", Position="after", Insert=", count"
// -----------------------------------------------------------------------------

const useFetchData = (userId: number) => {
  const [data, setData] = useState(null);

  useEffect(() => {
    fetch(`/api/${userId}`).then((r) => r.json()).then(setData);
  }, [userId]);

  return data;
};

const useOtherData = (userId: number) => {
  const [data, setData] = useState(null);

  useEffect(() => {
    fetch(`/api/other/${userId}`).then((r) => r.json()).then(setData);
  }, [userId]);

  return data;
};


// -----------------------------------------------------------------------------
// TEST 7: Object spread insertion
// HOW TO TEST:
// 1. Add "...defaultProps," before "title" in the object on line 170
// 2. Exit insert mode
// 3. Stride should suggest inserting spread in similar objects
//
// EXPECTED: Anchor="title:", Position="before", Insert="...defaultProps, "
// -----------------------------------------------------------------------------

const defaultProps = { className: "default" };

const cardProps1 = {
  title: "Card 1",
  content: "Content 1",
};

const cardProps2 = {
  title: "Card 2",
  content: "Content 2",
};


// -----------------------------------------------------------------------------
// TEST 8: CSS class insertion
// HOW TO TEST:
// 1. Add " active" after "item" in className on line 192
// 2. Exit insert mode
// 3. Stride should suggest inserting in similar classNames
//
// EXPECTED: Anchor='"item"', Position="after" (or within string)
// -----------------------------------------------------------------------------

const ListItem: React.FC<{ text: string }> = ({ text }) => (
  <li className="item">{text}</li>
);

const MenuItem: React.FC<{ text: string }> = ({ text }) => (
  <li className="item">{text}</li>
);

const NavItem: React.FC<{ text: string }> = ({ text }) => (
  <li className="item">{text}</li>
);
