import os
import json
import base64
import secrets

from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from cryptography.hazmat.primitives import hashes
from cryptography.fernet import Fernet

import keyring.backend
import keyring.errors

CONFIG_DIR = os.environ.get("XDG_DATA_HOME", "/config")
KEYRING_DIR = os.path.join(CONFIG_DIR, "python_keyring")
STORE_FILE = os.path.join(KEYRING_DIR, "encrypted_keyring.json")
SALT_FILE = os.path.join(KEYRING_DIR, "encrypted_keyring.salt")
PBKDF2_ITER = 200_000


class EncryptedFileKeyring(keyring.backend.KeyringBackend):
    """AES-encrypted keyring backend.

    Passwords are encrypted with a key derived (PBKDF2-HMAC-SHA256) from
    KEYRING_PASSPHRASE, which is supplied at container start and is NOT
    stored on disk. The data volume only ever contains ciphertext + a
    public salt, so stealing the volume alone yields no credentials.
    """

    priority = 1.0

    def __init__(self):
        super().__init__()
        pw = os.environ.get("KEYRING_PASSPHRASE")
        if not pw:
            raise RuntimeError(
                "KEYRING_PASSPHRASE is not set; cannot use encrypted keyring."
            )
        self._passphrase = pw

    def _read_salt(self):
        if not os.path.exists(SALT_FILE):
            os.makedirs(KEYRING_DIR, exist_ok=True)
            salt = secrets.token_bytes(16)
            with open(SALT_FILE, "wb") as f:
                f.write(salt)
        else:
            with open(SALT_FILE, "rb") as f:
                salt = f.read()
        return salt

    def _derive_key(self):
        kdf = PBKDF2HMAC(
            algorithm=hashes.SHA256(),
            length=32,
            salt=self._read_salt(),
            iterations=PBKDF2_ITER,
        )
        return base64.urlsafe_b64encode(kdf.derive(self._passphrase.encode()))

    def _load(self):
        if not os.path.exists(STORE_FILE):
            return {}
        with open(STORE_FILE, "r") as f:
            return json.load(f)

    def _save(self, data):
        os.makedirs(KEYRING_DIR, exist_ok=True)
        with open(STORE_FILE, "w") as f:
            json.dump(data, f)

    def get_password(self, service, username):
        data = self._load()
        token = data.get(f"{service}/{username}")
        if not token:
            return None
        try:
            fernet = Fernet(self._derive_key())
            return fernet.decrypt(token.encode()).decode()
        except Exception as e:
            raise keyring.errors.KeyringError(f"decrypt failed: {e}")

    def set_password(self, service, username, password):
        data = self._load()
        fernet = Fernet(self._derive_key())
        data[f"{service}/{username}"] = fernet.encrypt(password.encode()).decode()
        self._save(data)

    def delete_password(self, service, username):
        data = self._load()
        key = f"{service}/{username}"
        if key in data:
            del data[key]
            self._save(data)
