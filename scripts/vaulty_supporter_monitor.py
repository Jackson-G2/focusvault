#!/usr/bin/env python3
"""Read-only Vaulty Supporter Edition sales monitor.

This script only performs Stripe GET requests. It never creates checkout links,
charges customers, sends messages, or mutates payment data.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import sys
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

STRIPE_API = "https://api.stripe.com/v1"
DEFAULT_PRODUCT_SLUG = "vaulty-supporter"


def utc_day_bounds(start: str, end: Optional[str]) -> tuple[int, int, str, str]:
    start_day = date.fromisoformat(start)
    end_day = date.fromisoformat(end) if end else start_day + timedelta(days=13)
    if end_day < start_day:
        raise ValueError("end date must be on or after start date")
    start_dt = datetime.combine(start_day, datetime.min.time(), tzinfo=timezone.utc)
    end_dt = datetime.combine(end_day + timedelta(days=1), datetime.min.time(), tzinfo=timezone.utc)
    return int(start_dt.timestamp()), int(end_dt.timestamp()), start_day.isoformat(), end_day.isoformat()


def money_aud(cents: int) -> str:
    return f"{Decimal(cents) / Decimal(100):.2f}"


def stripe_get(api_key: str, path: str, params: Dict[str, Any]) -> Dict[str, Any]:
    query = urlencode(params, doseq=True)
    request = Request(
        f"{STRIPE_API}{path}?{query}",
        headers={
            "Authorization": "Basic " + base64.b64encode(f"{api_key}:".encode()).decode(),
            "Accept": "application/json",
            "User-Agent": "VaultySupporterMonitor/0.1",
        },
        method="GET",
    )
    try:
        with urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode("utf-8"))
    except HTTPError as error:
        body = error.read().decode("utf-8", "replace")
        raise RuntimeError(f"Stripe GET {path} failed with HTTP {error.code}: {body[:500]}") from error
    except URLError as error:
        raise RuntimeError(f"Stripe GET {path} failed: {error.reason}") from error


def list_all(api_key: str, path: str, params: Dict[str, Any]) -> List[Dict[str, Any]]:
    records: List[Dict[str, Any]] = []
    cursor: Optional[str] = None
    while True:
        page_params = dict(params)
        page_params["limit"] = 100
        if cursor:
            page_params["starting_after"] = cursor
        page = stripe_get(api_key, path, page_params)
        page_records = page.get("data", [])
        records.extend(page_records)
        if not page.get("has_more") or not page_records:
            return records
        cursor = page_records[-1].get("id")
        if not cursor:
            return records


def load_fixture(path: Path) -> tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    return payload.get("checkout_sessions", []), payload.get("refunds", [])


def session_product_matches(
    session: Dict[str, Any],
    product_slug: str,
    price_id: Optional[str],
) -> bool:
    metadata = session.get("metadata") or {}
    if metadata.get("product") == product_slug or metadata.get("offer") == product_slug:
        return True
    if session.get("client_reference_id") == product_slug:
        return True
    if price_id:
        line_items = (session.get("line_items") or {}).get("data", [])
        for item in line_items:
            price = item.get("price") or {}
            if price.get("id") == price_id:
                return True
    return False


def summarize(
    sessions: Iterable[Dict[str, Any]],
    refunds: Iterable[Dict[str, Any]],
    *,
    product_slug: str = DEFAULT_PRODUCT_SLUG,
    price_id: Optional[str] = None,
    window_start: str = "fixture",
    window_end: str = "fixture",
) -> Dict[str, Any]:
    matched: Dict[str, Dict[str, Any]] = {}
    for session in sessions:
        session_id = session.get("id")
        if not session_id or session_id in matched:
            continue
        if session.get("status") != "complete" or session.get("payment_status") != "paid":
            continue
        if str(session.get("currency", "aud")).lower() != "aud":
            continue
        if not session_product_matches(session, product_slug, price_id):
            continue
        matched[session_id] = session

    orders = []
    for session in matched.values():
        amount = int(session.get("amount_total") or 0)
        orders.append(
            {
                "checkout_session_id": session["id"],
                "created": int(session.get("created") or 0),
                "amount_aud": money_aud(amount),
                "payment_intent": session.get("payment_intent"),
            }
        )
    orders.sort(key=lambda item: (item["created"], item["checkout_session_id"]))

    payment_intents = {order["payment_intent"] for order in orders if order["payment_intent"]}
    successful_refunds = []
    seen_refunds = set()
    for refund in refunds:
        refund_id = refund.get("id")
        if not refund_id or refund_id in seen_refunds:
            continue
        if refund.get("status") not in {None, "succeeded"}:
            continue
        if refund.get("payment_intent") not in payment_intents:
            continue
        seen_refunds.add(refund_id)
        successful_refunds.append(
            {
                "refund_id": refund_id,
                "payment_intent": refund.get("payment_intent"),
                "amount_aud": money_aud(int(refund.get("amount") or 0)),
                "created": int(refund.get("created") or 0),
            }
        )
    successful_refunds.sort(key=lambda item: (item["created"], item["refund_id"]))

    gross_cents = sum(int(session.get("amount_total") or 0) for session in matched.values())
    refunded_cents = sum(int(refund.get("amount") or 0) for refund in refunds if refund.get("id") in seen_refunds)
    return {
        "status": "read-only",
        "product": product_slug,
        "window": {"start": window_start, "end": window_end},
        "order_count": len(orders),
        "gross_aud": money_aud(gross_cents),
        "refund_count": len(successful_refunds),
        "refunded_aud": money_aud(refunded_cents),
        "net_aud": money_aud(gross_cents - refunded_cents),
        "orders": orders,
        "refunds": successful_refunds,
    }


def live_report(
    api_key: str,
    start: str,
    end: Optional[str],
    *,
    product_slug: str,
    price_id: Optional[str],
) -> Dict[str, Any]:
    start_ts, end_ts, start_label, end_label = utc_day_bounds(start, end)
    session_params: Dict[str, Any] = {
        "created[gte]": start_ts,
        "created[lt]": end_ts,
        "expand[]": "data.line_items.data.price",
    }
    sessions = list_all(api_key, "/checkout/sessions", session_params)
    refunds = list_all(api_key, "/refunds", {"created[gte]": start_ts, "created[lt]": end_ts})
    return summarize(
        sessions,
        refunds,
        product_slug=product_slug,
        price_id=price_id,
        window_start=start_label,
        window_end=end_label,
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Read-only Vaulty supporter sales monitor")
    parser.add_argument("--start", help="UTC calendar day, YYYY-MM-DD")
    parser.add_argument("--end", help="UTC calendar day, inclusive; defaults to 14 days from start")
    parser.add_argument("--price-id", default=os.environ.get("VAULTY_STRIPE_PRICE_ID"))
    parser.add_argument("--product", default=os.environ.get("VAULTY_STRIPE_PRODUCT", DEFAULT_PRODUCT_SLUG))
    parser.add_argument("--fixture", type=Path, help="Use a local JSON fixture instead of Stripe")
    args = parser.parse_args()

    try:
        if args.fixture:
            sessions, refunds = load_fixture(args.fixture)
            report = summarize(
                sessions,
                refunds,
                product_slug=args.product,
                price_id=args.price_id,
            )
        else:
            if not args.start:
                parser.error("--start is required for a live read-only check")
            api_key = os.environ.get("VAULTY_STRIPE_SECRET_KEY")
            if not api_key:
                parser.error("VAULTY_STRIPE_SECRET_KEY is required for a live read-only check")
            report = live_report(
                api_key,
                args.start,
                args.end,
                product_slug=args.product,
                price_id=args.price_id,
            )
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
