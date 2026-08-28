# One declaration per app, everything else generated.
#
# Adding an app by hand means a quadlet container, a Caddy vhost, a sops entry,
# a state directory, an env file, a watcher that restarts it, and a line in the
# restic job. Seven places, and the one that gets forgotten is always the
# backup. So they are generated from a single attribute set instead:
#
#   my.apps.grafana = {
#     image  = "git.ybmn.no/tagp/grafana:master";
#     port   = 8090;
#     domain = "graf.ybmn.no";
#   };
#
# What this deliberately does NOT do is decide versions. The image tag is a
# moving target and `podman auto-update` reconciles it on a timer, so shipping a
# new build is a registry push, not a rebuild. See docs/app-deployments.md.
#
# It lives under hosts/private rather than shared/ because it writes into
# `services.restic.backups.private`, which only exists on this host. Moving it
# to shared/ when a second host wants it is a file move plus making that
# reference conditional.
{ config, lib, pkgs, ... }:
let
	inherit (lib)
		mkOption types mapAttrs mapAttrs' mapAttrsToList nameValuePair
		filterAttrs optional optionalAttrs concatLists;

	caddyLib = import ../../../lib/caddy.nix;

	cfg  = config.my;
	apps = cfg.apps;

	# Mutable, on purpose: the whole point of this directory is config that
	# changes without a rebuild. Nothing in the nix store may reference it.
	envDir  = "/var/lib/appenv";
	envFile = name: "${envDir}/${name}.env";

	stateDir = name: "/var/lib/${name}";

	# Ports the host already listens on. An app that picks one of these gets a
	# container that will not bind, discovered at 2am rather than at eval.
	reservedPorts = [
		80    # caddy
		443   # caddy
		2222  # forgejo built-in ssh
		3000  # forgejo web
		3001  # uptime-kuma
		3030  # filebrowser
		8080  # hello container
		8082  # homepage
		8086  # financio
		8123  # home-assistant
		8124  # zigbee2mqtt
	];

	withState  = filterAttrs (_: a: a.state)             apps;
	withDomain = filterAttrs (_: a: a.domain != null)    apps;
	withSecret = filterAttrs (_: a: a.secretFile != null) apps;

	allPorts = mapAttrsToList (_: a: a.port) apps;
