# NetBird overlay client. Enroll after first activation with:
#   sudo netbird up
# Credentials live under /var/lib/netbird and survive rebuilds.
{ ... }: {
	services.netbird.enable = true;
}
