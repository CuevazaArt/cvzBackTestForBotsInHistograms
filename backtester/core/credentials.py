"""Encrypted credential storage for Binance API keys."""

from __future__ import annotations

import json
import os
import platform
import subprocess
from pathlib import Path
from typing import Optional

from cryptography.fernet import Fernet, InvalidToken


def _secure_file(path: Path) -> None:
    """Restrict file to owner-only access (cross-platform best-effort).

    On Windows, chmod(0o600) is a no-op because NTFS uses ACLs.
    We call icacls to remove inherited permissions and grant the current
    user full control exclusively.
    """
    if not path.is_file():
        return
    if platform.system() == "Windows":
        username = os.environ.get("USERNAME", "")
        if username:
            try:
                subprocess.run(
                    [
                        "icacls", str(path),
                        "/inheritance:r",
                        "/grant:r", f"{username}:F",
                    ],
                    check=True,
                    capture_output=True,
                )
            except (subprocess.CalledProcessError, FileNotFoundError):
                pass  # icacls unavailable or failed — silently best-effort
    else:
        path.chmod(0o600)


class CredentialManager:
    """Store Binance API keys encrypted with Fernet (machine-local key)."""

    def __init__(self, vault_dir: Path) -> None:
        self.vault_dir = Path(vault_dir)
        self.vault_dir.mkdir(parents=True, exist_ok=True)
        self._cred_path = self.vault_dir / "credentials.enc"
        self._key_path = self.vault_dir / "vault.key"
        # Harden any already-existing files on startup
        _secure_file(self._cred_path)
        _secure_file(self._key_path)

    def exists(self) -> bool:
        return self._cred_path.is_file()

    def _get_fernet(self) -> Fernet:
        if not self._key_path.is_file():
            key = Fernet.generate_key()
            self._key_path.write_bytes(key)
            _secure_file(self._key_path)
        else:
            key = self._key_path.read_bytes()
        return Fernet(key)

    def save(self, api_key: str, api_secret: str) -> None:
        f = self._get_fernet()
        blob = json.dumps({"api_key": api_key.strip(),
                           "api_secret": api_secret.strip()}).encode()
        self._cred_path.write_bytes(f.encrypt(blob))
        _secure_file(self._cred_path)

    def load(self) -> Optional[tuple[str, str]]:
        if not self.exists():
            return None
        try:
            f = self._get_fernet()
            data = json.loads(f.decrypt(self._cred_path.read_bytes()).decode())
            return data["api_key"], data["api_secret"]
        except (InvalidToken, KeyError, json.JSONDecodeError):
            return None

    def delete(self) -> None:
        for path in [self._cred_path, self._key_path]:
            if path.is_file():
                path.unlink()
