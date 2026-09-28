# Changelog

## 0.2.0

- Keybindings: export your `o.bind` and `hl.unbind` lines, and install them
  into a marked block in `bindings.lua`. Keys you bound yourself are never
  overridden, missing programs are skipped, Omarchy defaults are unbound
  when replaced, and Hyprland errors restore the file.
- `omarchyfile share` publishes an Omarchyfile as a secret gist and prints
  its install command. Sharing again updates the same link.
- `omarchyfile sync` keeps machines in step through a git repository.
- `omarchyfile export --pick` chooses what to export from a checklist.

## 0.1.0

First release.

- `omarchyfile export` writes this machine's setup to an Omarchyfile: theme,
  packages, AUR packages, web apps, plugins with bar placement and settings,
  and built-in bar widgets that differ from Omarchy's defaults
- `omarchyfile check` shows what an install would change
- `omarchyfile install` applies an Omarchyfile from a path or URL, after
  showing every change, using Omarchy's own commands
- Exports skip hardware packages and Omarchy's own defaults
- The file is parsed, never executed; plugins show their marketplace status
