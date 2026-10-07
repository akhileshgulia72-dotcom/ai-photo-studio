"""Pure plan and purchase policy shared with the backend's unit tests."""

from __future__ import annotations

import hashlib

PLAY_PRODUCTS = {
    "vyro_creator_150": {"credits": 150, "plan": "creator"},
    "vyro_pro_500": {"credits": 500, "plan": "pro"},
}


def account_binding(uid: str) -> str:
    return hashlib.sha256(f"vyro:{uid}".encode("utf-8")).hexdigest()


def updated_plan(current_plan: str, purchased_plan: str) -> str:
    rank = {"free": 0, "creator": 1, "pro": 2, "premium": 2}
    current = (current_plan or "free").lower()
    purchased = purchased_plan.lower()
    return current if rank.get(current, 0) > rank.get(purchased, 0) else purchased


def generation_quality(plan: str) -> str:
    return "high" if str(plan or "free").lower() in {"pro", "premium"} else "medium"
