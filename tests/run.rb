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

if $failed.positive?
  puts "#{$failed} failed"
  exit 1
end
