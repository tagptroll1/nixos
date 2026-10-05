{ config, pkgs, ... }:
let
	# Probed by name from outside the mail host, so every check walks the same
	# path real clients do: DNS, the Pangolin VPS, the tunnel, then postfix or
	# dovecot on the public host. Port 587 is the VPS relay itself.
	host = "mail.yesbutmaybe.no";
in {
	# Posts to Discord when the mail server goes down and again when it
	# recovers. Only state changes are posted, so an outage is one message,
	# not one every run.
	systemd.services."mail-health" = {
		description = "Check ${host} and report state changes to Discord";
		path = [ pkgs.bash pkgs.curl pkgs.jq pkgs.openssl ];
		serviceConfig = {
			Type = "oneshot";
			DynamicUser = true;
			StateDirectory = "mail-health";
			LoadCredential = "webhook:${config.sops.secrets."discord/mail_webhook".path}";
		};
		script = ''
			# Postfix only sends 220 once the rspamd milter has answered, so this
			# also catches a wedged milter.
			smtp() {
				[ "$(timeout 20 bash -c "exec 3<>/dev/tcp/${host}/$1 && head -c 3 <&3" 2>/dev/null)" = "220" ]
			}

			# Verified TLS, so an expired or wrong certificate counts as down.
			imaps() {
				printf 'a LOGOUT\r\n' \
					| timeout 20 openssl s_client -quiet -connect ${host}:993 \
						-servername ${host} -verify_hostname ${host} -verify_return_error 2>/dev/null \
					| head -1 | grep -q '^\* OK'
			}

			failures=()
			smtp 25  || failures+=("SMTP 25 (inbound): no 220 greeting")
			smtp 587 || failures+=("Submission 587 (relay): no 220 greeting")
			imaps    || failures+=("IMAPS 993: no greeting over verified TLS")

			state=up
			if [ ''${#failures[@]} -gt 0 ]; then
				state=down
			fi

			last=$(cat "$STATE_DIRECTORY/state" 2>/dev/null || echo up)
			if [ "$state" = "$last" ]; then
				exit 0
			fi

			if [ "$state" = down ]; then
				msg="🔴 **${host} is down**"
				for f in "''${failures[@]}"; do
					msg+=$'\n'"- $f"
				done
			else
				msg="🟢 **${host} is back up**"
			fi
			echo "$msg"

			# State is saved only after Discord accepts the post, so a failed
			# post is retried on the next run.
			jq -n --arg content "$msg" '{content: $content}' \
				| curl -fsS --max-time 20 -H 'Content-Type: application/json' -d @- \
					"$(cat "$CREDENTIALS_DIRECTORY/webhook")"
			echo "$state" > "$STATE_DIRECTORY/state"
		'';
	};

	systemd.timers."mail-health" = {
		description = "Check ${host} every 5 minutes";
		wantedBy = [ "timers.target" ];
		timerConfig = {
			OnBootSec = "5min";
			OnUnitActiveSec = "5min";
			Unit = "mail-health.service";
		};
	};
}
