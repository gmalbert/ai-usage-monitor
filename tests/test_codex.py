from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from providers.codex import CodexProvider


class CodexProviderTests(unittest.TestCase):
    def test_finds_desktop_bundled_executable_when_path_is_missing(self):
        with tempfile.TemporaryDirectory() as directory:
            executable = Path(directory) / "OpenAI" / "Codex" / "bin" / "version" / "codex.exe"
            executable.parent.mkdir(parents=True)
            executable.touch()
            with patch("providers.codex.shutil.which", return_value=None), patch.dict(os.environ, {"LOCALAPPDATA": directory}):
                self.assertEqual(CodexProvider._find_executable(), str(executable))
