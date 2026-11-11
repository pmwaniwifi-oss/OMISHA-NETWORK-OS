import subprocess
import unittest
from unittest.mock import patch
from preflight import probe


class ProbeTests(unittest.TestCase):
    @patch("preflight.shutil.which", return_value=None)
    def test_missing_command(self, _):
        self.assertEqual(probe(["docker", "--version"])["reason"], "command_not_found")

    @patch("preflight.subprocess.run", return_value=subprocess.CompletedProcess([], 0, "Go: Unknown option: version", ""))
    @patch("preflight.shutil.which", return_value="/usr/bin/go")
    def test_same_named_binary_is_not_a_go_toolchain(self, *_):
        result = probe(["go", "version"], r"^go version go(\d+\.\d+[^\s]*)")
        self.assertFalse(result["available"])

    @patch("preflight.subprocess.run", return_value=subprocess.CompletedProcess([], 0, "go version go1.26.0 linux/amd64\n", ""))
    @patch("preflight.shutil.which", return_value="/usr/bin/go")
    def test_actual_version_is_detected(self, *_):
        self.assertEqual(probe(["go", "version"], r"^go version go(\d+\.\d+[^\s]*)")["version"], "1.26.0")

    @patch("preflight.subprocess.run", side_effect=subprocess.TimeoutExpired("docker", 8))
    @patch("preflight.shutil.which", return_value="/usr/bin/docker")
    def test_daemon_timeout_is_not_installed_and_running(self, *_):
        self.assertFalse(probe(["docker", "version"])["available"])


if __name__ == "__main__":
    unittest.main()
