#!/usr/bin/env python3
"""SkinXAI <-> Capital One Nessie: purchase history for Claude's order tool.

Nessie (http://nessieisreal.com) is Capital One's mock banking API. We store the demo
person's purchases in it and read them back, then join each purchase with our own product
catalog (products.json) to add ingredient lists, which Nessie does not have.

Status: built and runnable, NOT wired into the live iPhone demo yet. The app still reads
its bundled demo orders.

Usage (standard library only, Python 3.9+):
    export NESSIE_KEY=...            # from nessieisreal.com (log in with GitHub)
    python3 nessie.py seed           # create Douglas, his account, Amazon, and 30 purchases
    python3 nessie.py orders         # print order history in the shape of Claude's tool
    python3 nessie.py orders --days 30
    python3 nessie.py seed --dry-run # show the requests without sending them
"""
import argparse
import datetime as dt
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

BASE = os.environ.get("NESSIE_BASE", "https://prod-api.nessieisreal.com")
HERE = Path(__file__).resolve().parent
STATE = HERE / ".nessie-state.json"  # ids created by `seed` (not committed)


def call(method, path, body=None, dry=False):
    key = os.environ.get("NESSIE_KEY")
    if not key and not dry:
        sys.exit("Set NESSIE_KEY first (log in at nessieisreal.com with GitHub to get one).")
    url = f"{BASE}{path}?{urllib.parse.urlencode({'key': key or 'DRY_RUN'})}"
    if dry:
        print(method, f"{BASE}{path}", json.dumps(body) if body else "")
        return {"objectCreated": {"_id": f"dry-{path.strip('/').replace('/', '-')}"}}
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return json.loads(r.read() or b"null")
    except urllib.error.HTTPError as e:
        sys.exit(f"Nessie {method} {path} failed: {e.code} {e.read()[:300]!r}")


def load(name):
    return json.loads((HERE / name).read_text())


def seed(dry=False):
    demo = load("demo_orders.json")
    # Keep the story's dates relative to today, like the app does.
    shift = dt.date.today() - dt.date.fromisoformat(demo["anchor_date"]) - dt.timedelta(days=2)
    customer = call("POST", "/customers", {
        "first_name": "Douglas", "last_name": "Demo",
        "address": {"street_number": "2440", "street_name": "Lombard St", "city": "San Francisco",
                    "state": "CA", "zip": "94123"},
    }, dry)["objectCreated"]["_id"]
    account = call("POST", f"/customers/{customer}/accounts", {
        "type": "Credit Card", "nickname": "SkinXAI demo card", "rewards": 0, "balance": 0,
    }, dry)["objectCreated"]["_id"]
    merchant = call("POST", "/merchants", {
        "name": "Amazon", "category": "online shopping",
        "address": {"street_number": "410", "street_name": "Terry Ave N", "city": "Seattle",
                    "state": "WA", "zip": "98109"},
        "geocode": {"lat": 47.6223, "lng": -122.3366},
    }, dry)["objectCreated"]["_id"]
    for o in demo["orders"]:
        day = dt.date.fromisoformat(o["date"]) + shift
        call("POST", f"/accounts/{account}/purchases", {
            "merchant_id": merchant, "medium": "balance", "purchase_date": day.isoformat(),
            "amount": o["amount"], "status": "completed", "description": o["item"],
        }, dry)
    state = {"customer_id": customer, "account_id": account, "merchant_id": merchant}
    if not dry:
        STATE.write_text(json.dumps(state, indent=2))
    print(f"Seeded {len(demo['orders'])} purchases.", json.dumps(state))


def orders(days=120):
    """Purchases from Nessie, joined with our catalog: the same shape as Claude's order_history tool."""
    if not STATE.exists():
        sys.exit("Run `python3 nessie.py seed` first.")
    state = json.loads(STATE.read_text())
    catalog = load("products.json")["products"]
    since = dt.date.today() - dt.timedelta(days=days)
    rows = call("GET", f"/accounts/{state['account_id']}/purchases") or []
    rows = sorted(rows, key=lambda r: r["purchase_date"])
    seen, out = set(), []
    for r in rows:
        item = r.get("description", "")
        if dt.date.fromisoformat(r["purchase_date"]) < since:
            seen.add(item)  # older purchases only count for "bought before"
            continue
        product = catalog.get(item, {})
        entry = {"date": r["purchase_date"], "item": item,
                 "category": product.get("category", "unknown"),
                 "bought_before": item in seen, "amount": r.get("amount")}
        for field in ("ingredients", "material"):
            if field in product:
                entry[field] = product[field]
        out.append(entry)
        seen.add(item)
    return {"source": "Capital One Nessie (purchases) + SkinXAI product catalog (ingredients)",
            "orders": out}


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("command", choices=["seed", "orders"])
    p.add_argument("--days", type=int, default=120)
    p.add_argument("--dry-run", action="store_true")
    a = p.parse_args()
    if a.command == "seed":
        seed(a.dry_run)
    else:
        print(json.dumps(orders(a.days), indent=2))
