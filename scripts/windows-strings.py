#!/usr/bin/env python3
"""Builds the Windows app's English strings from Localization/en.py (shared with the Mac version)
and Localization/en_windows.py, and fails if any Chinese text in the C# sources has no English."""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "Localization"))
from en import EN  # noqa: E402
from en_windows import WINDOWS_EN  # noqa: E402

strings = {**EN, **WINDOWS_EN}
source = ROOT / "Windows" / "Crumple.Desktop"
keys = set()
for path in source.rglob("*.cs"):
    if "/obj/" in str(path) or "/bin/" in str(path):
        continue
    text = path.read_text(encoding="utf-8")
    for match in re.finditer(r'\bL\(\s*"((?:[^"\\]|\\.)*)"', text):
        keys.add(json.loads('"' + match.group(1) + '"'))
missing = sorted(k for k in keys if re.search(r"[㐀-鿿]", k) and k not in strings)
if missing:
    print("Missing English translations (add them to Localization/en_windows.py):")
    for key in missing:
        print(repr(key))
    sys.exit(1)
out = source / "Assets" / "en.json"
used = {k: strings[k] for k in sorted(keys) if k in strings}
out.write_text(json.dumps(used, ensure_ascii=False, indent=0, sort_keys=True) + "\n", encoding="utf-8")
print(f"Wrote {len(used)} English strings to {out.relative_to(ROOT)}")
