{
  description = "arch-expert: typed Prolog expert system for system troubleshooting";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: nixpkgs.legacyPackages.${system};
    in
    {
      packages = forAll (system: rec {
        arch-expert = (pkgsFor system).callPackage ./package.nix { src = self; };
        default = arch-expert;
      });

      devShells = forAll (system: {
        default = (pkgsFor system).mkShell {
          packages = [ (pkgsFor system).swi-prolog ];
        };
      });
    };
}
