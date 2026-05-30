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
  icoutils,
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

  # All user-visible strings come from LINE's own copy:
  #   desktopName = ProductName / FileDescription from LINE.exe VersionInfo
  #   genericName = LINE's self-classification on line.me ("a messenger app")
  #   comment     = line.me <meta property="og:title">, verbatim, minus the
  #                 redundant "LINE" brand prefix (XDG spec says Comment
  #                 should not duplicate Name). Original separator was the
  #                 full-width vertical bar; the brand half is dropped so
  #                 ASCII is preserved without a lossy substitution.
  desktopItem = makeDesktopItem {
    name = "line-messenger";
    desktopName = "LINE";
    genericName = "Messenger";
    comment = "always at your side.";
    icon = "line-messenger";
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

  nativeBuildInputs = [
    copyDesktopItems
    icoutils
    gnutar
    zstd
  ];
  desktopItems = [ desktopItem ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp ${launcher}/bin/line $out/bin/line

    # Icon: ships as a Windows resource embedded in LineLauncher.exe (the
    # snapshot has no standalone .ico/.png). Pull just that one .exe out of
    # the tarball, extract its group_icon as a multi-resolution .ico, split
    # per size, and install into hicolor. The LINE bin/ path is stable
    # across version bumps; bin/<ver>/LINE.exe is not.
    iconwork=$(mktemp -d)
    tar --zstd -xf ${snapshot} -C "$iconwork" \
        ./drive_c/users/runner/AppData/Local/LINE/bin/LineLauncher.exe
    wrestool -x -t 14 \
        -o "$iconwork/line.ico" \
        "$iconwork/drive_c/users/runner/AppData/Local/LINE/bin/LineLauncher.exe"
    icotool -x -o "$iconwork" "$iconwork/line.ico"
    for png in "$iconwork"/line_*.png; do
      # icotool names files <base>_<idx>_<W>x<H>x<bpp>.png
      dims=''${png##*_}            # WxHxBPP.png
      size=''${dims%%x*}           # W
      install -Dm644 "$png" \
        "$out/share/icons/hicolor/''${size}x''${size}/apps/line-messenger.png"
    done
    rm -rf "$iconwork"

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
