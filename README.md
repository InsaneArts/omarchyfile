<h1 align="center">Omarchyfile</h1>

<h3 align="center">Your Omarchy setup in one file.</h3>

Omarchyfile writes your apps, web apps, plugins, bar layout, and theme to a single file. Install that file on a fresh machine, or share it, and one command sets everything up.

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
```

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/InsaneArts/omarchyfile/main/omarchyfile -o ~/.local/bin/omarchyfile
chmod +x ~/.local/bin/omarchyfile
```

It needs only Ruby, which ships with Omarchy.

## Use

```sh
omarchyfile export     # write ./Omarchyfile from this machine
omarchyfile check      # show what install would change, without changing anything
omarchyfile install    # make this machine match ./Omarchyfile
```

`check` and `install` also take a path or a URL, including GitHub and gist links:

```sh
omarchyfile install https://github.com/alice/dotfiles/blob/main/Omarchyfile
```

Options:

- `--only packages,webapps,plugins,bar,theme` applies part of a file.
- `--yes` installs without asking, for scripts.
- `--stdout` prints an export instead of writing a file.

Running `install` twice changes nothing the second time.

## What an export leaves out

- Hardware packages: drivers, firmware, microcode, and kernels
- Omarchy's own default packages and web apps
- Plugins installed without an https git URL, and custom bar command modules
- Monitors, input, keybindings, and hooks

## Safety

- The file is parsed, never run. It can only name things to install, and every name is checked before use.
- `install` lists every change and asks before applying it.
- Each plugin shows whether it is listed on the [Omarchy plugin marketplace](https://plugins.omarchy.org). Plugins run as unsandboxed code, so only install ones you trust.

## Development

```sh
ruby tests/run.rb
```

## License

[MIT License](LICENSE).
