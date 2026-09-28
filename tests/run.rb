# frozen_string_literal: true

# Run: ruby tests/run.rb
require "set"
require "stringio"
load File.expand_path("../omarchyfile", __dir__)

$failed = 0
def test(name)
  yield
  puts "ok   #{name}"
rescue StandardError => e
  $failed += 1
  puts "FAIL #{name}\n     #{e.message}"
end

# Runs the block with stdout and stderr captured, returning its value.
def quietly
  out, err = $stdout, $stderr
  $stdout = StringIO.new
  $stderr = StringIO.new
  yield
ensure
  $stdout, $stderr = out, err
end

def eq(actual, expected)
  raise "expected #{expected.inspect}, got #{actual.inspect}" unless actual == expected
end

def raises(pattern)
  yield
  raise "expected an error matching #{pattern.inspect}"
rescue Omarchyfile::Error => e
  raise "error #{e.message.inspect} does not match #{pattern.inspect}" unless e.message.match?(pattern)
end

P = Omarchyfile::Parser

# A machine described entirely by data. Commands are recorded, never run.
class FakeMachine < Omarchyfile::Machine
  attr_reader :ran
  attr_accessor :config

  def initialize(**data)
    @d = {
      installed: [], native: [], foreign: [], defaults: [], script: [], config: { "bar" => { "layout" => {} } },
      default_config: { "bar" => { "layout" => {} } }, plugins: [], webapps: [], shipped: [], icons: [],
      theme: "solitude", theme_remotes: {}, themes: ["solitude"], marketplace: {},
      home: "/home/me", bindings: "", default_bindings: {}, commands: [], shares: {}, gists: {},
      git_root: nil, upstream: false, confirm: true,
    }.merge(data)
    @config = @d[:config]
    @ran = []
  end

  def installed_packages = @d[:installed].to_set
  def explicit_native = @d[:native]
  def explicit_foreign = @d[:foreign]
  def omarchy_default_packages = @d[:defaults].to_set
  def omarchy_script_packages = @d[:script].to_set
  def shell_config = @config
  def default_shell_config = @d[:default_config]
  def plugins = @d[:plugins]
  def webapps = @d[:webapps]
  def webapp_installed?(name) = @d[:webapps].any? { |w| w[:name] == name }
  def shipped_launchers = @d[:shipped].to_set
  def bundled_icon?(name) = @d[:icons].include?(name)
  def current_theme = @d[:theme]
  def theme_installed?(slug) = @d[:themes].include?(slug)
  def theme_remote(slug) = @d[:theme_remotes][slug]
  def marketplace_status = @d[:marketplace]
  def pick(labels) = @d[:pick]&.call(labels)
  def home = @d[:home]
  def bindings_text = @d[:bindings]
  def default_bindings = @d[:default_bindings]
  def command_available?(command) = @d[:commands].include?(Omarchyfile.program(command).sub(%r{\A~/}, "#{home}/"))
  def confirm?(_question) = @d[:confirm]
  def shares = @d[:shares]
  def save_shares(map) = @d[:shares] = map
  def gist_create(text, public:) = "https://gist.github.com/me/#{(@d[:gists].size + 1).to_s * 6}".tap { |u| @d[:gists][u] = [text, public] }
  def gist_update(url, text) = @d[:gists].key?(url) && (@d[:gists][url][0] = text; true)
  def gists = @d[:gists]
  def git_root(_path) = @d[:git_root]
  def git_upstream?(_repo) = @d[:upstream]
  def hostname = "desk"

  def add_bindings(lines)
    @ran << [:bindings, lines]
    @d[:bindings] = Omarchyfile::Bindings.insert(@d[:bindings], lines)
    true
  end

  def run(cmd)
    @ran << cmd
    true
  end
end

def layout(left: [], center: [], right: []) = { "bar" => { "layout" => { "left" => left, "center" => center, "right" => right } } }

SPACES = "https://github.com/tornikegomareli/omarchy-spaces"

# ---------------------------------------------------------------- parser