in {
	options.my = {
		# podman-auto-update pulls as root and needs credentials for a private
		# registry, which the Forgejo one is. Point this at a sops secret
		# holding a docker config json; it becomes the
		# io.containers.autoupdate.authfile label on every auto-updating app.
		# Without it, every pull from git.ybmn.no answers 401 and the app simply
		# never updates - quietly, because auto-update is a timer, not a build.
		registryAuthFile = mkOption {
			type    = types.nullOr types.str;
			default = null;
			example = "/run/secrets/registry/auth";
			description = "authfile podman auto-update uses to pull private images";
		};

		apps = mkOption {
			default     = { };
			description = "containerised apps on this host";
			type = types.attrsOf (types.submodule ({ name, config, ... }: {
				options = {
					image = mkOption {
						type    = types.str;
						example = "git.ybmn.no/tagp/grafana:master";
						description = ''
							Fully qualified image reference including the tag.
							The tag must be a moving one (`master`, `latest`) or
							auto-update has nothing to reconcile against - it
							compares digests behind a tag, it does not discover
							new tags.
						'';
					};

					port = mkOption {
						type        = types.port;
						description = "loopback port on the host Caddy proxies to";
					};

					containerPort = mkOption {
						type        = types.port;
						default     = config.port;
						description = "port inside the container, if it differs";
					};

					domain = mkOption {
						type    = types.nullOr types.str;
						default = null;
						example = "graf.ybmn.no";
						description = ''
							Name to serve it on. null means no vhost at all -
							for something only reached from the host itself.
							The DNS record is yours to create; nothing here can.
						'';
					};

					lanOnly = mkOption {
						type    = types.bool;
						default = true;
						description = ''
							Serve only to LAN + tailnet. Defaults on because
							almost nothing here authenticates, and the one that
							does should still say so explicitly.
						'';
					};

					secretFile = mkOption {
						type    = types.nullOr types.path;
						default = null;
						example = "./containers/grafana/secret.yaml";
						description = ''
							sops file with a key `env` holding a dotenv blob.
							Changing it needs a rebuild - sops-nix decrypts from
							a store path pinned at switch time. Anything that
							should change without one belongs in the mutable env
							file instead.
						'';
					};

					env = mkOption {
						type    = types.attrsOf types.str;
						default = { };
						description = ''
							Static environment, baked into the unit. Overridden
							by both env files, so it is the place for values
							that are part of the app's definition rather than
							its operation.
						'';
					};

					state = mkOption {
						type    = types.bool;
						default = true;
						description = ''
							Create /var/lib/<name>, mount it, and back it up.
							Opt-out rather than opt-in: the app whose backup
							nobody remembered to add is the one that needed it.
						'';
					};

					stateMount = mkOption {
						type        = types.str;
						default     = "/data";
						description = "where the state directory appears inside the container";
					};

					memory = mkOption {
						type    = types.str;
						default = "512m";
						description = ''
							Hard cap. Set so one app cannot take the host down
							with it; raise per app when it earns it.
						'';
					};

					autoUpdate = mkOption {
						type    = types.bool;
						default = true;
						description = "let podman-auto-update roll this forward when the tag moves";
					};

					extraContainerConfig = mkOption {
						type    = types.attrs;
						default = { };
						description = ''
							Escape hatch, merged over the generated
							containerConfig. Option names come from
							quadlet-nix's container.nix, not from podman.
						'';
					};
				};
			}));
		};
	};

	config = {
		assertions = [
			{
				assertion = lib.length allPorts == lib.length (lib.unique allPorts);
				message   = "my.apps: two apps share a port (${toString allPorts})";
			}
			{
				assertion = lib.intersectLists allPorts reservedPorts == [ ];
				message   = "my.apps: port already used by this host (${toString (lib.intersectLists allPorts reservedPorts)})";
			}
		];

		virtualisation.quadlet.containers = mapAttrs (name: a: {
			autoStart = true;

			containerConfig = {
				image = a.image;

				# The label podman-auto-update looks for. Without it the
				# container is invisible to the timer.
				autoUpdate = if a.autoUpdate then "registry" else null;

				# Loopback only. Caddy is on this host and is the access
				# control; publishing on the interface would route around it.
				publishPorts = [ "127.0.0.1:${toString a.port}:${toString a.containerPort}" ];

				environments = a.env;

				# Order matters: podman reads these left to right, and the
				# mutable file is last so an operator can override a value
				# without a rebuild.
				environmentFiles =
					(optional (a.secretFile != null) config.sops.secrets."${name}/env".path)
					++ [ (envFile name) ];

				volumes = optional a.state "${stateDir name}:${a.stateMount}";

				memory           = a.memory;
				noNewPrivileges  = true;
				dropCapabilities = [ "ALL" ];

				labels = optionalAttrs (cfg.registryAuthFile != null && a.autoUpdate) {
					"io.containers.autoupdate.authfile" = cfg.registryAuthFile;
				};
			} // a.extraContainerConfig;

			serviceConfig = {
				Restart    = "on-failure";
				RestartSec = "10";
			};
		}) apps;

		# Every generated vhost asks for DNS-01 with the propagation waits, not
		# just new ones: a name that already has a certificate ignores the block
		# until renewal, and a name that does not would otherwise fail its first
		# issuance the way git.ybmn.no did.
		services.caddy.virtualHosts = mapAttrs' (name: a:
			nameValuePair a.domain {
				extraConfig =
					(if a.lanOnly
					 then caddyLib.lanOnly "127.0.0.1:${toString a.port}"
					 else "reverse_proxy 127.0.0.1:${toString a.port}")
					+ caddyLib.tlsDomeneshop;
			}) withDomain;

		# 0400 and root-owned: containers are rootful here, so podman reads it
		# as root and nothing else needs to.
		sops.secrets = mapAttrs' (name: a:
			nameValuePair "${name}/env" {
				sopsFile = a.secretFile;
				key      = "env";
				mode     = "0400";
			}) withSecret;

		systemd.tmpfiles.rules =
			# Also read by financio.nix, which is not a container and so not in
			# my.apps. This module owns the directory.
			[ "d ${envDir} 0750 root root - -" ]

			# `f` creates it empty when missing and never touches it again, so a
			# rebuild cannot clobber an edit. It has to exist before the
			# container starts: podman fails a missing --env-file outright.
			++ mapAttrsToList (name: _: "f ${envFile name} 0640 root root - -") apps

			++ mapAttrsToList (name: _: "d ${stateDir name} 0700 root root - -") withState;

		# PathChanged rather than PathModified: `sudo -e` and vim write a new
		# file and rename it over the old one, which is a change of the path
		# rather than a write to the inode.
		systemd.paths = mapAttrs' (name: _:
			nameValuePair "${name}-env" {
				description = "${name} env watcher";
				wantedBy    = [ "multi-user.target" ];

				pathConfig.PathChanged = envFile name;
			}) apps;

		systemd.services = mapAttrs' (name: _:
			nameValuePair "${name}-env" {
				description = "restart ${name} after an env change";

				path = [ pkgs.systemd ];

				serviceConfig.Type = "oneshot";

				# quadlet-nix names the generated unit after the attribute, so
				# `my.apps.grafana` is grafana.service. Restarting re-creates
				# the container, which is what re-reads the env files.
				script = ''
					echo "restarting ${name} after an env change"
					systemctl restart ${name}.service
				'';
			}) apps;

		services.restic.backups.private.paths =
			mapAttrsToList (name: _: stateDir name) withState;
	};
}
