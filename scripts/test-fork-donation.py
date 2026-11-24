#!/usr/bin/env python3
"""Check the donation contract with the exact XMRig binary being packaged."""

import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path


def check(binary: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="xmrig-donation-") as directory:
        config = Path(directory) / "config.json"
        for value, expected in ((None, 0), (0, 0), (1, 1), (99, 99)):
            settings = {
                "autosave": False,
                "colors": False,
                "pools": [{"url": "127.0.0.1:1", "user": "fixture", "algo": "rx/0"}],
            }
            if value is not None:
                settings["donate-level"] = value
            config.write_text(json.dumps(settings), encoding="utf-8")
            result = subprocess.run(
                [str(binary), "--config", str(config), "--dry-run", "--no-color"],
                cwd=directory, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, timeout=15, check=True,
            )
            if not re.search(r"\bDONATE\s+" + str(expected) + r"%", result.stdout):
                raise AssertionError(f"donation setting {value!r} did not resolve to {expected}%")
            if "config OK" not in result.stdout:
                raise AssertionError("dry-run did not accept the configuration")
            print(f"donate-level={value!r}: {expected}%, config OK")


if __name__ == "__main__":
    check(Path(sys.argv[1]).resolve(strict=True))