test "parses every command with options" do
  entries = P.parse(<<~FILE)
    # comment
    theme "ash", git: "https://github.com/x/ash"
    pkg "btop"   # trailing comment
    aur "zen-browser-bin"
    webapp "YouTube", "https://youtube.com/", icon: "youtube"
    plugin "#{SPACES}", bar: "left", settings: {"showApps": "all", "iconSize": 18}
    widget "omarchy.tailscale", bar: "right"
    disable "omarchy.workspaces"
  FILE
  eq entries.map(&:verb), %w[theme pkg aur webapp plugin widget disable]
  eq entries[0].opts, { "git" => "https://github.com/x/ash" }
  eq entries[3].args, ["YouTube", "https://youtube.com/"]
  eq entries[4].opts["settings"], { "showApps" => "all", "iconSize" => 18 }
end

test "keeps # and braces inside strings" do
  e = P.parse(%(plugin "#{SPACES}", settings: {"label": "a # b } {"}\n)).first
  eq e.opts["settings"], { "label" => "a # b } {" }
end

test "decodes escapes in strings" do
  eq P.parse(%(webapp "My \\"App\\"", "https://x.com"\n)).first.args[0], 'My "App"'
end

test "rejects unknown commands and wrong arity" do
  raises(/unknown command 'brew'/) { P.parse(%(brew "git")) }
  raises(/takes 2 quoted values, found 1/) { P.parse(%(webapp "X")) }
  raises(/expected a comma/) { P.parse(%(webapp "X" "https://x.com")) }
end

test "rejects package names that could be options or shell" do
  raises(/not a valid package name/) { P.parse(%(pkg "--overwrite")) }
  raises(/not a valid package name/) { P.parse(%(pkg "btop; rm -rf ~")) }
  raises(/not a valid package name/) { P.parse(%(aur "$(whoami)")) }
end

test "rejects non-https plugins and unknown sections" do
  raises(/https:\/\/ git URLs/) { P.parse(%(plugin "http://example.com/p")) }
  raises(/https:\/\/ git URLs/) { P.parse(%(plugin "git@github.com:me/p.git")) }
  raises(/bar: must be left, center, or right/) { P.parse(%(plugin "#{SPACES}", bar: "top")) }
end

