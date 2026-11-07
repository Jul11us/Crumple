#!/usr/bin/env python3
"""Inspect actual PE headers and create SHA-256 checksums. Does not claim Windows runtime testing."""
from pathlib import Path
import hashlib
import struct
import sys

directory = Path(sys.argv[1]).resolve()
executables = sorted(directory.glob("Crumple-*.exe"))
if not executables:
    raise SystemExit("No packaged exe found")
checksums = []
for executable in executables:
    data = executable.read_bytes()
    assert data[:2] == b"MZ", f"Missing DOS header: {executable.name}"
    offset = struct.unpack_from("<I", data, 0x3C)[0]
    assert data[offset:offset+4] == b"PE\0\0", f"Missing PE header: {executable.name}"
    machine, sections = struct.unpack_from("<HH", data, offset+4)
    subsystem = struct.unpack_from("<H", data, offset+24+68)[0]
    assert subsystem == 2, f"Not a Windows GUI executable: {executable.name}"
    expected = 0x14C if "Setup" in executable.name else 0xAA64 if "arm64" in executable.name else 0x8664
    assert machine == expected, f"Wrong CPU architecture: {executable.name}"
    assert len(data) > 10_000_000, f"Runtime appears missing: {executable.name}"
    checksums.append(f"{hashlib.sha256(data).hexdigest()}  {executable.name}")
    print(f"Verified {executable.name}: {len(data):,} bytes, GUI PE, machine={machine:#x}, {sections} sections")
(directory / "SHA256SUMS.txt").write_text("\n".join(checksums) + "\n", encoding="ascii")
