# Demo file for testing stride.nvim with Python
# Run: :luafile demo.lua (from project root first)
# Then edit this file to test predictions

from dataclasses import dataclass
from typing import Optional
from datetime import datetime

# -----------------------------------------------------------------------------
# TEST 1: Variable rename propagation
# 1. Change "user_name" to "username"
# 2. Exit insert mode - stride predicts updating other "user_name" references
# 3. Press Tab to accept
# -----------------------------------------------------------------------------

user_name = "alice"
user_email = f"{user_name}@example.com"
print(f"Hello, {user_name}!")
print(f"Email: {user_email}")


def greet_user(name: str) -> str:
    return f"Welcome, {name}!"


greeting = greet_user(user_name)


# -----------------------------------------------------------------------------
# TEST 2: Function rename
# 1. Rename "calculate_total" to "compute_total"
# 2. Exit insert mode - stride suggests updating the call below
# -----------------------------------------------------------------------------


def calculate_total(items: list[float], tax_rate: float = 0.1) -> float:
    subtotal = sum(items)
    tax = subtotal * tax_rate
    return subtotal + tax


prices = [19.99, 29.99, 9.99]
total = calculate_total(prices)
print(f"Total: ${total:.2f}")


# -----------------------------------------------------------------------------
# TEST 3: Class attribute rename
# 1. Change "is_active" to "is_enabled"
# 2. Exit insert mode - stride suggests updating usages
# -----------------------------------------------------------------------------


@dataclass
class User:
    id: int
    name: str
    email: str
    is_active: bool = True
    created_at: Optional[datetime] = None


def create_user(name: str, email: str) -> User:
    return User(
        id=1,
        name=name,
        email=email,
        is_active=True,
        created_at=datetime.now(),
    )


def deactivate_user(user: User) -> User:
    user.is_active = False
    return user


def check_user_status(user: User) -> str:
    if user.is_active:
        return "User is active"
    return "User is inactive"


# -----------------------------------------------------------------------------
# TEST 4: String constant rename
# 1. Change "error" to "failed"
# 2. Exit insert mode - stride suggests updating similar occurrences
# -----------------------------------------------------------------------------


def process_request(data: dict) -> dict:
    if not data:
        return {"status": "error", "message": "No data provided"}

    if "id" not in data:
        return {"status": "error", "message": "Missing required field: id"}

    # Process the data
    result = {"status": "success", "data": data}
    return result


# Test the function
response = process_request({})
if response["status"] == "error":
    print(f"Error: {response['message']}")
