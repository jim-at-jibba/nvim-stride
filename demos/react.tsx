// Demo file for testing stride.nvim with React/TSX
// Run: :luafile demo.lua (from project root first)
// Then edit this file to test predictions

import React, { useState, useEffect } from "react";

// -----------------------------------------------------------------------------
// TEST 1: Variable rename propagation
// 1. Change "count" to "counter" on the useState line
// 2. Exit insert mode - stride predicts updating other "count" references
// 3. Press Tab to accept
// -----------------------------------------------------------------------------

interface ButtonProps {
  label: string;
  onClick: () => void;
}

const Button: React.FC<ButtonProps> = ({ label, onClick }) => {
  return (
    <button className="btn" onClick={onClick}>
      {label}
    </button>
  );
};

export const Counter: React.FC = () => {
  const [count, setCount] = useState(0);

  const increment = () => {
    setCount(count + 1);
  };

  const decrement = () => {
    setCount(count - 1);
  };

  return (
    <div className="counter">
      <h2>Count: {count}</h2>
      <Button label="+" onClick={increment} />
      <Button label="-" onClick={decrement} />
    </div>
  );
};

// -----------------------------------------------------------------------------
// TEST 2: Function rename
// 1. Rename "fetchUser" to "getUser"
// 2. Exit insert mode - stride suggests updating the call below
// -----------------------------------------------------------------------------

interface User {
  id: number;
  firstName: string;
  email: string;
}

const fetchUser = async (id: number): Promise<User> => {
  const response = await fetch(`/api/users/${id}`);
  return response.json();
};

export const UserProfile: React.FC<{ userId: number }> = ({ userId }) => {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchUser(userId).then((data) => {
      setUser(data);
      setLoading(false);
    });
  }, [userId]);

  if (loading) return <div>Loading...</div>;
  if (!user) return <div>User not found</div>;

  return (
    <div className="profile">
      <h1>{user.name}</h1>
      <p>{user.email}</p>
    </div>
  );
};

// -----------------------------------------------------------------------------
// TEST 3: Component prop rename
// 1. Change "isActive" to "isEnabled" in the interface
// 2. Exit insert mode - stride suggests updating usages
// -----------------------------------------------------------------------------

interface ToggleProps {
  isActive: boolean;
  onToggle: () => void;
}

const Toggle: React.FC<ToggleProps> = ({ isActive, onToggle }) => {
  return (
    <div className={isActive ? "toggle-on" : "toggle-off"} onClick={onToggle}>
      {isActive ? "ON" : "OFF"}
    </div>
  );
};

export const Settings: React.FC = () => {
  const [darkMode, setDarkMode] = useState(false);

  return (
    <div>
      <h3>Dark Mode</h3>
      <Toggle isActive={darkMode} onToggle={() => setDarkMode(!darkMode)} />
    </div>
  );
};
