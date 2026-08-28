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

	# DNS-01 through the domeneshop plugin, with the propagation waits a new
	# name needs.
	#
	# Domeneshop spreads records across ns1/ns2/ns3.hyp.net slower than Caddy's
	# default zero delay, so Let's Encrypt's secondary validation reads a stale
	# challenge TXT and fails. This cost `git.ybmn.no` its first issuance. Any
	# vhost for a name that has never had a certificate wants this block.
	tlsDomeneshop = ''
		tls {
			dns domeneshop {
				token  {env.DOMENESHOP_API_TOKEN}
				secret {env.DOMENESHOP_API_SECRET}
			}
			propagation_delay   2m
			propagation_timeout 5m
		}
	'';
}
