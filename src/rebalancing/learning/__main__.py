from __future__ import annotations

import argparse
import json

from .diagnosis import run_diagnosis


def main() -> None:
    parser = argparse.ArgumentParser(description="Run one learning diagnosis cycle.")
    parser.add_argument("--window", type=int, default=100, help="Number of recent decisions to analyze.")
    parser.add_argument("--mode", choices=("paper", "live"), default=None, help="Optional decision mode filter.")
    args = parser.parse_args()

    result = run_diagnosis(window=args.window, mode=args.mode)
    print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
