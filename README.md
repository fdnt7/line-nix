# line-nix

LINE (the Windows desktop client) on NixOS via Wine -- fully declarative and
snapshot-based.

## What it is

LINE ships only Windows and macOS desktop builds, so on NixOS it runs under
Wine. Rather than run the installer on each machine (slow, non-reproducible, and
reliant on network state at install time), line-nix uses a **snapshot model**:

- A working Wine prefix is built **once in CI** -- installer downloaded, run
  headlessly, and the resulting prefix scrubbed of non-deterministic state.
- That prefix is shipped as a single **immutable, hash-pinned tarball**
  (`nix/snapshot-pin.json`).
- At runtime the launcher just extracts-or-updates the prefix and execs LINE.
  Your login token and chat history (`LINE/Data`, `LINE/UserData`) are preserved
  across snapshot bumps.

The shipped client is **LINE 9.1.3.3383**. See [Why 9.x and not 26.x] below.

## Requirements

- Nix with flakes enabled.
- LINE is unfree; the flake allows it for its own package, but to install it
  into your config you must permit the unfree `line-messenger` (e.g.
  `nixpkgs.config.allowUnfreePredicate = p: lib.getName p == "line-messenger";`).

## Try it

```sh
nix run github:fdnt7/line-nix
```

## Install (Home Manager)

Add the flake as an input and enable the module:

```nix
# flake.nix
{
  inputs.line-nix.url = "github:fdnt7/line-nix";
  # ... your other inputs
}
```

```nix
# home-manager configuration
{ inputs, ... }:
{
  imports = [ inputs.line-nix.homeManagerModules.default ];

  programs.line-messenger = {
    enable = true;
    # desktopEntry = true;   # .desktop launcher (default: true)
    # autostart   = false;   # start on graphical login (default: false)
    # prefixPath  = "${config.xdg.dataHome}/line-msgr";  # wine prefix location
  };
}
```

Module options (`programs.line-messenger.*`): `enable`, `package`, `wine`,
`prefixPath`, `desktopEntry`, `autostart`. See [`nix/hm-module.nix`] for
details.

> The `wine` flavour must match what CI used to build the snapshot -- plain
> `pkgs.wine` (classical, 32-bit). Overriding it can cause ABI mismatches that
> break the prefix; only do so if you know what you're doing.

## Other entry points

- `packages.default` / `packages.line-messenger` -- the package.
- `apps.default` -- `nix run`.
- `overlays.default` -- adds `line-messenger` to `pkgs`.
- `homeManagerModules.default` (alias `.line-messenger`).

<a name="line-version"></a>

## LINE version: why 9.x and not the latest 26.x

The current LINE Desktop (26.x, a Qt6 rewrite) **does not run under Wine**: it
performs a two-stage Authenticode self-integrity check on the system DLLs it
loads, and Wine's legitimate-but-unsigned builtins fail the second stage
(genuine certificate validation). There is no clean, sustainable bypass, so
line-nix stays on the newest LINE that runs cleanly -- **9.1.3.3383**.

The 26.x installer, the 64-bit (`wineWow64`) requirement, the dissected
integrity check, and why each workaround is a dead end are documented in
[`docs/line-26x-investigation.md`]. The rest of the pipeline is ready should the
check ever become satisfiable under Wine.

## Development

```sh
nix develop          # dev shell (prek + formatter)
nix fmt              # format (treefmt)
nix flake check      # formatting check
```

## License

The packaging here is provided as-is. LINE itself is proprietary
(`license = unfree`); you are responsible for complying with LINE's terms.

[why 9.x and not 26.x]: #line-version
[`docs/line-26x-investigation.md`]: docs/line-26x-investigation.md
[`nix/hm-module.nix`]: nix/hm-module.nix
