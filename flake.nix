{
  description = "My Bastion modules flake";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
  outputs = { self, nixpkgs, }: {
    nixosModules.bastion = import ./modules;
    formatter = nixpkgs.legacyPackages.x86_64-linux.alejandra;
  };
}
