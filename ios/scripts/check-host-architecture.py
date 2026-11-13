#!/usr/bin/env python3
"""Reject mixed host/target ICU makefiles before a long native compilation."""
import platform
import re
import sys
from pathlib import Path


def check(folder: Path, architecture: str) -> None:
    required = ["icutools", "genccode", "icupkg", "gen-regexp-special-case"]
    for name in required:
        matches = list(folder.rglob(name + ".host.mk"))
        if len(matches) != 1:
            raise ValueError(f"Expected one {name}.host.mk; found {len(matches)}")
        text = matches[0].read_text().replace("\\\n", " ")
        archs = re.findall(r"(?:^|\s)-arch\s+(\S+)", text)
        if not archs or set(archs) != {architecture}:
            raise ValueError(f"{matches[0]}: expected only -arch {architecture}, got {archs}")
        if "iPhoneOS" in text or "-miphoneos-version-min=" in text:
            raise ValueError(f"{matches[0]}: host tool uses the iPhoneOS SDK")
    print(f"PASS: ICU and V8 host generators all target macOS {architecture}")


if __name__ == "__main__":
    try:
        check(Path(sys.argv[1]), platform.machine())
    except (ValueError, IndexError) as error:
        sys.exit(str(error))
