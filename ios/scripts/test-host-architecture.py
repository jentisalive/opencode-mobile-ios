import importlib.util
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("host_check", Path(__file__).with_name("check-host-architecture.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class HostArchitectureTests(unittest.TestCase):
    def test_matching_and_mixed_makefiles(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            names = ["icutools", "genccode", "icupkg", "gen-regexp-special-case"]
            for architecture in ["x86_64", "arm64"]:
                for name in names:
                    (root / (name + ".host.mk")).write_text(f"CFLAGS := -arch {architecture}\nLDFLAGS := -arch {architecture}\n")
                module.check(root, architecture)
                (root / "icutools.host.mk").write_text("CFLAGS := -arch wrong\n")
                with self.assertRaisesRegex(ValueError, "expected only"):
                    module.check(root, architecture)
            (root / "icutools.host.mk").write_text("CFLAGS := -arch arm64 -isysroot /SDKs/iPhoneOS.sdk\n")
            with self.assertRaisesRegex(ValueError, "iPhoneOS SDK"):
                module.check(root, "arm64")
            (root / "icutools.host.mk").unlink()
            with self.assertRaisesRegex(ValueError, "Expected one"):
                module.check(root, "arm64")


if __name__ == "__main__":
    unittest.main()
