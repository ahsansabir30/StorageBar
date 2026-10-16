#!/usr/bin/env python3
"""Fails if any reachable git object (all branches, tags and history) looks like a credential.

Read-only. Prints the pattern name, the file path and the object id, never the matched text, so the
output itself can never leak a secret. Run locally with `scripts/scan-secrets.py`; CI runs it on the
full history. GitHub secret scanning and push protection are an additional, independent layer.

Patterns are assembled from fragments so this file does not match its own rules.
"""
import re
import subprocess
import sys

PATTERNS = {
    "GitHub token": re.compile(r"\b(?:gh[pousr]" + r"_)[A-Za-z0-9]{20,}|github" + r"_pat_[A-Za-z0-9_]{20,}"),
    "private key block": re.compile("-----" + "BEGIN [A-Z ]*PRIVATE " + "KEY-----"),
    "AWS access key": re.compile(r"\bAK" + r"IA[0-9A-Z]{16}\b"),
    "Slack token": re.compile(r"\bxox" + r"[baprs]-[A-Za-z0-9-]{10,}"),
    "API key (sk- style)": re.compile(r"\bsk" + r"-(?:ant-)?[A-Za-z0-9_-]{20,}"),
    "Google API key": re.compile(r"\bAI" + r"za[0-9A-Za-z_-]{30,}"),
    "JWT": re.compile(r"\bey" + r"J[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"),
}
SENSITIVE_NAMES = re.compile(r"\.(p12|p8|pfx|pem|key|cer|mobileprovision)$|(^|/)\.env(\.|$)|(^|/)id_(rsa|ed25519)$", re.I)


def git(*args: str) -> bytes:
    return subprocess.run(["git", *args], check=True, capture_output=True).stdout


def main() -> int:
    listing = git("rev-list", "--objects", "--all").decode("utf-8", "ignore").splitlines()
    names: dict[str, str] = {}
    for line in listing:
        parts = line.split(" ", 1)
        names[parts[0]] = parts[1] if len(parts) > 1 else ""
    if not names:
        print("no git objects found")
        return 1

    proc = subprocess.Popen(["git", "cat-file", "--batch"], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    out, _ = proc.communicate(("\n".join(names) + "\n").encode())

    problems: list[str] = []
    seen = 0
    i = 0
    while i < len(out):
        nl = out.index(b"\n", i)
        header = out[i:nl].split()
        if len(header) < 3:
            break
        sha, kind, size = header[0].decode(), header[1].decode(), int(header[2])
        body = out[nl + 1 : nl + 1 + size]
        i = nl + 1 + size + 1
        seen += 1
        path = names.get(sha, "")
        if kind == "blob" and SENSITIVE_NAMES.search(path):
            problems.append(f"sensitive file name tracked: {path} (object {sha[:10]})")
        text = body.decode("utf-8", "ignore")
        for label, rx in PATTERNS.items():
            if rx.search(text):
                where = path or f"{kind} object"
                problems.append(f"{label} in {where} (object {sha[:10]})")

    print(f"scanned {seen} git objects across all refs")
    if problems:
        print("POSSIBLE SECRETS FOUND (values are not printed):")
        for p in sorted(set(problems)):
            print(" -", p)
        return 1
    print("OK: no credential patterns or sensitive file names found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
