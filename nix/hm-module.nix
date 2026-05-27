self:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.line-messenger;
  defaultPkg = self.packages.${pkgs.system}.line-messenger;
in
{
  options.programs.line-messenger = {
    enable = lib.mkEnableOption "LINE messenger via Wine (snapshot-based)";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPkg;
      defaultText = lib.literalExpression "line-nix.packages.\${system}.line-messenger";
      description = "The line-messenger package to install.";
    };

    wine = lib.mkOption {
      type = lib.types.package;
      default = pkgs.wine;
      defaultText = lib.literalExpression "pkgs.wine";
      description = ''
        Wine flavour used at runtime. Defaults to plain `pkgs.wine` (classical
        wine), which is what the LINE installer is known to work cleanly with.
        Must match what CI used to build the snapshot, or you may hit ABI
        mismatches; override only if you know what you're doing.
      '';
    };

    prefixPath = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.dataHome}/line-msgr";
      defaultText = lib.literalExpression "\"\${config.xdg.dataHome}/line-msgr\"";
      description = ''
        Path to the wine prefix. The snapshot is re-extracted here on
        snapshot bumps; LINE's per-user state (Data/, UserData/) is
        preserved across bumps.
      '';
    };

    desktopEntry = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install a .desktop entry.";
    };

    autostart = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Start LINE on graphical login (systemd user service).";
    };
  };

  config = lib.mkIf cfg.enable (
    let
      wrapped = cfg.package.override { wine = cfg.wine; };
      finalPkg =
        if cfg.desktopEntry then
          wrapped
        else
          wrapped.overrideAttrs (old: {
            postInstall = (old.postInstall or "") + ''
              rm -rf $out/share/applications
            '';
          });
    in
    {
      home.packages = [ finalPkg ];

      home.sessionVariables = {
        LINE_NIX_PREFIX = cfg.prefixPath;
      };

      systemd.user.services.line-messenger = lib.mkIf cfg.autostart {
        Unit = {
          Description = "LINE messenger (Wine, snapshot-based)";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${finalPkg}/bin/line";
          Restart = "on-failure";
          RestartSec = 5;
          Environment = [ "LINE_NIX_PREFIX=${cfg.prefixPath}" ];
        };
        Install = {
          WantedBy = [ "graphical-session.target" ];
        };
      };
    }
  );
}
