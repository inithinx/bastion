{ config, lib, pkgs, ... }:

with lib; {
  options.bkp = {
    enable = mkEnableOption "Enable Borg backups for all enabled services";

    remoteRepo = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Remote Borg repository, e.g. \"user@rsync.net:/path/to/repo\"";
    };

    sshKeyFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Path to SSH private key for accessing the remote Borg repo";
    };

    encryptionMode = mkOption {
      type = types.enum [ "none" "repokey" "repokey-blake2" "keyfile" "keyfile-blake2" "authenticated" "authenticated-blake2" ];
      default = "repokey-blake2";
      description = "Borg encryption mode";
    };

    passFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Path to a file containing your Borg encryption passphrase";
    };

    startAt = mkOption {
      type = types.strOrListOfStr;
      default = "daily";
      description = "When to run backups (systemd.Time format or presets)";
    };

    pruneWithin = mkOption {
      type = types.str;
      default = "7d";
      description = "Prune any archives older than this interval";
    };

    pruneKeep = mkOption {
      type = types.attrsOf types.int;
      default = { daily = 7; weekly = 4; monthly = 12; };
      description = "Number of archives to keep per timeframe";
    };
  };

  config = mkIf config.bkp.enable {
    # sanity check
    assert config.bkp.remoteRepo != null; "You must set bkp.remoteRepo";

    # Ensure data dirs exist…
    systemd.tmpfiles.settings."bkp-proxy" = {
      path = config.proxy.dataDir; type = "d"; mode = "0755"; user = "root"; group = "root";
    };
    systemd.tmpfiles.settings."bkp-media" = {
      path = config.arr.dataDir;   type = "d"; mode = "0755"; user = "root"; group = "root";
    };

    environment.systemPackages = [ pkgs.borgbackup ];

    services.borgbackup.jobs.all = {
      repo    = config.bkp.remoteRepo;
      user    = "root";
      group   = "root";
      encryption.mode = config.bkp.encryptionMode;

      # Hard-code passCommand to 'cat <passFile>' if user provided one
      encryption.passCommand = config.bkp.passFile
        // (builtins.isNull config.bkp.passFile ? null
          : "cat ${config.bkp.passFile}");

      startAt = config.bkp.startAt;

      prune.prefix = "";
      prune.keep = {
        within = config.bkp.pruneWithin;
        inherit (config.bkp.pruneKeep) daily weekly monthly;
      };

      exclude = [ "/nix" "/run" ];

      paths = concatLists [
        [ config.proxy.dataDir ]
        (filterAttrs (_: val: val != null) {
          jellyfin = if config.services.jellyfin.enable then config.services.jellyfin.dataDir else null;
          sonarr   = if config.services.sonarr.enable   then config.services.sonarr.dataDir   else null;
          radarr   = if config.services.radarr.enable   then config.services.radarr.dataDir   else null;
          lidarr   = if config.services.lidarr.enable   then config.services.lidarr.dataDir   else null;
          deluge   = if config.services.deluge.enable   then config.services.deluge.dataDir   else null;
        })
      ];

      environment = optionalAttrs (config.bkp.sshKeyFile != null) {
        BORG_RSH = "ssh -i ${config.bkp.sshKeyFile} -o StrictHostKeyChecking=no";
      };
    };
  };
}

