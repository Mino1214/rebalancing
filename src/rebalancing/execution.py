from __future__ import annotations

import argparse
import json

from .status import execute_runtime_orders


def main() -> None:
    parser = argparse.ArgumentParser(description="Execute the current rebalance decision against Binance.")
    parser.add_argument(
        "--live",
        action="store_true",
        help="Actually submit Binance orders. Requires BINANCE_LIVE_TRADING=true and BINANCE_ENABLE_ORDERS=true.",
    )
    args = parser.parse_args()

    payload = execute_runtime_orders(live=args.live)
    print(json.dumps(payload, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
