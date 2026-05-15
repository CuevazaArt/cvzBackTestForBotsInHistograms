"""Encrypted credential storage for Binance API keys."""

from __future__ import annotations

import json
from pathlib import Path

from cryptography.fernet import Fernet, InvalidToken


class CredentialManager:
    """Store Binance API keys encrypted with Fernet (machine-local key)."""

    def __init__(self, vault_dir: Path) -> None:
        self.vault_dir = Path(vault_dir)
        self.vault_dir.mkdir(parents=True, exist_ok=True)
        self._cred_path = self.vault_dir / "credentials.enc"
        self._key_path = self.vault_dir / "vault.key"
        self._chmod_secret_file()

    def exists(self) -> bool:
        """Check if credentials are already stored."""
        return self._cred_path.is_file()

    def _chmod_secret_file(self) -> None:
        """Restrict permissions on secret files."""
        for path in [self._cred_path, self._key_path]:
            if path.is_file():
                path.chmod(0o600)

    def _get_fernet(self) -> Fernet:
        """Load or create encryption key."""
        if not self._key_path.is_file():
            key = Fernet.generate_key()
            self._key_path.write_bytes(key)
            self._key_path.chmod(0o600)
        else:
            key = self._key_path.read_bytes()
        return Fernet(key)

    def save(self, api_key: str, api_secret: str) -> None:
        """Encrypt and save credentials."""
        f = self._get_fernet()
        data = {"api_key": api_key.strip(), "api_secret": api_secret.strip()}
        blob = json.dumps(data).encode("utf-8")
        token = f.encrypt(blob)
        self._cred_path.write_bytes(token)
        self._cred_path.chmod(0o600)

    def load(self) -> tuple[str, str] | None:
        """Decrypt and load credentials."""
        if not self.exists():
            return None
        try:
            f = self._get_fernet()
            raw = self._cred_path.read_bytes()
            dec = f.decrypt(raw)
            data = json.loads(dec.decode("utf-8"))
            return data["api_key"], data["api_secret"]
        except (InvalidToken, KeyError, json.JSONDecodeError):
            return None

    def delete(self) -> None:
        """Securely delete stored credentials."""
        for path in [self._cred_path, self._key_path]:
            if path.is_file():
                path.unlink()
