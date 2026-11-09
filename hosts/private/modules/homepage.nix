{ config, lib, pkgs, ... }: {
	services.homepage-dashboard = {
		enable = true;
		listenPort = 8082;
		allowedHosts = "home.ybmn.no";
		environmentFiles = [ config.sops.secrets."homepage/env".path ];
		services = [
			{
				"Daily" = [
					{ "Home Assistant" = { href = "https://ass.ybmn.no";            description = "Smart home";    icon = "home-assistant.png"; }; }
					{ "Immich"         = { href = "https://immich.ybmn.no";         description = "Photos";        icon = "immich.png"; }; }
					{ "OpenCloud"      = { href = "https://cloud.ybmn.no";          description = "Cloud storage"; icon = "sh-opencloud.png"; }; }
					{ "Mealie"         = { href = "https://recipe.ybmn.no";         description = "Recipes";       icon = "mealie.png"; }; }
					{ "Financio"       = { href = "https://bank.ybmn.no";           description = "Ledger";        icon = "mdi-bank"; }; }
					{ "Mova"           = { href = "https://mova.ybmn.no";           description = "Workout sheet"; icon = "mdi-dumbbell"; }; }
					{ "Webmail"        = { href = "https://webmail.yesbutmaybe.no"; description = "yesbutmaybe.no"; icon = "roundcube.png"; }; }
					{ "FileBrowser"    = { href = "https://file.ybmn.no";           description = "Files";         icon = "filebrowser.png"; }; }
				];
			}
			{
				"Status" = [
					{
						"Proxmox home02" = {
							href        = "https://10.2.0.69:8006";
							description = "hddmirror storage";
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
					{ "Uptime Kuma"      = { href = "https://status.ybmn.no"; description = "Status";       icon = "uptime-kuma.png"; }; }
					{ "Grafana"          = { href = "http://10.0.0.5:3000";   description = "Metrics";      icon = "grafana.png"; }; }
					{ "Change Detection" = { href = "https://change.ybmn.no"; description = "Page changes"; icon = "changedetection.png"; }; }
				];
			}
			{
				"Infrastructure" = [
					{ "Proxmox home01" = { href = "https://10.0.0.69:8006";          description = "Server VLAN"; icon = "proxmox.png"; }; }
					{ "Cockpit media"  = { href = "https://cockpit.ybmn.no";         description = "media VM";    icon = "cockpit.png"; }; }
					{ "Zigbee2MQTT"    = { href = "https://z2m.ybmn.no";             description = "Zigbee mesh"; icon = "zigbee2mqtt.png"; }; }
					{ "Pangolin"       = { href = "https://pangolin.yesbutmaybe.no"; description = "Ingress";     icon = "pangolin.png"; }; }
				];
			}
			{
				"Hosting" = [
					{ "yesbutmaybe.no"       = { href = "https://yesbutmaybe.no";       description = "Website"; icon = "mdi-web"; }; }
					{ "byggogbedrag.no"      = { href = "https://byggogbedrag.no";      description = "Website"; icon = "mdi-web"; }; }
					{ "mail.byggogbedrag.no" = { href = "https://mail.byggogbedrag.no"; description = "Mail";    icon = "roundcube.png"; }; }
				];
			}
			{
				"Tools & games" = [
					{ "Forgejo"  = { href = "https://git.ybmn.no";      description = "Git";            icon = "forgejo.png"; }; }
					{ "IT Tools" = { href = "https://tools.ybmn.no";    description = "Dev utilities";  icon = "it-tools.png"; }; }
					{ "Factorio" = { href = "https://factorio.ybmn.no"; description = "Server manager"; icon = "factorio.png"; }; }
					{ "Palworld" = { href = "https://palworld.ybmn.no"; description = "Server admin";   icon = "palworld.png"; }; }
				];
			}
		];
		widgets = [
			{ resources = { cpu = true; memory = true; disk = "/"; }; }
			{ datetime = { text_size = "xl"; format = { timeStyle = "short"; dateStyle = "short"; }; }; }
		];
	};

	# Written as YAML text rather than through `settings`: homepage orders groups
	# by the key order of `layout`, and a Nix attrset serialises alphabetically.
	environment.etc."homepage-dashboard/settings.yaml".source = lib.mkForce (pkgs.writeText "settings.yaml" ''
    title: Home
    headerStyle: clean
    layout:
      Daily:
        style: row
        columns: 4
      Status:
        style: row
        columns: 4
      Infrastructure:
        style: column
      Hosting:
        style: column
      "Tools & games":
        style: column
  '');
}
