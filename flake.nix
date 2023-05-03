{
  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-unstable;
    flake-utils.url = github:numtide/flake-utils;
  };
  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in {
        devShell = pkgs.mkShell {
          buildInputs = with pkgs; [
            julia-bin
            awscli2
            qt6.full
          ];
          shellHook = ''
            [ -z "''${AWS_PROFILE}" ] && export AWS_PROFILE=personal
            export JULIA_LOAD_PATH=@
            command -v fish &> /dev/null && fish
          '';
        };
      });
}

