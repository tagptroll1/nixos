{ config, ... }: {
	services.homepage-dashboard = {
		enable = true;
		listenPort = 8082;
		allowedHosts = "home.ybmn.no";
		environmentFiles = [ config.sops.secrets."homepage/env".path ];
		settings = {
			title = "Home";
			headerStyle = "clean";
		};
		bookmarks = [
			{
				"Dev Tools" = [
					{ "IT Tools" = [{ href = "https://tools.ybmn.no"; icon = "it-tools.png"; }]; }
					{ "Forgejo"  = [{ href = "https://git.ybmn.no";   icon = "forgejo.png"; }]; }
				];
			}
			{
				"Sites" = [
					{ "yesbutmaybe.no" = [{ href = "https://yesbutmaybe.no";          icon = "mdi-web"; }]; }
					{ "Pangolin"       = [{ href = "https://pangolin.yesbutmaybe.no"; icon = "pangolin.png"; }]; }
				];
			}
		];
		services = [
			{
				"Home" = [
					{ "Home Assistant" = { href = "https://ass.ybmn.no";  description = "Smart home";    icon = "home-assistant.png"; }; }
					{ "Zigbee2MQTT"    = { href = "https://z2m.ybmn.no";  description = "Zigbee mesh";   icon = "zigbee2mqtt.png"; }; }
					{ "Mealie"         = { href = "https://recipe.ybmn.no"; description = "Recipes";     icon = "mealie.png"; }; }
					{ "Financio"       = { href = "https://bank.ybmn.no"; description = "Ledger";        icon = "mdi-bank"; }; }
					{ "Mova"           = { href = "https://mova.ybmn.no"; description = "Workout sheet"; icon = "mdi-dumbbell"; }; }
				];
			}
			{
				"Media" = [
					{ "Immich" = { href = "https://immich.ybmn.no"; description = "Photos"; icon = "immich.png"; }; }
				];
			}
			{
				"Files" = [
					{ "OpenCloud"   = { href = "https://cloud.ybmn.no"; description = "Cloud storage"; icon = "opencloud.png"; }; }
					{ "FileBrowser" = { href = "https://file.ybmn.no";  description = "Files";         icon = "filebrowser.png"; }; }
				];
			}
			{
				"Mail" = [
					{ "Webmail" = { href = "https://webmail.yesbutmaybe.no"; description = "yesbutmaybe.no"; icon = "roundcube.png"; }; }
				];
			}
			{
				"Services provided" = [
					{ "byggogbedrag.no"      = { href = "https://byggogbedrag.no";      description = "Website"; icon = "mdi-web"; }; }
					{ "mail.byggogbedrag.no" = { href = "https://mail.byggogbedrag.no"; description = "Mail";    icon = "roundcube.png"; }; }
				];
			}
			{
				"Games" = [
					{ "Factorio" = { href = "https://factorio.ybmn.no"; description = "Server manager"; icon = "factorio.png"; }; }
					{ "Palworld" = { href = "https://palworld.ybmn.no"; description = "Server admin";   icon = "palworld.png"; }; }
				];
			}
			{
				"Monitoring" = [
					{ "Grafana"          = { href = "http://10.0.0.5:3000";    description = "Metrics";      icon = "grafana.png"; }; }
					{ "Uptime Kuma"      = { href = "https://status.ybmn.no";  description = "Status";       icon = "uptime-kuma.png"; }; }
					{ "Change Detection" = { href = "https://change.ybmn.no";  description = "Page changes"; icon = "changedetection-io.png"; }; }
				];
			}
			{
				"Hypervisors" = [
					{ "Proxmox home01" = { href = "https://10.0.0.69:8006";   description = "Server VLAN";    icon = "proxmox.png"; }; }
					{
						"Proxmox home02" = {
							href        = "https://10.2.0.69:8006";
							description = "NAS / VLAN 200";
							icon        = "proxmox.png";
							# ZFS pool totals straight from Proxmox, in bytes. Needs the
							# MikroTik rule "private -> home02: homepage proxmox api".
							widget = {
								type    = "customapi";
								url     = "https://10.2.0.69:8006/api2/json/nodes/home02/storage/hddmirror/status";
								headers = { Authorization = "PVEAPIToken={{HOMEPAGE_VAR_PVE_TOKEN}}"; };
								refreshInterval = 300000;
								mappings = [
									{ field = { data = "used";  }; label = "Used";  format = "bytes"; }
									{ field = { data = "avail"; }; label = "Free";  format = "bytes"; }
									{ field = { data = "total"; }; label = "Total"; format = "bytes"; }
								];
							};
						};
					}
					{ "Cockpit media"  = { href = "https://cockpit.ybmn.no";  description = "media VM";       icon = "cockpit.png"; }; }
				];
			}
		];
		widgets = [
			{ resources = { cpu = true; memory = true; disk = "/"; }; }
			{ datetime = { text_size = "xl"; format = { timeStyle = "short"; dateStyle = "short"; }; }; }
		];
	};
}
