{
  lib,
  stdenvNoCC,
  writeShellApplication,
  makeDesktopItem,
  copyDesktopItems,
  fetchurl,
  gnutar,
  zstd,
  coreutils,
  # Plain `pkgs.wine` (classical wine) is what the LINE installer works with
  # cleanly. Avoid `wineWow64Packages.*` flavours -- they hit signature/runtime
  # issues with LINE in practice. CI must use the SAME wine.
  wine,
}:

let
  pin =
    if builtins.pathExists ./snapshot-pin.json then
      builtins.fromJSON (builtins.readFile ./snapshot-pin.json)
    else
      throw "line-nix: nix/snapshot-pin.json missing.";

  hasLocalPath = pin ? path && pin.path != null;
  hasRemoteUrl = pin ? url && pin.url != null && pin ? hash && pin.hash != null;

  snapshot =
    if hasLocalPath then
      # Local file pinning, used to seed the system before CI is wired up.
      # The path is imported into the nix store at evaluation time.
      builtins.path {
        path = pin.path;
        name = "line-snapshot.tar.zst";
      }
    else if hasRemoteUrl then
      fetchurl {
        url = pin.url;
        hash = pin.hash;
      }
    else
      throw ''
        line-nix: no snapshot pinned in nix/snapshot-pin.json.

        Strict-mode by design: a working LINE setup is built entirely in CI
        and shipped as one immutable, hash-pinned tarball. The pin file must
        have either:
          - { "path": "/abs/path/to/snapshot.tar.zst" }       (local seed)
          - { "url": "...", "hash": "sha256-..." }            (remote, CI)
      '';

  # Used as a stamp inside the prefix to know when to re-extract on bumps.
  # For local path mode (no hash in pin), use the imported store path's hash.
  snapshotHash =
    if hasRemoteUrl then pin.hash else builtins.substring 11 32 (baseNameOf "${snapshot}");

  launcher = writeShellApplication {
    name = "line";
    runtimeInputs = [
      wine
      gnutar
      zstd
      coreutils
    ];
    text = lib.replaceStrings [ "@SNAPSHOT@" "@SNAPSHOT_HASH@" ] [ "${snapshot}" snapshotHash ] (
      builtins.readFile ./launcher.sh
    );
  };

  desktopItem = makeDesktopItem {
    name = "line-messenger";
    desktopName = "LINE";
    genericName = "Messenger";
    comment = "LINE messenger (Windows client via Wine)";
    exec = "line";
    terminal = false;
    categories = [
      "Network"
      "InstantMessaging"
    ];
    startupWMClass = "line.exe";
    startupNotify = true;
    keywords = [
      "chat"
      "messaging"
      "im"
      "line"
    ];
  };

in
stdenvNoCC.mkDerivation {
  pname = "line-messenger";
  version = "snapshot-${pin.capturedAt or "unknown"}";

  dontUnpack = true;
  dontBuild = true;

  nativeBuildInputs = [ copyDesktopItems ];
  desktopItems = [ desktopItem ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp ${launcher}/bin/line $out/bin/line
    runHook postInstall
  '';

  passthru = { inherit wine snapshot pin; };

  meta = with lib; {
    description = "LINE messenger (Windows client) wrapped in Wine for NixOS";
    homepage = "https://line.me/";
    license = licenses.unfree;
    platforms = platforms.linux;
    mainProgram = "line";
  };
}
