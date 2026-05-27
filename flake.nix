{
  description = "LINE for Windows on NixOS via Wine — fully declarative, snapshot-based";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  outputs =
    {
      self,
      nixpkgs,
      treefmt-nix,
    }:
    let
      inherit (nixpkgs) lib;

      forAllSystems = lib.genAttrs lib.systems.flakeExposed;

      treefmtEval = forAllSystems (
        system: treefmt-nix.lib.evalModule nixpkgs.legacyPackages.${system} ./treefmt.nix
      );
    in
    let
      perSystem = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) [ "line-messenger" ];
          };
          line-messenger = pkgs.callPackage ./nix/package.nix { };
        in
        {
          inherit line-messenger;
          inherit pkgs;
        }
      );
    in
    {
      packages = forAllSystems (system: {
        default = perSystem.${system}.line-messenger;
        line-messenger = perSystem.${system}.line-messenger;
      });

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${perSystem.${system}.line-messenger}/bin/line";
        };
      });

      homeManagerModules.default = import ./nix/hm-module.nix self;
      homeManagerModules.line-messenger = self.homeManagerModules.default;

      overlays.default = final: prev: {
        line-messenger = final.callPackage ./nix/package.nix { };
      };

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          inherit (pkgs) mkShell prek;
        in
        {
          default = mkShell {
            packages = [
              prek
              self.formatter.${system}
            ];
          };
        }
      );

      formatter = forAllSystems (system: treefmtEval.${system}.config.build.wrapper);
      checks = forAllSystems (system: {
        formatting = treefmtEval.${system}.config.build.check self;
      });
    };
}
