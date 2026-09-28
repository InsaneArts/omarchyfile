<h1 align="center">Omarchyfile</h1>

<h3 align="center">Your Omarchy setup in one file.</h3>

You don't write an Omarchyfile. Omarchyfile writes it from your machine: your apps, web apps, plugins, bar layout, keybindings, and theme. Share it, sync it between your machines, or install it on a fresh one, and one command sets everything up.

## Make one

```sh
omarchyfile export          # write ./Omarchyfile from this machine
omarchyfile export --pick   # untick anything you'd rather not share first
```

The result reads like this:

```ruby
# Omarchyfile
theme "solitude"

pkg "ghostty"
pkg "zellij"
aur "zen-browser-bin"

webapp "Linear", "https://linear.app"

plugin "https://github.com/tornikegomareli/omarchy-spaces", bar: "left", settings: {"showApps": "all"}

disable "omarchy.workspaces"
widget "omarchy.tailscale", bar: "right"

bind "SUPER + Z", "uwsm-app -- zellij", desc: "Zellij"
```

## Install it anywhere

```sh
omarchyfile check Omarchyfile     # see what would change, without changing anything
omarchyfile install Omarchyfile   # make this machine match
```

Both take a path or a URL, including GitHub and gist links:

```sh
omarchyfile install https://github.com/alice/dotfiles/blob/main/Omarchyfile
```

`install` lists every change and asks first. Running it twice changes nothing the second time.

## Share it

```sh
omarchyfile share
```

This uploads your Omarchyfile as a secret GitHub gist, visible only to people with the link, and prints the command that installs it:

```
omarchyfile install https://gist.github.com/you/1a2b3c
```

Sharing again updates the same gist, so the link keeps working. Use `--public` to list it on your GitHub profile, or `--new` for a fresh link. It needs the GitHub CLI (`gh`).

## Keep your machines in step

Put your Omarchyfile in a git repository, such as your dotfiles, then run this on each machine:

```sh
omarchyfile sync
```

It pulls, installs what your other machines added, adds this machine's changes to the file, then commits and pushes. Sync never drops an entry, so to remove something, delete its line and uninstall it.

## Get Omarchyfile

```sh
curl -fsSL https://raw.githubusercontent.com/InsaneArts/omarchyfile/main/omarchyfile -o ~/.local/bin/omarchyfile
chmod +x ~/.local/bin/omarchyfile
```

It needs only Ruby, which ships with Omarchy.

## Options

- `--pick` chooses what to export from a checklist.
- `--only packages,webapps,plugins,bar,keybindings,theme` applies part of a file.
- `--yes` installs, shares, or syncs without asking, for scripts.
- `--public` and `--new` change how `share` publishes.
- `--stdout` prints an export instead of writing a file.

## What an export leaves out

- Hardware packages: drivers, firmware, microcode, and kernels
- Omarchy's own default packages and web apps
- Plugins installed without an https git URL, and custom bar command modules
- Keybindings that run Lua instead of a command
- Monitors, input, and hooks

## Safety

- The file is parsed, never run. It can only name things to install, and every name is checked before use.
- `install` lists every change and asks before applying it.
- Keybindings go into a marked block in `bindings.lua`. Keys you bound yourself are never overridden, bindings for programs you don't have are skipped, and if Hyprland reports an error the file is put back.
- Each plugin shows whether it is listed on the [Omarchy plugin marketplace](https://plugins.omarchy.org). Plugins run as unsandboxed code, so only install ones you trust.

## Development

```sh
ruby tests/run.rb
```

## License

[MIT License](LICENSE).
