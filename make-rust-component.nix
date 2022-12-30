{ self, lib, version, component, system, autoPatchelfHook, zlib, stdenv, runCommand }:
let

  manifest = builtins.fromJSON
    (builtins.readFile ./manifest/${version}/${system}/${component}.json);

  rustLibs = lib.optional (component != "rustc")
    self.packages.${system}.${version}.rustc;

in stdenv.mkDerivation rec {
  pname = component;
  inherit version;

  buildInputs = [ zlib ] ++ rustLibs;

  nativeBuildInputs = [ autoPatchelfHook ];

  sourceRoot = manifest.path;

  src = builtins.fetchurl {
    url = manifest.url;
    sha256 = manifest.hash;
  };

  installPhase = ''
    runHook preInstall

    mkdir -p "$out"
    cp -rv */ "$out"

    runHook postInstall
  '';
}
