# Mails a report when a systemd unit fails. Add to any unit with:
#   onFailure = [ "notify-failure@%n.service" ];
#
# Delivery is local: postfix drops it straight into the mailbox on the public
# host, so alerts still arrive when outbound relaying is broken. Sending them
# through the smarthost would mean the one failure most worth knowing about,
# mail being down, is also the one that silences the alert.
{ pkgs, hostConfig, ... }:
let
	recipient = "thomas@yesbutmaybe.no";

	notify = pkgs.writeShellScript "notify-failure" ''
		unit="$1"
		{
			echo "To: ${recipient}"
			echo "Subject: [${hostConfig.hostname}] $unit failed"
			echo ""
			${pkgs.systemd}/bin/systemctl status --full --lines=0 "$unit" || true
			echo ""
			echo "--- last 100 journal lines ---"
			${pkgs.systemd}/bin/journalctl -u "$unit" -n 100 --no-pager || true
		} | /run/wrappers/bin/sendmail -t
	'';
in {
	systemd.services."notify-failure@" = {
		description = "Mail a failure report for %i";
		serviceConfig = {
			Type      = "oneshot";
			ExecStart = "${notify} %i";
		};
	};
}
