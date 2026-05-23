{
  private = {
    hostname = "private";
    interface = "ens18";
    ip = "10.0.20.5";
    gateway = "10.0.20.1";
    prefixLength = 24;
		nameservers = [ "8.8.8.8" "1.1.1.1" ];

		systemData = "/var/lib";
		userData = "/home/tagp/.local/share";
  };

  public = {
    hostname = "public";
    interface = "ens18";
    ip = "10.0.10.10";
    gateway = "10.0.10.1";
    prefixLength = 24;
		nameservers = [ "8.8.8.8" "1.1.1.1" ];

		systemData = "/var/lib";
		userData = "/home/tagp/.local/share";
  };

  media = {
    hostname = "media";
    interface = "ens18";
    ip = "10.2.10.10";
    gateway = "10.2.10.1";
    prefixLength = 24;
		nameservers = [ "1.1.1.1" "8.8.8.8" ];

		systemData = "/var/lib";
		userData = "/home/tagp/.local/share";
  };

  pangoling = {
    hostname = "pangoling";
    interface = "ens18";
    ip = "193.200.238.206";
    gateway = "193.200.238.1";
    prefixLength = 24;
		nameservers = [
			"79.161.9.164"   # Telenor
			"85.165.9.222"   # Telenor
			"94.127.122.231" # Altibox
			"1.1.1.1"        # Cloudflare
		];

		systemData = "/var/lib";
		userData = "/home/tagp/.local/share";
  };
}
