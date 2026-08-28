"""Secure Windows Credential Manager storage for the OpenCode Go API key."""
from __future__ import annotations

import ctypes
import sys
from ctypes import POINTER, Structure, byref, c_byte, c_void_p
from ctypes.wintypes import DWORD, FILETIME, LPWSTR

TARGET_NAME = "AIUsageMonitor/OpenCodeGoApiKey"
CRED_TYPE_GENERIC = 1
CRED_PERSIST_LOCAL_MACHINE = 2


class _Credential(Structure):
    _fields_ = [("Flags", DWORD), ("Type", DWORD), ("TargetName", LPWSTR), ("Comment", LPWSTR),
        ("LastWritten", FILETIME), ("CredentialBlobSize", DWORD), ("CredentialBlob", POINTER(c_byte)),
        ("Persist", DWORD), ("AttributeCount", DWORD), ("Attributes", c_void_p), ("TargetAlias", LPWSTR), ("UserName", LPWSTR)]


def load_opencode_key() -> str | None:
    if sys.platform != "win32":
        return None
    pointer = POINTER(_Credential)()
    if not ctypes.windll.advapi32.CredReadW(TARGET_NAME, CRED_TYPE_GENERIC, 0, byref(pointer)):
        return None
    try:
        value = pointer.contents
        return ctypes.string_at(value.CredentialBlob, value.CredentialBlobSize).decode("utf-16-le") if value.CredentialBlobSize else None
    finally:
        ctypes.windll.advapi32.CredFree(pointer)


def save_opencode_key(api_key: str) -> None:
    if sys.platform != "win32":
        raise OSError("The key dialog is supported on Windows only")
    encoded = api_key.strip().encode("utf-16-le")
    if not encoded:
        raise ValueError("The API key cannot be empty")
    blob = (c_byte * len(encoded)).from_buffer_copy(encoded)
    credential = _Credential(0, CRED_TYPE_GENERIC, TARGET_NAME, None, FILETIME(), len(encoded), blob,
        CRED_PERSIST_LOCAL_MACHINE, 0, None, None, "AI Usage Monitor")
    if not ctypes.windll.advapi32.CredWriteW(byref(credential), 0):
        raise ctypes.WinError()


def delete_opencode_key() -> None:
    if sys.platform == "win32":
        ctypes.windll.advapi32.CredDeleteW(TARGET_NAME, CRED_TYPE_GENERIC, 0)
