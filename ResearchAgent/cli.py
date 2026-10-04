"""JSON-only command-line contract for the desktop app."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from .common import MODEL_LABEL, now_iso
from .workflow import run_question, run_recommendation

def main(argv=None, *, run_recommendation=run_recommendation, run_question=run_question, now_iso=now_iso) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("recommend", "ask"), default="recommend")
    parser.add_argument("--result-file", type=Path)
    parser.add_argument("--video-id")
    parser.add_argument("--question")
    args = parser.parse_args(argv)

    try:
        if args.mode == "ask":
            if not args.result_file or not args.video_id or not args.question:
                raise RuntimeError("Ask mode requires --result-file, --video-id, and --question.")
            result = run_question(args.result_file, args.video_id, args.question)
        else:
            result = run_recommendation()
        print(json.dumps(result, ensure_ascii=False))
        return 0 if result.get("status") != "error" else 1
    except Exception as exc:  # Keep stdout contract valid for the app.
        print(
            json.dumps(
                {
                    "schemaVersion": 1,
                    "generatedAt": now_iso(),
                    "model": MODEL_LABEL,
                    "status": "error",
                    "topics": [],
                    "recommendations": [],
                    "diagnostics": [str(exc)],
                },
                ensure_ascii=False,
            )
        )
        return 1
