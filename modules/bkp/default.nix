{
  config,
  lib,
  pkgs,
  ...
}:
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
      type = types.enum ["none" "repokey" "repokey-blake2" "keyfile" "keyfile-blake2" "authenticated" "authenticated-blake2"];
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
      default = {
        daily = 7;
        weekly = 4;
        monthly = 12;
      };
      description = "Number of archives to keep per timeframe";
    };

    extraExclude = mkOption {
      type = types.listOf types.str;
      default = ["/nix" "/run"];
      description = "Additional paths to exclude from backups";
    };
  };

  # Basic input validation
  assertions = [
    {
      assertion = config.bkp.enable -> config.bkp.remoteRepo != null;
      message = "You must specify bkp.remoteRepo when bkp.enable is true";
    }
  ];

  config = mkIf config.bkp.enable {
    # Install borg
    environment.systemPackages = [pkgs.borgbackup];

    # Set up basic job configuration
    # Individual paths are added by respective modules
    services.borgbackup.jobs.all = {
      repo = config.bkp.remoteRepo;
      user = "root";
      group = "root";

      encryption.mode = config.bkp.encryptionMode;
      encryption.passCommand =
        if config.bkp.passFile != null
        then "cat ${config.bkp.passFile}"
        else null;

      startAt = config.bkp.startAt;

      prune.prefix = "";
      prune.keep = {
        within = config.bkp.pruneWithin;
        inherit (config.bkp.pruneKeep) daily weekly monthly;
      };

      exclude = config.bkp.extraExclude;

      # Path definition is delegated to individual modules using services.borgbackup.jobs.all.paths
      # instead of hardcoding them here

      environment = optionalAttrs (config.bkp.sshKeyFile != null) {
        BORG_RSH = "ssh -i ${config.bkp.sshKeyFile} -o StrictHostKeyChecking=no";
      };
    };
  };
}
