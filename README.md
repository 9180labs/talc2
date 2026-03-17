# talc2

Map local services to `*.internal` domains with HTTPS — no `/etc/hosts` edits required.

talc2 glues together **dnsmasq** (wildcard DNS) and **Caddy** (reverse proxy + TLS) so you can reach any local dev service at `myapp.internal` instead of `localhost:3000`.

```
App → systemd-resolved → dnsmasq:5335 (*.internal) → Caddy → localhost:PORT
```

## Requirements

- Arch Linux (uses `pacman` for dependency installation)
- `bash` 5+
- `systemd-resolved`
- [`gum`](https://github.com/charmbracelet/gum) — installed separately; degrades to plain text if absent

`talc setup` installs `caddy` and `dnsmasq` automatically.

## Installation

```bash
git clone https://github.com/yourname/talc2
cd talc2
sudo ln -s "$PWD/talc" /usr/local/bin/talc
```

Then run first-time setup:

```bash
talc setup
```

This installs dependencies, configures dnsmasq + systemd-resolved, generates a wildcard TLS cert, and starts both services.

## Usage

```
talc <command> [options]

Commands:
  setup                    Install deps, configure DNS + proxy
  add DOMAIN               Add a domain   (--port PORT, --ip IP)
  remove DOMAIN            Remove a domain
  list                     List domains   (--format table|json|plain)
  update DOMAIN            Update a domain (--port PORT, --ip IP)
  status                   Show system status
  teardown                 Remove all talc2 config

Global flags:
  --verbose, -v            Verbose output
  --help, -h               Help
```

### Examples

```bash
# Add a domain interactively
talc add

# Add non-interactively
talc add myapp --port 3000

# Point to a specific IP (default: auto-detected LAN IP)
talc add api --port 4000 --ip 192.168.1.50

# List domains as JSON
talc list --format json

# Remove a domain
talc remove myapp
```

## Trusting the TLS certificate

talc2 generates a self-signed wildcard cert for `*.internal`. To avoid browser warnings, add it to your system's trust store:

```bash
sudo trust anchor /etc/caddy/certs/internal.crt
```

## Allowing `.internal` domains in your app

Some frameworks block requests from unrecognized hosts by default. After running `talc add myapp --port 3000`, you'll need to whitelist `myapp.internal`.

**Rails** (`config/environments/development.rb`):

```ruby
Rails.application.configure do
  config.hosts << "myapp.internal"
end
```

Or use a pattern to allow any subdomain:

```ruby
config.hosts << /.*\.internal/
```

## Configuration

Config lives at `~/.config/talc2/config.env`:

```bash
TALC_DOMAIN_SUFFIX='internal'   # change to use a different TLD
TALC_LOCAL_IP='auto'            # or set a fixed IP
TALC_CADDY_API='http://localhost:2019'
TALC_CERTS_DIR='/etc/caddy/certs'
TALC_ENABLE_TLS='true'
```

## Storage

Domains are stored as TSV at `~/.config/talc2/domains.tsv`. Writes are `flock`-protected.
