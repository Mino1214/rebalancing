from __future__ import annotations

import argparse
import json

from .diagnosis import run_diagnosis
from .loop import run_learning_cycle, run_scheduler
from .params import activate_bot_params_version, apply_evaluation_suggestions


def main() -> None:
    parser = argparse.ArgumentParser(description="Run one learning diagnosis cycle.")
    parser.add_argument("--window", type=int, default=100, help="Number of recent decisions to analyze.")
    parser.add_argument("--mode", choices=("paper", "live"), default=None, help="Optional decision mode filter.")
    parser.add_argument("--apply-evaluation", type=int, default=None, help="Stage/apply param suggestions from an evaluation.")
    parser.add_argument("--activate-version", type=int, default=None, help="Activate a staged bot_params version.")
    parser.add_argument("--policy", choices=("approve", "auto"), default=None, help="Param apply policy override.")
    parser.add_argument("--cycle", action="store_true", help="Run one full diagnosis/apply/stage learning cycle.")
    parser.add_argument("--scheduler", action="store_true", help="Run the learning cycle repeatedly.")
    parser.add_argument("--interval-seconds", type=int, default=None, help="Scheduler interval override.")
    args = parser.parse_args()

    if args.activate_version is not None:
        result = activate_bot_params_version(args.activate_version)
    elif args.apply_evaluation is not None:
        result = apply_evaluation_suggestions(args.apply_evaluation, policy=args.policy)
    elif args.scheduler:
        run_scheduler(window=args.window, mode=args.mode, interval_seconds=args.interval_seconds)
        return
    elif args.cycle:
        result = run_learning_cycle(window=args.window, mode=args.mode, trigger="manual", apply_policy=args.policy)
    else:
        result = run_diagnosis(window=args.window, mode=args.mode)

    print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
