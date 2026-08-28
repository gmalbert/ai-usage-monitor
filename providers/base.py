from __future__ import annotations

from abc import ABC, abstractmethod

from models import ProviderUsage


class UsageProvider(ABC):
    key: str

    @abstractmethod
    def fetch(self) -> ProviderUsage:
        raise NotImplementedError
