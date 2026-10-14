{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs";

  outputs =
    { nixpkgs, ... }:
    {
      packages.aarch64-darwin.lima = nixpkgs.legacyPackages.aarch64-darwin.lima.override {
        withAdditionalGuestAgents = true;
      };
    };
}
