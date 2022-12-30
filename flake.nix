{
  description = "Application packaged using poetry2nix";

  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    let
      inherit (nixpkgs.lib) genAttrs removeSuffix flatten fold recursiveUpdate;

      makeRustComponent = { system, ... }@args:
        nixpkgs.legacyPackages.${system}.callPackage ./make-rust-component.nix
          (args // { inherit self; });

      versions = builtins.attrNames (builtins.readDir ./manifest);

      components = { version, system }:
        map (removeSuffix ".json")
        (builtins.attrNames (builtins.readDir ./manifest/${version}/${system}));

      systems = { version }:
        builtins.attrNames (builtins.readDir ./manifest/${version});

      packages = builtins.foldl' recursiveUpdate { } (flatten (map (version:
        map (system:
          map (component: {
            ${system}.${version}.${component} =
              makeRustComponent { inherit system component version; };
          }) (components { inherit system version; }))
        (systems { inherit version; })) versions));

      latest = system:
        let
          latestVersion = builtins.head
            (builtins.sort (a: b: (builtins.compareVersions a b) > 0)
              (builtins.attrNames packages.${system}));
        in packages.${system}.${latestVersion};

    in recursiveUpdate { inherit packages; }
    (flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
      let pkgs = import nixpkgs { inherit system; };
      in rec {

        packages = recursiveUpdate {
          latest = latest system;
          
          default = pkgs.symlinkJoin {
            name = "rust-${self.packages.${system}.latest.rustc.version}";
            paths = builtins.attrValues self.packages.${system}.latest;
          };
        } (latest system);

        devShells.default = pkgs.mkShell {
          packages = (with pkgs.nodePackages; [ bash-language-server ]);
        };
      }));
}
