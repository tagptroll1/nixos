# Encrypted DNS, for the hosts that resolve names on the open internet.
#
# The problem this fixes is not "which company answers the query" but "who else
# reads it on the way": plain port-53 lookups are visible to the ISP and to
# every hop in between, and they name every service the host talks to before a
# single byte of the actual connection is sent.
#
# Quad9 rather than 1.1.1.1 or 8.8.8.8: a Swiss non-profit foundation, no
# storage of client addresses, QNAME minimisation, and no EDNS client-subnet -
# so the query does not carry a fragment of the asker's address to the
# authoritative server either. It also blocks known malware and phishing
# domains, which is worth having on hosts that fetch pages nobody vetted.
# 9.9.9.10 / 149.112.112.10 are the same service without that blocklist, if a
# legitimate name is ever caught by it.
#
# Two resolvers that used to belong in this comment are gone: Mullvad shut its
# public DNS down in November 2026 and put its funding behind Quad9, and
# dns0.eu was discontinued in October 2025. Check before swapping to something
# a guide recommends.
{ hostConfig, lib, ... }: {
  services.resolved = {
    enable = true;

    # Written through `settings` rather than the shorter aliases
    # (services.resolved.dnsovertls and friends), which are deprecated and warn
    # on every evaluation.
    settings.Resolve = {
      # Strict, not opportunistic. Opportunistic mode falls back to plaintext
      # the moment anything interferes with port 853, which is precisely when
      # you would want it not to - the failure has to be visible, not silent.
      DNSOverTLS = "true";

      # Integrity rather than privacy, and Quad9 already validates upstream
      # over a channel this host authenticates. `allow-downgrade` keeps a
      # domain with a broken chain from turning into an unexplainable SERVFAIL
      # here.
      DNSSEC = "allow-downgrade";

      # Used when the configured servers are unreachable. Left pointing at the
      # same place on purpose: the stock fallback list is Cloudflare and
      # Google, which would quietly undo all of the above at the worst moment.
      FallbackDNS = [
        "9.9.9.9#dns.quad9.net"
        "149.112.112.112#dns.quad9.net"
      ];

      # Nothing here discovers peers by name.
      LLMNR = "false";
    };
  };

  # The `#hostname` suffix is what makes this DNS-over-TLS rather than DNS-over-
  # a-TLS-socket-to-whoever-answered: resolved verifies the certificate against
  # that name. Without it, strict mode still encrypts but authenticates nothing.
  #
  # mkForce because hosts/*/modules/networking.nix already sets this from
  # hostConfig; list options merge by concatenation, so without it the plain
  # addresses would sit alongside these and get used unencrypted.
  networking.nameservers =
    lib.mkForce (map (addr: "${addr}#dns.quad9.net") hostConfig.nameservers);
}
