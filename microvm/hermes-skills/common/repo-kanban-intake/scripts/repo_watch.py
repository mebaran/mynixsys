#!/usr/bin/env python3
"""Poll a request directory and enqueue Hermes Kanban planning tasks.

This intentionally uses only the Python standard library. It watches for
`*.md` files, creates one planning task per file, then renames the file to
`.queued` on success.
"""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import time


def run(argv: list[str]) -> None:
    subprocess.run(argv, check=True)


def stable_key(path: Path, body: str) -> str:
    digest = hashlib.sha256()
    digest.update(str(path.resolve()).encode())
    digest.update(b"\0")
    digest.update(body.encode())
    return digest.hexdigest()[:32]


def enqueue(path: Path, args: argparse.Namespace) -> None:
    body = path.read_text(encoding="utf-8")
    first = next((line.strip("# ").strip() for line in body.splitlines() if line.strip()), path.stem)
    title = f"Plan: {first[:96]}"
    key = stable_key(path, body)
    cmd = [
        "hermes",
        "kanban",
        "create",
        title,
        "--body",
        f"Request file: {path}\n\n{body}",
        "--workspace",
        f"dir:{args.repo}",
        "--idempotency-key",
        key,
        "--skill",
        "repo-kanban-intake",
        "--skill",
        "one-three-one-rule",
    ]
    for skill in args.skill:
        cmd.extend(["--skill", skill])
    if args.assignee:
        cmd.extend(["--assignee", args.assignee])
    run(cmd)
    path.rename(path.with_suffix(path.suffix + ".queued"))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True, help="Repository/workspace path for Kanban tasks")
    parser.add_argument("--requests-dir", default=".hermes-requests", help="Directory containing Markdown requests")
    parser.add_argument("--assignee", default="", help="Optional Hermes profile assignee")
    parser.add_argument("--skill", action="append", default=[], help="Additional skill to pin on planning tasks")
    parser.add_argument("--interval", type=float, default=15.0, help="Polling interval in seconds")
    parser.add_argument("--once", action="store_true", help="Run one scan and exit")
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    args.repo = str(repo)
    request_dir = Path(args.requests_dir)
    if not request_dir.is_absolute():
        request_dir = repo / request_dir
    request_dir.mkdir(parents=True, exist_ok=True)

    while True:
      for path in sorted(request_dir.glob("*.md")):
          try:
              enqueue(path, args)
          except Exception as exc:
              print(f"failed to enqueue {path}: {exc}", file=sys.stderr)
      if args.once:
          return 0
      time.sleep(args.interval)


if __name__ == "__main__":
    raise SystemExit(main())
