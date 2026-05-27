{ lib, ... }:
{
  programs = {
    jsonfmt.enable = true;
    mdformat = {
      enable = true;
      settings.wrap = 80;
    };
    nixfmt.enable = true;
    shfmt.enable = true;
    taplo.enable = true;
    typos.enable = true;
  };

  # exclude `--write-changes` from options so it doesn't automatically fix typos
  # because it could break code
  settings.formatter.typos.options = lib.mkForce [ "--force-exclude" ];
}
