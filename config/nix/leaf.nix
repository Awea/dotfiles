# Leaf, the markdown view of the Renux file peek (bin.symlink/renux-open): the release
# binary of https://github.com/DeepanshuMishraa/leaf, with the SHA-256 that the release
# publishes. The package.nix of Leaf builds from source but is at 0.16.2 and lacks the
# ALSA library that the Linux build needs. Do not run `leaf upgrade`: the Nix store is
# read-only. To update, change the version and the 4 hashes (the .sha256 files of the
# release, converted with `nix hash convert --hash-algo sha256 --to sri`).
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  alsa-lib,
}:
let
  version = "0.17.1";
  assets = {
    x86_64-linux = {
      target = "x86_64-unknown-linux-gnu";
      hash = "sha256-RbFNrGm994LFpnzXzVhFUpACge8AfMWXujhhVsSeNBY=";
    };
    aarch64-linux = {
      target = "aarch64-unknown-linux-gnu";
      hash = "sha256-AGZ6Q4qgsdO9W+jWNBvTFHIc8bpNS8lSN0yb9zyCG/g=";
    };
    x86_64-darwin = {
      target = "x86_64-apple-darwin";
      hash = "sha256-kmH5prUg1kAmuulSdgP7xHFMAIx6XNeyWqNb6PQXb2I=";
    };
    aarch64-darwin = {
      target = "aarch64-apple-darwin";
      hash = "sha256-NeJEYF5qHuNx03YhR0driF9wsgUuEb37fRmdVrns3kQ=";
    };
  };
  asset = assets.${stdenv.hostPlatform.system};
in
stdenv.mkDerivation {
  pname = "leaf";
  inherit version;

  src = fetchurl {
    url = "https://github.com/DeepanshuMishraa/leaf/releases/download/v${version}/leaf-${asset.target}.tar.gz";
    inherit (asset) hash;
  };
  sourceRoot = ".";

  # On Linux the binary needs the ALSA library and libgcc_s.
  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    alsa-lib
    stdenv.cc.cc.lib
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 leaf $out/bin/leaf
    runHook postInstall
  '';

  meta = {
    description = "Read PDFs, markdown files and web articles in the terminal";
    homepage = "https://github.com/DeepanshuMishraa/leaf";
    license = lib.licenses.mit;
    platforms = builtins.attrNames assets;
    mainProgram = "leaf";
  };
}
