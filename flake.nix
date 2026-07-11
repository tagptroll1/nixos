{
  description = "Tagps NixOS Config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nvim-config = {
      url = "github:tagptroll1/nvim";
      flake = false;
    };
    quadlet-nix = {
      url = "github:SEIAROTg/quadlet-nix";
    };
    simple-nixos-mailserver = {
      url = "gitlab:simple-nixos-mailserver/nixos-mailserver/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, sops-nix, quadlet-nix, simple-nixos-mailserver, ... }@inputs:
  let
    hosts = import ./lib/hosts.nix;
  in
  {
    # Exposed so the prophunt plugin's NuGet lock can be generated:
    #   nix build .#cs2-prophunt.fetch-deps && ./result pkgs/cs2-prophunt/deps.json
    packages.x86_64-linux.cs2-prophunt =
      nixpkgs.legacyPackages.x86_64-linux.callPackage ./pkgs/cs2-prophunt { };

    nixosConfigurations = {
      private = nixpkgs.lib.nixosSystem {
        specialArgs = {
          inherit inputs;
          hostConfig = hosts.private;
        };
        modules = [
          sops-nix.nixosModules.sops
          quadlet-nix.nixosModules.quadlet
          ./hosts/private
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs; hostConfig = hosts.private; };
            home-manager.users.tagp = import ./home/tagp;
            home-manager.users.podman = import ./hosts/private/home-rootless.nix;
          }
        ];
      };

      public = nixpkgs.lib.nixosSystem {
        specialArgs = {
          inherit inputs;
          hostConfig = hosts.public;
        };
        modules = [
          sops-nix.nixosModules.sops
          simple-nixos-mailserver.nixosModules.mailserver
          ./hosts/public
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs; hostConfig = hosts.public; };
            home-manager.users.tagp = import ./home/tagp;
          }
        ];
      };

      # VPS: Pangolin ingress + outbound mail relay for yesbutmaybe.no.
      pangolin = nixpkgs.lib.nixosSystem {
        specialArgs = {
          inherit inputs;
          hostConfig = hosts.pangolin;
        };
        modules = [
          sops-nix.nixosModules.sops
          ./hosts/pangolin
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs; hostConfig = hosts.pangolin; };
            home-manager.users.tagp = import ./home/tagp;
          }
        ];
      };

      media = nixpkgs.lib.nixosSystem {
        specialArgs = {
          inherit inputs;
          hostConfig = hosts.media;
        };
        modules = [
          sops-nix.nixosModules.sops
          ./hosts/media
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs; hostConfig = hosts.media; };
            home-manager.users.tagp = import ./home/tagp;
          }
        ];
      };
    };
  };
}
