# NixOS Configuration

## What is this?
This project is a collection of all my nixOS configurations for multiple hosts and the extensibiltiy of multiple users.

## Why does this exist?
I nuked my home directly at one point, and figured it would be nice be able to start up my server again without having to manually reinstall everything.

## Hosts
### Private
This is a collection of services and setup that is run on a private network. 
The network is only accessible from without my local network, with its own ip range for services.

I use the domain ybmn.no to get a SSL Certificate to secure the traffic (and remove any annyoing browser warnings :) )

### Public
This is a collection of services that are exposed to the world. This host runs on an isolated network,
with firewall rules that prevent any connections to any other network. It is exclusively internet only.
Other services and my "default" home network can connect to it, but it does not know about them itself.

Connections are provided through a wireguard tunnel running on my VPS. Pangolin, gerbil and newt are the engines that
control this setup. Which provides a layer of security towards exposing my machine to the world. 
yesbutmaybe.no is the domain used for public access.

## Proxmox
Proxmos is the chosen hyporvisor for running multiple containers on my home server.
It currently runs:
- Grafana (LXC)
- Prometheus (LXC)
- Proxmox export for promethues (LXC)
- Private (NixOS VM)
- Public (NixOS VM)

## Secrets
All secrets stored in this repo are encrypted with post-quantum safe algorithmns. That gives me a sense of security for the future
when i expose them to the internet in this repo, the way I have. The downside in doing this is that I will have to 
manage the age private & public keys manually whenever i setup any of the configured machines. I lose the ability to
use convenience tools like ssh-to-age key conversion. Which is also one of the reasons I included a 
proton-pass-cli nix package wrapper in the config. This should give me quicker access to the age secret whenever setting up a new machine.


## Services running on the machines
### Private
- Uptime Kuma
- Filebrowser
- Homepage

### Public
- Portfolios
- Wordpress
- Email server

More to come..


## User


## TODO:
- Write down every manual task done outside of the nixos configuration
    - Domeneshop DNS Records
    - Domeneshop API Keys
    - Gigahost panel (PTR record for the pangolin VPS)
    - Age public key in .sops.yaml (on my machine)
- Install other cool services
    - Immich
- Build NAS with backup and data redundancy
    - Multiple Disks with RAID
    - Off-site backup (external disk)
    - Maybe trust the data overloads with a cloud storage backup
