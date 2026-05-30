# Investigation: moving line-nix to LINE 26.x (and why it's blocked)

_Date: 2026-05-31. Status: **not shippable**; we stay on 9.1.3.3383._

## TL;DR

The newest LINE Desktop (26.x) **can be obtained and installed** under Wine, but
it **will not run** because LINE 26.x performs a two-stage Authenticode
self-integrity check on the system DLLs it loads. Wine's builtin DLLs are
legitimate but unsigned, so the check hard-fails at a modal dialog and refuses
to start. Stage one is defeatable with a `wintrust.dll` compatibility shim;
stage two (genuine certificate/publisher validation via `crypt32`) is not, short
of forging a Microsoft signature, redistributing signed Microsoft DLLs
(licensing + they fail to load under Wine), or binary-patching `LINE.exe` on
every release. None is sustainable, so the package remains on 9.x.

## The two LINE products

- **LINE 9.x** -- the legacy standalone-installer client. **32-bit.** This is
  what line-nix currently ships (9.1.3.3383) and what runs cleanly under the
  flake's plain `pkgs.wine` (32-bit). The old stub
  `https://desktop.line-scdn.net/win/new/LineInst.exe` is frozen here
  (Last-Modified 2024-12-04, ~1 MB downloader stub).
- **LINE Desktop 26.x** -- the current Qt6 client distributed via the Microsoft
  Store. **64-bit.**

## How to get the genuine 26.x installer (this part works)

The Microsoft Store "LINE Desktop" listing
(`apps.microsoft.com/detail/xpfcc4cd725961`) is **not** an MSIX. Microsoft's
StoreEdgeFD API reports it as a **WPM** (winget-style) installer that points
back to LINE's own CDN:

```
curl -s -A 'Mozilla/5.0' \
  "https://storeedgefd.dsx.mp.microsoft.com/v9.0/products/xpfcc4cd725961?market=US&locale=en-US&deviceFamily=Windows.Desktop" \
  | jq '.Payload.Installer.Architectures'
```

-> x64: `https://desktop.line-scdn.net/win/bin/real/installer/LineInst.exe`
(Args `/M`, a published SHA-256 we verified byte-for-byte), version 26.2.0.3894.
(x86 sibling is the legacy 8.7.x build under `.../installer/legacy/`.)

Notes:

- This is a **~74.7 MB full offline NSIS installer** (not a stub). Its SHA-256
  matches the `Hash` Microsoft publishes in the WPM metadata, confirming it is
  exactly what the Store delivers, from the same legitimate
  `desktop.line-scdn.net` CDN we already trust.
- Silent install works headlessly: `wine LineInst.exe /S`. **No xdotool
  click-through needed** (the 9.x installer needed it; 26.x is plain NSIS).
- Installs to the same layout: `%LocalAppData%/LINE/bin/LineLauncher.exe` +
  `bin/<version>/LINE.exe`.

## What it takes to run it (and where it dies)

1. **64-bit Wine required.** `LINE.exe`, `LineAppMgr.exe`, `LineConnector.exe`,
   `LineDiag.exe` are PE32+/x86-64. Only `LineLauncher.exe`/`LineUpdater.exe`/
   `LineUnInst.exe` are 32-bit. The flake's plain `pkgs.wine` is 32-bit-only, so
   it fails with `Bad EXE format`. **`wineWow64Packages.stable`** (cached, no
   source build) runs it. `wineWowPackages.stable` is deprecated and builds Wine
   from source -- avoid.

1. Launch `LINE.exe` directly (bypassing the 32-bit `LineLauncher`, which also
   avoids the runtime updater -- desirable for the snapshot model).

1. LINE.exe shows a modal **"Security verification failed."** dialog and blocks:

   ```
   Security verification failed.
   The following files failed security verification:
   Restore binary process will be start.
   File : C:\windows\system32\CRYPT32.dll
   Reason : NO_SIGNATURE
   ```

### The integrity check, dissected

`LINE.exe` imports `WINTRUST.dll` (statically only
`CryptCATAdminReleaseCatalogContext`; the rest resolved dynamically) and uses
the catalogue/`WinVerifyTrust` path.

- **Stage 1 -- trust status.** A `wintrust.dll` shim that returns
  `ERROR_SUCCESS` from `WinVerifyTrust` (and benign values from the
  `CryptCATAdmin*` functions) **passes**. Confirmed loaded `native` from the app
  dir via `WINEDEBUG=+loaddll`.
- **Stage 2 -- certificate validation.** With stage 1 passed, the reason string
  changes `NO_SIGNATURE` -> **`INVALID_SIGNATURE`**. LINE independently reads
  the DLL's actual Authenticode certificate (builtin `crypt32`) and validates
  the publisher/chain. Wine's DLLs have no real signature -> fails.

There is **no public precedent** for running the Qt-based LINE under Wine.

### Why stage 2 has no clean fix

- **Forge a Microsoft signature** -- cryptographically impossible (the point of
  signing).
- **Bundle genuine signed Microsoft DLLs** as native overrides -- Microsoft
  licensing violation, *and* native `crypt32`/`wintrust` typically fail to load
  under Wine (NT-internal dependencies). Also an unknown, growing file list.
- **Binary-patch `LINE.exe`** -- app-level tampering; re-breaks on every update;
  unmaintainable.

## If revisiting later

The whole pipeline (download URL, silent install, `wineWow64`, direct `LINE.exe`
launch) is ready. The only blocker is stage-2 cert validation. Re-check if Wine
ever ships Authenticode-signed builtin DLLs, or if LINE relaxes the check. To
re-derive the installer URL, re-query the StoreEdgeFD endpoint above (the CDN
path may change between releases).