test "rejects bad options and settings" do
  raises(/pkg does not take bar:/) { P.parse(%(pkg "btop", bar: "left")) }
  raises(/cannot set id/) { P.parse(%(plugin "#{SPACES}", settings: {"id": "x"})) }
  raises(/missing a closing/) { P.parse(%(plugin "#{SPACES}", settings: {"a": 1)) }
  raises(/values must come before options/) { P.parse(%(webapp "X", icon: "x", "https://x.com")) }
  raises(/built-in widget id/) { P.parse(%(disable "acme.clock")) }
end

test "reports the line number" do
  raises(/\Aline 3:/) { P.parse(%(pkg "a"\n\nbogus "b"\n)) }
end

test "writer output parses back to the same entries" do
  text = <<~FILE
    theme "ash", git: "https://github.com/x/ash"
    pkg "btop"
    webapp "My \\"App\\"", "https://x.com/?q=1", icon: "hey"
    plugin "#{SPACES}", bar: "left", settings: {"showApps": "all", "nested": {"a": [1, 2]}}
    disable "omarchy.workspaces"
  FILE
  entries = P.parse(text)
  again = P.parse(entries.map { |e| Omarchyfile::Writer.line(e) }.join("\n"))
  eq again.map { |e| [e.verb, e.args, e.opts] }, entries.map { |e| [e.verb, e.args, e.opts] }
end

# ---------------------------------------------------------------- helpers

test "normalizes repository URLs" do
  eq Omarchyfile.normalize_repo("https://github.com/Me/Plugin.git/"), "https://github.com/me/plugin"
end

test "recognizes machine-specific packages" do
  %w[intel-ucode linux linux-firmware nvidia-open-dkms lib32-nvidia-utils omarchy-settings sudo sof-firmware].each do |p|
    raise "#{p} should be a system package" unless Omarchyfile.system_package?(p)
  end
  %w[btop ghostty spotify zen-browser-bin].each do |p|
    raise "#{p} should not be a system package" if Omarchyfile.system_package?(p)
  end
end

test "turns GitHub page URLs into raw file URLs" do
  eq Omarchyfile::CLI.raw_url("https://github.com/me/dots/blob/main/Omarchyfile"),
     "https://raw.githubusercontent.com/me/dots/main/Omarchyfile"
  eq Omarchyfile::CLI.raw_url("https://gist.github.com/me/abc123"), "https://gist.githubusercontent.com/me/abc123/raw"
end

# ---------------------------------------------------------------- export

def rich_machine
  FakeMachine.new(
    native: %w[btop ghostty intel-ucode git nvidia-utils],
    foreign: %w[zen-browser-bin],
    installed: %w[btop ghostty intel-ucode git nvidia-utils zen-browser-bin],
    defaults: %w[git],
    script: %w[nvidia-utils],
    webapps: [
      { name: "YouTube", url: "https://youtube.com/", icon: "youtube", file: "YouTube.desktop" },
      { name: "Linear", url: "https://linear.app", icon: "linear", file: "Linear.desktop" },
      { name: "HEY", url: "https://app.hey.com", icon: "HEY", file: "HEY.desktop" },
    ],
    shipped: ["YouTube.desktop"],
    icons: ["HEY"],
    plugins: [
      { id: "tornikegomareli.spaces", dir: "/p/s", remote: "#{SPACES}.git" },
      { id: "me.local", dir: "/p/l", remote: nil },
    ],
    default_config: layout(left: [{ "id" => "omarchy.menu" }, { "id" => "omarchy.workspaces" }],
                           center: [{ "id" => "omarchy.clock", "format" => "HH:mm" }]),
    config: layout(left: [{ "id" => "omarchy.menu" }, { "id" => "tornikegomareli.spaces", "showApps" => "all" }, { "id" => "me.local" }],
                   center: [{ "id" => "omarchy.clock", "format" => "dddd HH:mm" }],
                   right: [{ "id" => "omarchy.tailscale" }, { "id" => "vpn", "type" => "command", "exec" => "~/vpn" }]),
    theme: "ash", theme_remotes: { "ash" => "https://github.com/x/omarchy-ash-theme" }
  )
end

test "exports only packages the user chose" do
  text = Omarchyfile::Exporter.new(rich_machine).render
  lines = text.lines.map(&:chomp)
  raise "btop missing" unless lines.include?('pkg "btop"')
  raise "ghostty missing" unless lines.include?('pkg "ghostty"')
  raise "aur missing" unless lines.include?('aur "zen-browser-bin"')
  %w[git intel-ucode nvidia-utils].each { |p| raise "#{p} leaked" if text.include?(%(pkg "#{p}")) }
end

test "exports user web apps, skipping shipped ones, with bundled icons only" do
  text = Omarchyfile::Exporter.new(rich_machine).render
  raise "shipped YouTube leaked" if text.include?("youtube.com")
  raise "Linear missing" unless text.include?(%(webapp "Linear", "https://linear.app"\n))
  raise "HEY icon missing" unless text.include?(%(webapp "HEY", "https://app.hey.com", icon: "HEY"))
end

test "exports git plugins with section and settings, skips local ones" do
  text = Omarchyfile::Exporter.new(rich_machine).render
  raise "plugin line wrong:\n#{text}" unless text.include?(%(plugin "#{SPACES}", bar: "left", settings: {"showApps": "all"}))
  raise "local plugin not reported" unless text.include?("me.local: installed locally")
end

test "exports built-in widget differences and skips custom modules" do
  text = Omarchyfile::Exporter.new(rich_machine).render
  raise "disable missing" unless text.include?(%(disable "omarchy.workspaces"))
  raise "added widget missing" unless text.include?(%(widget "omarchy.tailscale", bar: "right"))
  raise "changed widget missing" unless text.include?(%(widget "omarchy.clock", settings: {"format": "dddd HH:mm"}))
  raise "menu should be unchanged" if text.include?(%(widget "omarchy.menu"))
  raise "custom module not reported" unless text.include?("vpn: custom bar module")
end

test "exports a git theme with its URL" do
  text = Omarchyfile::Exporter.new(rich_machine).render
  raise "theme wrong" unless text.include?(%(theme "ash", git: "https://github.com/x/omarchy-ash-theme"))
end

test "a machine matches its own export" do
  machine = rich_machine
  entries = P.parse(Omarchyfile::Exporter.new(machine).render)
  steps = Omarchyfile::Planner.new(entries, machine).steps
  eq steps.map(&:detail), []
end

test "export --pick writes only the ticked entries" do
  machine = rich_machine
  machine.instance_variable_get(:@d)[:pick] = ->(labels) { labels.reject { |l| l.start_with?("AUR") || l.include?("Linear") } }
  out = StringIO.new
  orig = $stdout
  $stdout = out
  code = Omarchyfile::CLI.run(["export", "--pick", "--stdout"], machine: machine)
  $stdout = orig
  eq code, 0
  text = out.string
  raise "kept package missing" unless text.include?(%(pkg "btop"))
  raise "unticked AUR package exported" if text.include?(%(aur "zen-browser-bin"))
  raise "unticked web app exported" if text.include?("Linear")
  raise "Not exported notes missing" unless text.include?("# Not exported:")
end

test "cancelling the checklist writes nothing" do
  machine = rich_machine
  machine.instance_variable_get(:@d)[:pick] = ->(_labels) { nil }
  eq quietly { Omarchyfile::CLI.run(["export", "--pick", "--stdout"], machine: machine) }, 2
end

test "checklist labels read naturally" do
  entries = P.parse(%(pkg "btop"\nplugin "#{SPACES}", bar: "left"\ndisable "omarchy.workspaces"\n))
  eq entries.map { |e| Omarchyfile.label(e) },
     ["Package   btop", "Plugin    tornikegomareli/omarchy-spaces on the left", "Bar       turn off omarchy.workspaces"]
end

# ---------------------------------------------------------------- plan

test "plans missing packages in one command per source" do
  m = FakeMachine.new(installed: %w[btop])
  steps = Omarchyfile::Planner.new(P.parse(%(pkg "btop"\npkg "lazygit"\npkg "yazi"\naur "bruno-bin"\n)), m).steps
  eq steps.map(&:label), %w[Packages AUR]
  steps.each { |s| s.run.call }
  eq m.ran, [%w[omarchy pkg add lazygit yazi], %w[omarchy pkg aur add bruno-bin]]
end

test "plans a missing web app with automatic icon" do
  m = FakeMachine.new
  steps = Omarchyfile::Planner.new(P.parse(%(webapp "Linear", "https://linear.app"\n)), m).steps
  steps.first.run.call
  eq m.ran, [["omarchy", "webapp", "install", "Linear", "https://linear.app", ""]]
end

test "adds a missing plugin, shows its marketplace status, then places it" do
  m = FakeMachine.new(marketplace: { SPACES.downcase => "verified" })
  entries = P.parse(%(plugin "#{SPACES}", bar: "left", settings: {"showApps": "all"}\n))
  step = Omarchyfile::Planner.new(entries, m).steps.first
  eq step.detail, ["add #{SPACES} (on plugins.omarchy.org, verified)", "then place it on the left", "then apply 1 setting"]
  # Simulate the install landing the plugin in its default section.
  def m.run(cmd)
    super
    if cmd[1..2] == %w[plugin add]
      @d[:plugins] = [{ id: "tornikegomareli.spaces", dir: "/p", remote: SPACES }]
      self.config = layout(right: [{ "id" => "tornikegomareli.spaces" }])
    end
    true
  end
  step.run.call
  eq m.ran, [
    ["omarchy", "plugin", "add", SPACES, "--enable", "--yes"],
    ["omarchy", "bar", "move", "tornikegomareli.spaces", "--section", "left"],
    ["omarchy", "bar", "set", "tornikegomareli.spaces", "showApps", '"all"', "--json"],
  ]
end

test "warns about plugins missing from the marketplace" do
  m = FakeMachine.new
  step = Omarchyfile::Planner.new(P.parse(%(plugin "https://github.com/x/y"\n)), m).steps.first
  eq step.detail.first, "add https://github.com/x/y (not on plugins.omarchy.org)"
end

test "moves and configures an installed plugin" do
  m = FakeMachine.new(plugins: [{ id: "tornikegomareli.spaces", dir: "/p", remote: SPACES }],
                      config: layout(right: [{ "id" => "tornikegomareli.spaces", "showApps" => "hover" }]))
  step = Omarchyfile::Planner.new(P.parse(%(plugin "#{SPACES}", bar: "left", settings: {"showApps": "all"}\n)), m).steps.first
  eq step.detail, ["move tornikegomareli.spaces to the left", 'set tornikegomareli.spaces showApps to "all"']
end

test "turns off built-in widgets that are on" do
  m = FakeMachine.new(config: layout(left: [{ "id" => "omarchy.workspaces" }]))
  steps = Omarchyfile::Planner.new(P.parse(%(disable "omarchy.workspaces"\ndisable "omarchy.clock"\n)), m).steps
  eq steps.map(&:detail), [["turn off omarchy.workspaces"]]
end

test "installs a git theme before switching to it" do
  m = FakeMachine.new(theme: "solitude")
  steps = Omarchyfile::Planner.new(P.parse(%(theme "Forest Night", git: "https://github.com/x/forest-night"\n)), m).steps
  steps.first.run.call
  eq m.ran, [%w[omarchy theme install https://github.com/x/forest-night], %w[omarchy theme set forest-night]]
end

# ---------------------------------------------------------------- CLI

test "check exits 0 when in sync and 1 when changes are pending" do
  Dir.mktmpdir do |dir|
    path = File.join(dir, "Omarchyfile")
    File.write(path, %(pkg "btop"\n))
    eq quietly { Omarchyfile::CLI.run(["check", path], machine: FakeMachine.new(installed: %w[btop])) }, 0
    eq quietly { Omarchyfile::CLI.run(["check", path], machine: FakeMachine.new) }, 1
  end
end

test "install --yes --only applies just the chosen categories" do
  Dir.mktmpdir do |dir|
    path = File.join(dir, "Omarchyfile")
    File.write(path, %(pkg "btop"\nwebapp "Linear", "https://linear.app"\n))
    m = FakeMachine.new
    eq quietly { Omarchyfile::CLI.run(["install", path, "--yes", "--only", "webapps"], machine: m) }, 0
    eq m.ran, [["omarchy", "webapp", "install", "Linear", "https://linear.app", ""]]
  end
end

test "rejects unknown --only categories" do
  eq quietly { Omarchyfile::CLI.run(["check", "--only", "fonts"], machine: FakeMachine.new) }, 2
end

# ---------------------------------------------------------------- keybindings

USER_BINDINGS = <<~LUA
  -- Keep only your personal keybinding overrides here.
  -- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")
  hl.unbind("SUPER + RETURN")
  o.bind("SUPER + RETURN", "Jolt", "/home/me/Development/jolt/target/release/jolt toggle")
  o.bind("SUPER + CTRL + ALT + S", nil, "omarchy-shell tornikegomareli.spaces toggle") -- spaces
  o.bind("SUPER + P", "Say \\"hi\\"", "notify-send \\"hi\\"")
  o.bind("SUPER + T", "Terminal", { omarchy = "terminal" })
LUA

test "normalizes key combinations" do
  eq Omarchyfile::Keys.normalize("ctrl+super + s"), "SUPER + CTRL + S"
  eq Omarchyfile::Keys.normalize("SUPER + SHIFT + CTRL + ALT + k"), "SUPER + CTRL + ALT + SHIFT + K"
  eq Omarchyfile::Keys.normalize("super + mouse:272"), "SUPER + MOUSE:272"
end

test "finds the program a command starts" do
  eq Omarchyfile.program("uwsm-app -- zellij attach"), "zellij"
  eq Omarchyfile.program("FOO=1 BAR=2 ~/bin/tool --x"), "~/bin/tool"
  eq Omarchyfile.program(%(notify-send "a b")), "notify-send"
end

test "reads plain bindings and notes Lua ones" do
  found, others = Omarchyfile::Bindings.parse(USER_BINDINGS)
  eq found.map { |b| [b[:kind], b[:keys]] }, [[:unbind, "SUPER + RETURN"], [:bind, "SUPER + RETURN"],
                                             [:bind, "SUPER + CTRL + ALT + S"], [:bind, "SUPER + P"]]
  eq found[2][:desc], nil
  eq found[3][:desc], 'Say "hi"'
  eq found[3][:command], 'notify-send "hi"'
  eq others, ["SUPER + T"]
end

test "writes Lua lines that read back the same" do
  entries = P.parse(%(bind "SUPER + P", "notify-send \\"hi\\" \\\\ ok", desc: "Say \\"hi\\""\nunbind "SUPER + SPACE"\n))
  lines = entries.map { |e| Omarchyfile::Bindings.line(e) }
  found, = Omarchyfile::Bindings.parse(lines.join("\n"))
  eq found[0][:command], 'notify-send "hi" \\ ok'
  eq found[0][:desc], 'Say "hi"'
  eq found[1], { kind: :unbind, keys: "SUPER + SPACE" }
end

test "inserts into one marked block and reuses it" do
  once = Omarchyfile::Bindings.insert("-- mine\n", ['hl.unbind("A")'])
  twice = Omarchyfile::Bindings.insert(once, ['o.bind("B", nil, "b")'])
  eq twice.scan(Omarchyfile::Bindings::BEGIN_MARK).size, 1
  raise "order wrong:\n#{twice}" unless twice.index('hl.unbind("A")') < twice.index('o.bind("B"') &&
                                      twice.index('o.bind("B"') < twice.index(Omarchyfile::Bindings::END_MARK)
  raise "user text lost" unless twice.start_with?("-- mine\n")
end

test "exports plain bindings with home paths made portable" do
  m = FakeMachine.new(bindings: USER_BINDINGS)
  text = Omarchyfile::Exporter.new(m).render
  raise "unbind missing" unless text.include?(%(unbind "SUPER + RETURN"\n))
  raise "home not rewritten:\n#{text}" unless text.include?(%(bind "SUPER + RETURN", "~/Development/jolt/target/release/jolt toggle", desc: "Jolt"))
  raise "nil desc wrong" unless text.include?(%(bind "SUPER + CTRL + ALT + S", "omarchy-shell tornikegomareli.spaces toggle"\n))
  raise "Lua binding not noted" unless text.include?("SUPER + T: keybinding runs Lua")
  raise "unbind must come before its bind" unless text.index('unbind "SUPER + RETURN"') < text.index('bind "SUPER + RETURN"')
end

test "a machine with bindings matches its own export" do
  m = FakeMachine.new(bindings: USER_BINDINGS)
  steps = Omarchyfile::Planner.new(P.parse(Omarchyfile::Exporter.new(m).render), m).steps
  eq steps.map(&:detail), []
end

test "adds a binding, replacing an Omarchy default with an unbind" do
  m = FakeMachine.new(commands: %w[zellij], default_bindings: { "SUPER + RETURN" => "Terminal" })
  steps = Omarchyfile::Planner.new(P.parse(%(bind "SUPER + RETURN", "uwsm-app -- zellij", desc: "Zellij"\n)), m).steps
  eq steps.first.detail, ['SUPER + RETURN replaces Omarchy\'s "Terminal"', "SUPER + RETURN runs uwsm-app -- zellij (Zellij)"]
  steps.first.run.call
  eq m.ran, [[:bindings, ['hl.unbind("SUPER + RETURN")', 'o.bind("SUPER + RETURN", "Zellij", "uwsm-app -- zellij")']]]
end

test "never overrides the user's own binding and skips missing programs" do
  m = FakeMachine.new(bindings: %(o.bind("SUPER + J", "Mine", "foot")\n), commands: %w[foot])
  file = %(bind "SUPER + J", "kitty"\nbind "SUPER + K", "~/bin/jolt toggle"\nbind "SUPER + L", "foot -e btop"\n)
  steps = Omarchyfile::Planner.new(P.parse(file), m).steps
  eq steps.reject(&:info).map(&:detail), [["SUPER + L runs foot -e btop"]]
  eq steps.select(&:info).map(&:detail), [["skip SUPER + J: you already bound it to foot", "skip SUPER + K: jolt is not installed here"]]
end

test "counts a program the same file installs as available" do
  m = FakeMachine.new
  steps = Omarchyfile::Planner.new(P.parse(%(pkg "zellij"\nbind "SUPER + Z", "zellij"\n)), m).steps
  eq steps.map(&:label), %w[Packages Keys]
end

test "skipped bindings alone do not count as changes" do
  Dir.mktmpdir do |dir|
    path = File.join(dir, "Omarchyfile")
    File.write(path, %(bind "SUPER + K", "~/bin/missing"\n))
    eq quietly { Omarchyfile::CLI.run(["check", path], machine: FakeMachine.new) }, 0
  end
end

test "rejects bindings that are not key combinations" do
  raises(/not a key combination/) { P.parse(%(bind "SUPER + ;", "x")) }
  raises(/needs a command/) { P.parse(%(bind "SUPER + X", "   ")) }
end

# ---------------------------------------------------------------- share

test "share creates a secret gist, then updates the same one" do
  Dir.mktmpdir do |dir|
    path = File.join(dir, "Omarchyfile")
    File.write(path, %(pkg "btop"\n))
    m = FakeMachine.new
    out = nil
    eq quietly { Omarchyfile::CLI.run(["share", path, "--yes"], machine: m) }, 0
    url = m.shares[File.expand_path(path)]["url"]
    eq m.gists[url], [%(pkg "btop"\n), false]
    File.write(path, %(pkg "btop"\npkg "yazi"\n))
    eq quietly { Omarchyfile::CLI.run(["share", path, "--yes"], machine: m) }, 0
    eq m.gists.size, 1
    eq m.gists[url][0], %(pkg "btop"\npkg "yazi"\n)
    eq quietly { Omarchyfile::CLI.run(["share", path, "--yes", "--new"], machine: m) }, 0
    eq m.gists.size, 2
  end
end

test "share asks first and stops when declined" do
  Dir.mktmpdir do |dir|
    path = File.join(dir, "Omarchyfile")
    File.write(path, %(pkg "btop"\n))
    m = FakeMachine.new(confirm: false)
    eq quietly { Omarchyfile::CLI.run(["share", path], machine: m) }, 1
    eq m.gists, {}
  end
end

test "summarizes what a share contains" do
  entries = P.parse(%(theme "ash"\npkg "a"\naur "b"\nwebapp "X", "https://x.com"\nbind "SUPER + A", "a"\n))
  eq Omarchyfile::CLI.summary(entries), "theme, 2 packages, 1 web app, 1 keybinding"
end

# ---------------------------------------------------------------- sync

test "merge keeps every file entry and adds this machine's" do
  file = P.parse(%(pkg "btop"\npkg "only-on-laptop"\nplugin "#{SPACES}.git", bar: "left"\nbind "super+a", "a"\n))
  mine = P.parse(%(pkg "btop"\npkg "yazi"\nplugin "#{SPACES}", bar: "right"\nbind "SUPER + A", "b"\n))
  merged = Omarchyfile::Merge.call(file, mine)
  eq merged.map { |e| Omarchyfile::Writer.line(e) }, [
    %(pkg "btop"), %(pkg "yazi"), %(plugin "#{SPACES}", bar: "right"), %(bind "SUPER + A", "b"), %(pkg "only-on-laptop"),
  ]
end

test "sync installs, merges, commits, and pushes" do
  Dir.mktmpdir do |dir|
    path = File.join(dir, "Omarchyfile")
    File.write(path, %(pkg "btop"\npkg "only-on-laptop"\n))
    m = FakeMachine.new(installed: %w[btop yazi], native: %w[btop yazi], git_root: dir, upstream: true)
    eq quietly { Omarchyfile::CLI.run(["sync", path, "--yes"], machine: m) }, 0
    eq m.ran.map { |c| c[0..3] }, [
      ["git", "-C", dir, "pull"],
      %w[omarchy pkg add only-on-laptop],
      ["git", "-C", dir, "add"],
      ["git", "-C", dir, "commit"],
      ["git", "-C", dir, "push"],
    ]
    text = File.read(path)
    %w[btop yazi only-on-laptop].each { |p| raise "#{p} missing after sync" unless text.include?(%(pkg "#{p}")) }
  end
end

test "sync does not commit when nothing changed" do
  Dir.mktmpdir do |dir|
    path = File.join(dir, "Omarchyfile")
    File.write(path, %(theme "solitude"\npkg "yazi"\n))
    m = FakeMachine.new(installed: %w[yazi], native: %w[yazi], git_root: dir)
    eq quietly { Omarchyfile::CLI.run(["sync", path, "--yes"], machine: m) }, 0
    eq m.ran, []
  end
end

test "sync explains how to start when there is no repository" do
  Dir.mktmpdir do |dir|
    path = File.join(dir, "Omarchyfile")
    File.write(path, %(pkg "yazi"\n))
    raises(/git repository/) { Omarchyfile::CLI.sync(path, { yes: true }, FakeMachine.new) }
  end
end

if $failed.positive?
  puts "#{$failed} failed"
  exit 1
end
