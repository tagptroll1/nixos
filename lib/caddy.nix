# Caddy snippet builders, shared by the host's hand-written vhosts and by the
# `my.apps` module that generates one per app.
#
# The point of having them here rather than inline is that the LAN allowlist is
# written down exactly once. Widening it widens it for home-assistant, the
# ledger and every generated app at the same time, which is a decision worth
# making in one place instead of discovering in three.
{
	# Only serve to LAN + tailnet - blocks access from the public VM, internet
	# pivots, etc. Even if the MikroTik firewall is misconfigured, Caddy will
	# not serve these externally.
	#
	# Tailnet traffic arrives via a subnet router on the Server subnet
	# (10.0.0.0/24), which is why that range is in the list and why VPN access
	# works without a separate rule.
	lanOnly = upstream: ''
		@lan remote_ip 192.168.0.0/24 192.168.54.0/24 10.0.0.0/24
		handle @lan {
			reverse_proxy ${upstream}
		}
		respond "Access denied" 403
	'';

	# DNS-01 through the gigahost plugin (github.com/tagptroll1/caddy-dns-gigahost),
	# with the propagation waits a new name needs.
	#
	# A fresh challenge TXT has to reach all of ns1/ns2/ns3.gigahost.no before
	# Let's Encrypt validates, and its secondary validation asks from several
	# vantage points. With Caddy's default zero delay one of them can read a
	# stale answer and fail the order. Any vhost for a name that has never had a
	# certificate wants this block.
	#
	# GIGAHOST_API_KEY comes from the host's caddy/gigahost_env secret.
	tlsGigahost = ''
		tls {
			dns gigahost {
				api_key {env.GIGAHOST_API_KEY}
			}
			propagation_delay   2m
			propagation_timeout 5m
		}
	'';

	# The global default issuer config, for names whose vhost has no tls block.
	acmeDnsGigahost = ''
		acme_dns gigahost {
			api_key {env.GIGAHOST_API_KEY}
		}
	'';

	# Plugin pin shared by every Caddy host, so a fix lands everywhere at once.
	# The hash is the fixed-output hash of the built Caddy; leave it "" when the
	# version changes, rebuild, and paste the `got: sha256-...` it prints.
	gigahostPlugin = {
		plugins = [ "github.com/tagptroll1/caddy-dns-gigahost@v0.1.0" ];
		hash = "";
	};
}
