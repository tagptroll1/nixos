{ config, lib, ... }: {
  mailserver = {
    enable = true;
    fqdn = "mail.yesbutmaybe.no";
    sendingFqdn = "mail.yesbutmaybe.no";
    domains = [
      "yesbutmaybe.no"
      "byggogbedrag.no"
    ];

    enableSubmission = true;
    enableSubmissionSsl = false; # 587 uses STARTTLS, not SSL

    stateVersion = 5;

    storage.path = "/var/vmail";
    dkim.keyDirectory = "/var/dkim";

    accounts = {
      "thomas@yesbutmaybe.no" = {
        hashedPasswordFile = config.sops.secrets."mail_hashed_password".path;
        aliases = [ "admin@yesbutmaybe.no" ];
        # Catch-all: any address @yesbutmaybe.no that isn't another
        # account or alias is delivered here.
        catchAll = [ "yesbutmaybe.no" ];
      };
      "grafana@yesbutmaybe.no" = {
        hashedPasswordFile = config.sops.secrets."mail_grafana_hashed_password".path;
      };
      "changes@yesbutmaybe.no" = {
        hashedPasswordFile = config.sops.secrets."mail_changes_hashed_password".path;
      };
      "post@byggogbedrag.no" = {
        hashedPasswordFile = config.sops.secrets."mail_byggogbedrag_hashed_password".path;
        # Catch-all: any *@byggogbedrag.no not another account/alias lands here.
        catchAll = [ "byggogbedrag.no" ];
      };
    };

    # Forward everything that lands in post@byggogbedrag.no (incl. catch-all)
    # to the main inbox. Listing the address itself keeps a local copy too —
    # postfix delivers the self-reference locally, no loop.
    forwards = {
      "post@byggogbedrag.no" = [
        "post@byggogbedrag.no"
        "thomas@petersson.priv.no"
      ];
    };

    x509.useACMEHost = "mail.yesbutmaybe.no";
  };

  # ACME cert for the mail server via Domeneshop DNS-01
  security.acme = {
    acceptTerms = true;
    defaults.email = "admin@yesbutmaybe.no";

    certs."mail.yesbutmaybe.no" = {
      domain = "mail.yesbutmaybe.no";
      dnsProvider = "domeneshop";
      credentialFiles = {
        "DOMENESHOP_API_TOKEN_FILE" = config.sops.secrets."domeneshop_api_token".path;
        "DOMENESHOP_API_SECRET_FILE" = config.sops.secrets."domeneshop_api_secret".path;
      };
    };
  };

  # Give mail services access to the ACME cert
  users.users.dovecot2.extraGroups = [ "acme" ];
  users.users.postfix.extraGroups = [ "acme" ];

  services.postfix.settings.main = {
    relayhost = [ "[193.200.238.206]:587" ];
    # Single hosts only, not whole subnets — any device in a trusted range
    # can relay unauthenticated with our domain reputation.
    #
    # NEVER add 10.0.10.10 (own LAN IP): newt dials tunneled connections
    # from that address, so every internet client on the Pangolin-forwarded
    # mail ports would be trusted — that made us an open relay (abused
    # 2026-06-28, caught in queue). Roundcube and the byggogbedrag app
    # authenticate with SASL and need no IP trust. Same reason the Pangolin
    # targets for 25/587 must stay 10.0.10.10, not localhost — 127.0.0.1
    # is in mynetworks.
    mynetworks = [
      "127.0.0.0/8"
      "10.0.20.5/32" # private host — trusted relay, no auth needed
    ];
    # Authenticate to the Pangolin VPS smarthost. Home WAN IP is dynamic,
    # so IP-based mynetworks trust on the VPS breaks on every ISP rotation;
    # SASL survives it. Creds live in sops; TLS required so they aren't sent
    # in clear.
    smtp_sasl_auth_enable = "yes";
    smtp_sasl_password_maps = [ "texthash:${config.sops.secrets."mail_relay_sasl_passwd".path}" ];
    smtp_sasl_security_options = "noanonymous";
    # Override the module's DANE default — relayhost has no TLSA record and
    # all outbound goes through it, so require STARTTLS to protect the creds.
    smtp_tls_security_level = lib.mkForce "encrypt";
    myorigin = "yesbutmaybe.no";
    mydomain = "yesbutmaybe.no";
    myhostname = "mail.yesbutmaybe.no";
    masquerade_domains = [ "yesbutmaybe.no" ];
  };
}
