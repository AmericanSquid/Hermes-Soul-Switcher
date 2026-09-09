"""Small, file-only SOUL.md switcher used by the /soul command."""

from __future__ import annotations

import os
import re
import tempfile
from pathlib import Path

from hermes_constants import get_hermes_home


_VALID_NAME = re.compile(r"^[a-z0-9][a-z0-9_-]*$")


class SoulError(ValueError):
    """A safe, user-facing soul-switching error."""


def _home(home: Path | None = None) -> Path:
    return Path(home) if home is not None else get_hermes_home()


def available_souls(home: Path | None = None) -> list[str]:
    souls_dir = _home(home) / "souls"
    if not souls_dir.is_dir():
        return []
    names = []
    for path in souls_dir.iterdir():
        if (
            path.suffix == ".md"
            and _VALID_NAME.fullmatch(path.stem)
            and path.is_file()
            and not path.is_symlink()
        ):
            names.append(path.stem)
    return sorted(names)


def active_souls(home: Path | None = None) -> list[str]:
    root = _home(home)
    active = root / "SOUL.md"
    if not active.is_file():
        return []
    try:
        active_bytes = active.read_bytes()
    except OSError:
        return []
    matches = []
    for name in available_souls(root):
        try:
            if (root / "souls" / f"{name}.md").read_bytes() == active_bytes:
                matches.append(name)
        except OSError:
            continue
    return matches


def format_soul_list(home: Path | None = None) -> str:
    names = available_souls(home)
    active = set(active_souls(home))
    lines = ["Available souls:"]
    lines.extend(f"  {'*' if name in active else ' '} {name}" for name in names)
    if not names:
        lines.append("  (none — add lowercase-name.md files to ~/.hermes/souls/)")
    current = ", ".join(sorted(active)) or "custom/unsaved"
    lines.extend((f"Active: {current}", "Usage: /soul <name>"))
    return "\n".join(lines)


def switch_soul(name: str, home: Path | None = None) -> str:
    requested = (name or "").strip().lower()
    if not _VALID_NAME.fullmatch(requested):
        raise SoulError("Soul names may contain only lowercase letters, numbers, '_' and '-'.")

    root = _home(home)
    souls_dir = root / "souls"
    source = souls_dir / f"{requested}.md"
    if source.is_symlink() or not source.is_file():
        raise SoulError(f"Unknown soul: {requested}")

    try:
        content = source.read_bytes()
    except OSError as exc:
        raise SoulError(f"Could not read soul '{requested}': {exc}") from exc

    root.mkdir(parents=True, exist_ok=True)
    target = root / "SOUL.md"
    mode = 0o644
    try:
        if target.exists() and not target.is_symlink():
            mode = target.stat().st_mode & 0o777
    except OSError:
        pass

    temp_name = ""
    try:
        with tempfile.NamedTemporaryFile(prefix=".SOUL.md.", dir=root, delete=False) as temp:
            temp_name = temp.name
            temp.write(content)
            temp.flush()
            os.fsync(temp.fileno())
        os.chmod(temp_name, mode)
        os.replace(temp_name, target)
    except OSError as exc:
        if temp_name:
            try:
                os.unlink(temp_name)
            except OSError:
                pass
        raise SoulError(f"Could not activate soul '{requested}': {exc}") from exc
    return requested
