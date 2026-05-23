#!/usr/bin/env python3
"""
cost_api_probe.py - exploratory CLI for the Anthropic Usage & Cost API.

Reads admin key from ~/.openclaw/workspace/secrets/anthropic-admin-key.txt by default.
Override with --key or ANTHROPIC_ADMIN_KEY env var.

Examples:
  python3 cost_api_probe.py --whoami
  python3 cost_api_probe.py --mtd
  python3 cost_api_probe.py --range 2026-05-01 2026-05-15
  python3 cost_api_probe.py --mtd --json
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterator

DEFAULT_KEY_PATH = Path.home() / ".openclaw/workspace/secrets/anthropic-admin-key.txt"
API_BASE = "https://api.anthropic.com"
API_VERSION = "2023-06-01"


def load_key(args: argparse.Namespace) -> str:
    if args.key:
        return args.key.strip()
    env_key = os.environ.get("ANTHROPIC_ADMIN_KEY")
    if env_key:
        return env_key.strip()
    path = Path(args.key_path).expanduser()
    if not path.exists():
        sys.exit(
            f"admin key not found. tried: --key, $ANTHROPIC_ADMIN_KEY, {path}"
        )
    return path.read_text(encoding="utf-8").strip()


def api_get(path: str, key: str, params: dict[str, str] | None = None) -> dict:
    url = API_BASE + path
    if params:
        url += "?" + "&".join(f"{k}={v}" for k, v in params.items())
    req = urllib.request.Request(
        url,
        headers={
            "x-api-key": key,
            "anthropic-version": API_VERSION,
            "accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        sys.exit(f"HTTP {e.code} {e.reason}: {body}")


def iter_cost_report(key: str, starting_at: str, ending_at: str) -> Iterator[dict]:
    params = {"starting_at": starting_at, "ending_at": ending_at}
    while True:
        page = api_get("/v1/organizations/cost_report", key, params)
        for bucket in page.get("data", []):
            yield bucket
        if not page.get("has_more") or not page.get("next_page"):
            return
        params = {
            "starting_at": starting_at,
            "ending_at": ending_at,
            "page": page["next_page"],
        }


@dataclass
class CostSummary:
    cents: float
    bucket_count: int
    row_count: int

    @property
    def dollars(self) -> float:
        return self.cents / 100.0


def summarize(buckets: Iterator[dict]) -> CostSummary:
    total_cents = 0.0
    bucket_count = 0
    row_count = 0
    for bucket in buckets:
        bucket_count += 1
        for r in bucket.get("results", []):
            row_count += 1
            total_cents += float(r.get("amount", 0))
    return CostSummary(cents=total_cents, bucket_count=bucket_count, row_count=row_count)


def utc_iso(d: datetime) -> str:
    return d.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def mtd_range() -> tuple[str, str]:
    now = datetime.now(timezone.utc)
    start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    return utc_iso(start), utc_iso(now)


def cmd_whoami(key: str, args: argparse.Namespace) -> None:
    data = api_get("/v1/organizations/me", key)
    if args.json:
        print(json.dumps(data, indent=2))
    else:
        print(f"Org: {data.get('name')!r} ({data.get('id')})")


def cmd_cost(key: str, start: str, end: str, args: argparse.Namespace) -> None:
    print(f"# cost_report  range: {start}  →  {end}", file=sys.stderr)
    summary = summarize(iter_cost_report(key, start, end))
    payload = {
        "starting_at": start,
        "ending_at": end,
        "total_cents": summary.cents,
        "total_usd": round(summary.dollars, 4),
        "buckets": summary.bucket_count,
        "rows": summary.row_count,
    }
    if args.json:
        print(json.dumps(payload, indent=2))
    else:
        print(f"Buckets: {summary.bucket_count}")
        print(f"Rows:    {summary.row_count}")
        print(f"Cents:   {summary.cents:,.4f}")
        print(f"USD:     ${summary.dollars:,.2f}")


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--key", help="admin api key (overrides file & env)")
    p.add_argument("--key-path", default=str(DEFAULT_KEY_PATH), help="path to admin key file")
    p.add_argument("--json", action="store_true", help="output JSON instead of pretty text")

    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("--whoami", action="store_true", help="print org identity and exit")
    g.add_argument("--mtd", action="store_true", help="month-to-date cost summary (UTC month)")
    g.add_argument(
        "--range",
        nargs=2,
        metavar=("START", "END"),
        help="cost summary for a custom range (YYYY-MM-DD, treated as UTC midnight)",
    )
    return p.parse_args()


def main() -> None:
    args = parse_args()
    key = load_key(args)
    if args.whoami:
        cmd_whoami(key, args)
    elif args.mtd:
        start, end = mtd_range()
        cmd_cost(key, start, end, args)
    elif args.range:
        start_d, end_d = args.range
        start = f"{start_d}T00:00:00Z"
        end = f"{end_d}T00:00:00Z"
        cmd_cost(key, start, end, args)


if __name__ == "__main__":
    main()
