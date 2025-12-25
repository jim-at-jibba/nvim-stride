# Demo file for testing stride.nvim with Python
# Run: :luafile demo.lua (from project root first)
# Then edit this file to test predictions

from dataclasses import dataclass
from typing import Optional
from datetime import datetime

# =============================================================================
# REPLACE ACTION TESTS (existing functionality)
# =============================================================================

# -----------------------------------------------------------------------------
# TEST 1: Variable rename propagation
# 1. Change "username" on line 18 to "user_name"
# 2. Exit insert mode - stride predicts updating other references
# 3. Press Tab to accept each suggestion
# -----------------------------------------------------------------------------

username = "alice"
user_email = f"{username}@example.com"
print(f"Hello, {username}!")
greeting = f"Welcome, {username}!"


# -----------------------------------------------------------------------------
# TEST 2: Function rename
# 1. Rename "calculate_total" to "compute_total" on line 33
# 2. Exit insert mode - stride suggests updating the call on line 39
# -----------------------------------------------------------------------------


def calculate_total(items: list[float], tax_rate: float = 0.1) -> float:
    subtotal = sum(items)
    return subtotal + (subtotal * tax_rate)


prices = [19.99, 29.99, 9.99]
total = calculate_total(prices)
print(f"Total: ${total:.2f}")


# =============================================================================
# INSERT ACTION TESTS (new functionality)
# =============================================================================

# -----------------------------------------------------------------------------
# TEST 3: Dataclass field insertion
# HOW TO TEST:
# 1. Add "age: int" after line 54 (after "email: str")
# 2. Exit insert mode
# 3. Stride should suggest INSERTING "age=25" after "email=email" on line 63
# 4. Press Tab to accept - text is inserted, not replaced
#
# EXPECTED: Anchor="email=email", Position="after", Insert=", age=25"
# -----------------------------------------------------------------------------


@dataclass
class Person:
    name: str
    email: str
    # <- ADD "age: int" HERE


def create_person(name: str, email: str) -> Person:
    return Person(name=name, email=email)


alice = create_person("Alice", "alice@example.com")
bob = create_person("Bob", "bob@example.com")


# -----------------------------------------------------------------------------
# TEST 4: Function parameter insertion
# HOW TO TEST:
# 1. Add "timeout: int = 30" parameter after "url: str" on line 79
# 2. Exit insert mode
# 3. Stride should suggest INSERTING ", timeout=30" at call sites
# 4. Press Tab to accept each insertion
#
# EXPECTED: Anchor='"https://api.example.com/users"', Position="after", Insert=", timeout=30"
# -----------------------------------------------------------------------------


def fetch_data(url: str) -> dict:
    """Fetch data from a URL."""
    return {"url": url, "data": []}


# Call sites that need the new parameter inserted
result1 = fetch_data("https://api.example.com/users")
result2 = fetch_data("https://api.example.com/posts")
result3 = fetch_data("https://api.example.com/comments")


# -----------------------------------------------------------------------------
# TEST 5: Dictionary key insertion
# HOW TO TEST:
# 1. Add '"status": "active",' after '"email": email,' on line 103
# 2. Exit insert mode
# 3. Stride should suggest inserting same key in other dicts
#
# EXPECTED: Anchor='"email": user["email"]', Position="after", Insert=', "status": "active"'
# -----------------------------------------------------------------------------


def format_user(user: dict) -> dict:
    return {
        "name": user["name"],
        "email": user["email"],
        # <- ADD '"status": "active",' HERE
    }


def format_admin(user: dict) -> dict:
    return {
        "name": user["name"],
        "email": user["email"],
    }


# -----------------------------------------------------------------------------
# TEST 6: Import insertion
# HOW TO TEST:
# 1. Add "from typing import List" after "from typing import Optional" (line 7)
# 2. Exit insert mode
# 3. Stride may suggest similar import insertions if pattern matches
# -----------------------------------------------------------------------------


# -----------------------------------------------------------------------------
# TEST 7: Decorator insertion
# HOW TO TEST:
# 1. Add "@property" decorator before "def name(self)" on line 140
# 2. Exit insert mode
# 3. Stride should suggest inserting @property before similar methods
#
# EXPECTED: Anchor="def email", Position="before", Insert="    @property\n"
# -----------------------------------------------------------------------------


class User:
    def __init__(self, name: str, email: str):
        self._name = name
        self._email = email

    def name(self) -> str:
        return self._name

    def email(self) -> str:
        return self._email


# -----------------------------------------------------------------------------
# TEST 8: List item insertion
# HOW TO TEST:
# 1. Add '"debug",' after '"warning",' on line 157
# 2. Exit insert mode
# 3. Stride should suggest inserting in similar lists
#
# EXPECTED: Anchor='"warning"', Position="after", Insert=', "debug"'
# -----------------------------------------------------------------------------

LOG_LEVELS = [
    "error",
    "warning",
    # <- ADD '"debug",' HERE
    "info",
]

ALERT_LEVELS = [
    "critical",
    "warning",
    "info",
]
