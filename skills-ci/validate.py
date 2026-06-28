#!/usr/bin/env python3
"""
Pre-merge validator for Agent Skills (SKILL.md) in this repo.

Shifts OpenClaw's "test before prod" beat left into CI: this runs on every PR so
a structurally-broken, oversized, or risky skill cannot be merged (and therefore
cannot be pulled to the live agent). It is deterministic and needs no secrets.

What it CHECKS (deterministic, blocks merge on error):
  - SKILL.md has valid YAML frontmatter with required `name` + `description`
  - `name` is unique across skills
  - body is non-empty; SKILL.md size within OpenClaw's limits
  - no hardcoded secrets in skill files

What it WARNS on (reported, does not block):
  - `name` != directory name
  - description too short/long
  - risky instruction patterns (curl|bash, "ignore previous instructions",
    attempts to disable sandbox/approvals)

What it does NOT do: prove the skill behaves correctly. LLM behavior is
non-deterministic — that still needs the staging/enable beat on the box. This
raises the floor; it doesn't guarantee quality.

Usage:  python3 skills-ci/validate.py [repo_root]
Exit:   0 = ok (warnings allowed), 1 = at least one error
"""

from __future__ import annotations
import glob
import os
import re
import sys

import yaml

# OpenClaw documents a 40,000-byte ceiling for skill proposal bodies; use it as
# a hard cap and warn well before it.
MAX_SKILL_BYTES = 40_000
WARN_SKILL_BYTES = 20_000
MIN_DESC = 40
MAX_DESC = 2_000
MIN_BODY = 80

SECRET_PATTERNS = [
    (re.compile(r"sk-ant-(?!x{4})[A-Za-z0-9_\-]{20,}"), "Anthropic API key"),
    (re.compile(r"AKIA[0-9A-Z]{16}"), "AWS access key id"),
    (re.compile(r"-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----"), "private key"),
    (re.compile(r"ghp_[A-Za-z0-9]{36}"), "GitHub token"),
    (re.compile(r"xox[baprs]-[A-Za-z0-9-]{10,}"), "Slack token"),
]

RISKY_PATTERNS = [
    (re.compile(r"curl[^\n|]*\|\s*(?:sudo\s+)?(?:ba)?sh", re.I), "pipe-to-shell (curl | sh)"),
    (re.compile(r"ignore (?:all )?(?:previous|prior|above) instructions", re.I), "prompt-injection phrasing"),
    (re.compile(r"disable\s+(?:the\s+)?(?:sandbox|approvals?|exec[\s_-]?approvals?)", re.I), "asks to disable sandbox/approvals"),
    (re.compile(r"\b(?:rm\s+-rf\s+/|mkfs|:\(\)\s*\{)", re.I), "destructive shell"),
]


class Report:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def error(self, where: str, msg: str) -> None:
        self.errors.append(f"{where}: {msg}")

    def warn(self, where: str, msg: str) -> None:
        self.warnings.append(f"{where}: {msg}")


def split_frontmatter(text: str):
    """Return (frontmatter_str, body_str) or (None, None) if no frontmatter."""
    if not text.startswith("---"):
        return None, None
    # Match leading --- ... --- block.
    m = re.match(r"^---\s*\n(.*?)\n---\s*\n?(.*)$", text, re.S)
    if not m:
        return None, None
    return m.group(1), m.group(2)


def validate_skill(skill_md: str, rep: Report, seen_names: dict) -> None:
    d = os.path.dirname(skill_md)
    dirname = os.path.basename(d)
    where = os.path.relpath(skill_md)

    raw = open(skill_md, "rb").read()
    size = len(raw)
    if size > MAX_SKILL_BYTES:
        rep.error(where, f"SKILL.md is {size} bytes (> {MAX_SKILL_BYTES} limit)")
    elif size > WARN_SKILL_BYTES:
        rep.warn(where, f"SKILL.md is {size} bytes (large; consider trimming)")

    text = raw.decode("utf-8", errors="replace").replace("\r\n", "\n")
    fm_str, body = split_frontmatter(text)
    if fm_str is None:
        rep.error(where, "missing or malformed YAML frontmatter (--- ... ---)")
        return

    try:
        fm = yaml.safe_load(fm_str)
    except yaml.YAMLError as e:
        rep.error(where, f"frontmatter is not valid YAML: {e}")
        return
    if not isinstance(fm, dict):
        rep.error(where, "frontmatter did not parse to a mapping")
        return

    name = fm.get("name")
    desc = fm.get("description")

    if not isinstance(name, str) or not name.strip():
        rep.error(where, "missing/empty required field: name")
    else:
        name = name.strip()
        if name in seen_names:
            rep.error(where, f"duplicate skill name '{name}' (also in {seen_names[name]})")
        else:
            seen_names[name] = where
        if name != dirname:
            rep.warn(where, f"name '{name}' != directory '{dirname}' (allowed, but unusual)")

    if not isinstance(desc, str) or not desc.strip():
        rep.error(where, "missing/empty required field: description")
    else:
        dlen = len(desc.strip())
        if dlen < MIN_DESC:
            rep.warn(where, f"description is short ({dlen} chars) — triggers may be vague")
        elif dlen > MAX_DESC:
            rep.warn(where, f"description is long ({dlen} chars)")

    if not body or len(body.strip()) < MIN_BODY:
        rep.error(where, f"skill body is empty or too short (< {MIN_BODY} chars)")

    # Scan all files in the skill dir for secrets + risky patterns.
    for path in glob.glob(os.path.join(d, "**", "*"), recursive=True):
        if not os.path.isfile(path) or path.endswith(".skill"):
            continue
        try:
            content = open(path, "r", encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        rel = os.path.relpath(path)
        for pat, label in SECRET_PATTERNS:
            if pat.search(content):
                rep.error(rel, f"possible hardcoded secret ({label})")
        for pat, label in RISKY_PATTERNS:
            if pat.search(content):
                rep.warn(rel, f"risky pattern: {label}")


def main() -> int:
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    skills = sorted(glob.glob(os.path.join(root, "*", "SKILL.md")))
    if not skills:
        print("No SKILL.md files found — nothing to validate.")
        return 0

    rep = Report()
    seen_names: dict[str, str] = {}
    for s in skills:
        validate_skill(s, rep, seen_names)

    print(f"Validated {len(skills)} skill(s): {', '.join(os.path.basename(os.path.dirname(s)) for s in skills)}\n")
    for w in rep.warnings:
        print(f"  WARN  {w}")
    for e in rep.errors:
        print(f"  ERROR {e}")

    if rep.errors:
        print(f"\nFAILED: {len(rep.errors)} error(s), {len(rep.warnings)} warning(s).")
        return 1
    print(f"\nOK: 0 errors, {len(rep.warnings)} warning(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
