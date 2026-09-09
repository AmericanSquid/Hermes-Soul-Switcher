# Hermes Soul Switcher

A small source patch for [Nous Research Hermes Agent](https://github.com/NousResearch/hermes-agent). It adds one command:

```text
/soul
/soul default
```

`/soul` lists saved souls and marks the active one. `/soul NAME` atomically copies `~/.hermes/souls/NAME.md` to `~/.hermes/SOUL.md`. Hermes already reads `SOUL.md` when it builds an agent, so the patch only refreshes that agent for the next message.

The mod does not add a config file or state database. It does not change memories, providers, models, skills, tools, sessions, profiles, or message routing. The active name is determined by comparing `SOUL.md` with the saved `.md` files.

## Install

From this directory:

```bash
chmod +x install.sh uninstall.sh
./install.sh
```

The installer looks first at `$HERMES_INSTALL_DIR`, then the normal Hermes locations (`$HERMES_HOME/hermes-agent`, `~/.hermes/hermes-agent`, `/usr/local/lib/hermes-agent`, and `/opt/hermes-agent`), the `hermes` launcher on `PATH`, and finally a shallow search under `$HERMES_HOME`.

For an unusual installation location:

```bash
HERMES_INSTALL_DIR=/path/to/hermes-agent ./install.sh
```

Restart any Hermes processes that were already running. No build, dependency install, or Docker change is required.

The installer is safe to run again. It keeps the first pristine backup and does not overwrite saved soul files. Every valid top-level `souls/*.md` file bundled with this repository is copied automatically, so rerunning the installer after an update adds newly bundled souls.

## Existing SOUL.md behavior

If `~/.hermes/SOUL.md` exists, the installer leaves it active and copies it into the souls directory as `current.md` or a non-conflicting `current-N.md`. Existing soul files are never overwritten.

If no `SOUL.md` exists, the included `default.md` becomes the initial soul. If a repository intentionally omits `default.md`, the first bundled soul in filename order is used instead.

Repository contributors can bundle another soul simply by adding a valid Markdown file directly to `souls/`. No installer code change is required.

Add a soul by creating a lowercase file directly inside the souls directory, for example:

```bash
cp my-personality.md ~/.hermes/souls/researcher.md
```

Names may contain lowercase letters, numbers, `_`, and `-`. Subdirectories, paths, symlinks, and other extensions are not accepted by `/soul`.

## Uninstall

From this directory:

```bash
./uninstall.sh
```

The uninstaller restores every patched Hermes source file and the `SOUL.md` that existed at install time. It removes the installed helper module and its backup directory. It deliberately leaves `~/.hermes/souls/` and every saved soul in it untouched.

For an unusual installation location:

```bash
HERMES_INSTALL_DIR=/path/to/hermes-agent ./uninstall.sh
```

Restart running Hermes processes once after uninstalling.

Because this mod directly patches a Git checkout, uninstall it before running `hermes update`, then reinstall it after the update if the patch still matches that Hermes version.

## Files changed in Hermes

The installer backs up and patches these existing files:

- `hermes_cli/commands.py`
- `hermes_cli/cli_commands_mixin.py`
- `gateway/slash_commands_model.py`
- `gateway/run_busy.py`
- `tui_gateway/methods_slash.py`

It also installs one small new module:

- `hermes_cli/soul_switcher.py`

User-state changes are limited to creating `~/.hermes/souls/`, adding bundled souls only when their filenames are unused, preserving an existing `SOUL.md` there, and creating `SOUL.md` from `default.md` (or the first bundled soul) only when it was absent.

Backups live temporarily at `<hermes-install>/.soul-switcher-backup/` and are removed after a successful uninstall. The patch was built and tested against Hermes commit `b1f003e18633298d549668b8e186af84cca45b76` (2026-09-08). On a source version whose surrounding code no longer matches, installation stops during a dry run before modifying anything.
