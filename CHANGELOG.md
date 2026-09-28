# Changelog

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
