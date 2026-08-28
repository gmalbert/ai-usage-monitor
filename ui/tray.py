from __future__ import annotations

import os
import subprocess
import sys
import threading
import tkinter as tk
from pathlib import Path

import pystray

from config import Settings, app_data_dir, save_settings
from credential_store import delete_opencode_key, save_opencode_key
from service import UsageService
from ui.icons import make_icon
from usage import format_local_time


class TrayApplication:
    def __init__(self, service: UsageService, settings: Settings) -> None:
        self.service, self.settings = service, settings
        self.stop_event = threading.Event()
        self.icon = pystray.Icon("AIUsageMonitor", make_icon("degraded"), "AI Usage — loading")

    def _state(self) -> str:
        lowest = self.service.lowest_remaining()
        if lowest is None:
            return "degraded"
        if lowest < self.settings.critical_threshold:
            return "critical"
        if lowest < self.settings.warning_threshold:
            return "warning"
        return "normal"

    def _tooltip(self) -> str:
        lines = ["AI Usage Monitor"]
        labels = {"commandcode": "CommandCode", "opencode": "OpenCode Go", "codex": "Codex"}
        for key, usage in self.service.values.items():
            label = labels.get(key, usage.provider)
            # Keep the compact hover text useful: only show Codex when its live app-server refresh succeeded.
            if key == "codex" and (usage.stale or usage.status.value != "ok"):
                continue
            if usage.five_hour or usage.weekly:
                five = f"5h {usage.five_hour.remaining_percent:.0f}%" if usage.five_hour else "5h —"
                weekly = f"Week {usage.weekly.remaining_percent:.0f}%" if usage.weekly else "Week —"
                lines.append(f"{label}: {five} · {weekly}" + (" (stale)" if usage.stale else ""))
            else:
                if key != "codex":
                    lines.append(f"{label}: unavailable")
        return "\n".join(lines)

    def _refresh(self) -> None:
        self.service.refresh()
        self._notify_threshold_transitions()
        self.icon.icon, self.icon.title = make_icon(self._state(), self.service.lowest_remaining()), self._tooltip()
        self.icon.update_menu()

    def _notify_threshold_transitions(self) -> None:
        """Notify once when a meter crosses into warning/critical territory."""
        for provider_key, usage in self.service.values.items():
            for window in usage.windows():
                key = f"{provider_key}:{window.name}"
                state = "critical" if window.remaining_percent < self.settings.critical_threshold else "warning" if window.remaining_percent < self.settings.warning_threshold else "normal"
                previous = self.service.thresholds.get(key, "normal")
                self.service.thresholds[key] = state
                if self.settings.show_notifications and state in ("warning", "critical") and state != previous:
                    self.icon.notify(f"{usage.provider} {window.name} has {window.remaining_percent:.0f}% remaining.", "AI Usage Monitor")

    def refresh_now(self, _=None, wait: bool = False) -> None:
        if wait:
            self._refresh()
        else:
            threading.Thread(target=self._refresh, daemon=True).start()

    def _scheduled_refresh(self) -> None:
        while not self.stop_event.wait(self.settings.refresh_seconds):
            self._refresh()

    def _lines(self) -> list[str]:
        lines = []
        for usage in self.service.values.values():
            label = usage.provider + (f" — {usage.plan}" if usage.plan else "")
            if usage.error and not usage.windows():
                lines.append(f"{label}: unavailable")
            else:
                meters = " / ".join(f"{window.name}: {window.remaining_percent:.0f}%" for window in usage.windows())
                lines.append(f"{label}: {meters}")
        return lines or ["Usage values are loading…"]

    def _menu(self):
        info = [pystray.MenuItem(line, None, enabled=False) for line in self._lines()]
        return pystray.Menu(*info, pystray.Menu.SEPARATOR,
            pystray.MenuItem("Refresh now", self.refresh_now), pystray.MenuItem("Open detailed view", self.show_details),
            pystray.MenuItem("Set OpenCode Go API key…", self.set_opencode_key),
            pystray.MenuItem("Remove saved OpenCode Go API key", self.remove_opencode_key),
            pystray.MenuItem("Start with Windows", self.toggle_startup, checked=lambda _: self.settings.start_with_windows),
            pystray.MenuItem("Open logs", self.open_logs), pystray.MenuItem("Exit", self.exit))

    def show_details(self, _=None) -> None:
        def run():
            root = tk.Tk(); root.title("AI Usage Monitor"); root.geometry("610x560")
            frame = tk.Frame(root, padx=18, pady=18); frame.pack(fill="both", expand=True)
            for usage in self.service.values.values():
                tk.Label(frame, text=usage.provider + (f" — {usage.plan}" if usage.plan else ""), font=("Segoe UI", 12, "bold"), anchor="w").pack(fill="x", pady=(8, 2))
                if usage.stale:
                    tk.Label(frame, text="Latest local Codex record — live refresh unavailable", fg="#b45309", anchor="w").pack(fill="x")
                if usage.error and not usage.windows(): tk.Label(frame, text=usage.error, anchor="w").pack(fill="x")
                for window in usage.windows():
                    text = f"{window.name:8} {'█' * round(window.remaining_percent / 5):20} {window.remaining_percent:5.1f}% remaining"
                    tk.Label(frame, text=text, anchor="w", font=("Consolas", 10)).pack(fill="x")
                    detail = format_local_time(window.reset_at, "Renews" if window.name == "Monthly" else "Resets")
                    if window.remaining is not None: detail = f"{window.remaining:.2f} credits remaining   {detail}"
                    tk.Label(frame, text="           " + detail, anchor="w").pack(fill="x")
            tk.Button(frame, text="Refresh now", command=self.refresh_now).pack(anchor="e", pady=12)
            root.mainloop()
        threading.Thread(target=run, daemon=True).start()

    def toggle_startup(self, _=None) -> None:
        self.settings.start_with_windows = not self.settings.start_with_windows
        save_settings(self.settings)
        startup = Path(os.environ.get("APPDATA", "")) / "Microsoft/Windows/Start Menu/Programs/Startup/AIUsageMonitor.cmd"
        if self.settings.start_with_windows:
            startup.parent.mkdir(parents=True, exist_ok=True)
            if getattr(sys, "frozen", False):
                command = f'"{sys.executable}"'
            else:
                command = f'"{sys.executable}" "{Path.cwd() / "app.py"}"'
            startup.write_text(f"@echo off\r\n{command}\r\n", encoding="utf-8")
        else:
            startup.unlink(missing_ok=True)

    def set_opencode_key(self, _=None) -> None:
        def run():
            from tkinter import messagebox, simpledialog
            root = tk.Tk(); root.withdraw()
            key = simpledialog.askstring("OpenCode Go API key", "Paste your OpenCode Go API key:", show="*", parent=root)
            if key is not None:
                try:
                    save_opencode_key(key)
                except (OSError, ValueError) as exc:
                    messagebox.showerror("Could not save key", str(exc), parent=root)
                else:
                    messagebox.showinfo("Saved", "Saved securely in Windows Credential Manager.", parent=root)
                    # Refresh in this worker before reporting success so the newly saved key is used immediately.
                    self.refresh_now(wait=True)
            root.destroy()
        threading.Thread(target=run, daemon=True).start()

    def remove_opencode_key(self, _=None) -> None:
        delete_opencode_key()
        self.refresh_now()

    def open_logs(self, _=None) -> None:
        path = app_data_dir() / "logs"
        path.mkdir(parents=True, exist_ok=True)
        if sys.platform == "win32": os.startfile(path)  # type: ignore[attr-defined]
        elif sys.platform == "darwin": subprocess.run(["open", str(path)], check=False)

    def exit(self, _=None) -> None:
        self.stop_event.set(); self.icon.stop()

    def run(self) -> None:
        self.icon.menu = self._menu()
        self.refresh_now()
        threading.Thread(target=self._scheduled_refresh, daemon=True).start()
        self.icon.run()
