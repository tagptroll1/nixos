{ ... }: {
	systemd.services.prometheus-nginxlog-exporter.serviceConfig.SupplementaryGroups = [ "nginx" ];

	services.prometheus.exporters.node = {
		enable = true;
		port = 9100;
		listenAddress = "10.0.10.10";
		enabledCollectors = [ "systemd" "processes" ];
	};

	services.prometheus.exporters.nginxlog = {
		enable = true;
		port = 4040;
		listenAddress = "10.0.10.10";
		settings = {
			namespaces = [{
				name = "wordpress";
				source_files = [ "/var/log/nginx/wordpress_access.log" ];
				format = "$remote_addr - $remote_user [$time_local] \"$request\" $status $body_bytes_sent \"$http_referer\" \"$http_user_agent\" $request_time \"$http_x_forwarded_for\"";
				labels = { app = "wordpress"; };
				histogram_buckets = [ 0.005 0.01 0.025 0.05 0.1 0.25 0.5 1.0 2.5 5.0 10.0 ];
			}];
		};
	};
}
