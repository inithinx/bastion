{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
  options.mcs = {
    enable = mkEnableOption "Enable Minecraft server";

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/minecraft";
      description = "Directory where Minecraft server stores data";
    };

    user = mkOption {
      type = types.str;
      default = "minecraft";
      description = "User to run the Minecraft server as";
    };

    group = mkOption {
      type = types.str;
      default = "minecraft";
      description = "Group to run the Minecraft server as";
    };

    domain = mkOption {
      type = types.str;
      default = "mc.${config.proxy.primaryDomain}";
      description = "Domain for Minecraft server's web admin panel";
    };

    port = mkOption {
      type = types.port;
      default = 25565;
      description = "Port for the Minecraft server";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to open firewall ports for Minecraft";
    };

    serverProperties = mkOption {
      type = types.attrs;
      default = {};
      description = "Server properties";
      example = literalExpression ''
        {
          server-port = 25565;
          difficulty = "normal";
          gamemode = "survival";
          max-players = 20;
          motd = "NixOS Minecraft Server";
          white-list = true;
          enable-rcon = true;
          "rcon.password" = "strong_password";
        }
      '';
    };

    papermc = {
      version = mkOption {
        type = types.str;
        default = "1.21.2";
        description = "PaperMC version to use";
      };

      build = mkOption {
        type = types.str;
        default = "latest";
        description = "PaperMC build number (or latest)";
      };

      maxHeapSize = mkOption {
        type = types.int;
        default = 2048;
        description = "Maximum heap size for the Java process in MB";
      };

      minHeapSize = mkOption {
        type = types.int;
        default = 1024;
        description = "Minimum heap size for the Java process in MB";
      };

      jvmOpts = mkOption {
        type = types.str;
        default = "-XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M -XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 -XX:InitiatingHeapOccupancyPercent=15 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 -XX:+PerfDisableSharedMem";
        description = "JVM options for the Minecraft server";
      };
    };

    webAdmin = {
      enable = mkEnableOption "Enable web admin panel (using mcadmin)";

      port = mkOption {
        type = types.port;
        default = 8100;
        description = "Port for the web admin panel";
      };

      adminUsers = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "List of users who can access the admin panel";
      };

      passwordFile = mkOption {
        type = types.str;
        default = null;
        description = "Path to file containing admin password hash";
      };
    };

    plugins = mkOption {
      type = types.listOf types.path;
      default = [];
      description = "List of plugin JAR files to install";
      example = literalExpression ''
        [
          (pkgs.fetchurl {
            url = "https://github.com/EssentialsX/Essentials/releases/download/2.19.0/EssentialsX-2.19.0.jar";
            sha256 = "0000000000000000000000000000000000000000000000000000";
          })
        ]
      '';
    };
  };

  config = mkIf config.mcs.enable {
    # Create the minecraft user and group if they don't exist
    users.users = mkIf (config.mcs.user == "minecraft") {
      minecraft = {
        isSystemUser = true;
        group = config.mcs.group;
        home = config.mcs.dataDir;
        createHome = true;
        description = "Minecraft server service user";
      };
    };

    users.groups = mkIf (config.mcs.group == "minecraft") {
      minecraft = {};
    };

    # Ensure data directory exists
    systemd.tmpfiles.settings."mcs-data" = {
      path = config.mcs.dataDir;
      type = "d";
      mode = "0750";
      user = config.mcs.user;
      group = config.mcs.group;
    };

    # Configure PaperMC server
    services.minecraft-server = {
      enable = true;
      package = pkgs.papermc;
      declarative = true;
      eula = true;

      dataDir = config.mcs.dataDir;
      openFirewall = config.mcs.openFirewall;

      serverProperties =
        {
          server-port = config.mcs.port;
          motd = "NixOS Minecraft Server";
          difficulty = "normal";
          gamemode = "survival";
          max-players = 20;
          white-list = false;
          # Allow remote connections
          "server-ip" = "0.0.0.0";
          # Enable rcon for admin panel
          "enable-rcon" = config.mcs.webAdmin.enable;
          "rcon.port" = 25575;
          "rcon.password" = "minecraft";
        }
        // config.mcs.serverProperties;

      jvmOpts = ''-Xms${toString config.mcs.papermc.minHeapSize}M -Xmx${toString config.mcs.papermc.maxHeapSize}M ${config.mcs.papermc.jvmOpts}'';

      # Customize the server version
      papermc = {
        enable = true;
        inherit (config.mcs.papermc) version build;
      };
    };

    # Install plugins
    system.activationScripts.installMinecraftPlugins = mkIf (config.mcs.plugins != []) {
      text = ''
        mkdir -p ${config.mcs.dataDir}/plugins
        chown ${config.mcs.user}:${config.mcs.group} ${config.mcs.dataDir}/plugins
        chmod 750 ${config.mcs.dataDir}/plugins

        ${concatMapStringsSep "\n" (plugin: ''
            cp ${plugin} ${config.mcs.dataDir}/plugins/
            chown ${config.mcs.user}:${config.mcs.group} ${config.mcs.dataDir}/plugins/$(basename ${plugin})
          '')
          config.mcs.plugins}
      '';
      deps = [];
    };

    # Web admin panel (mcadmin)
    services.mcadmin = mkIf config.mcs.webAdmin.enable {
      enable = true;
      port = config.mcs.webAdmin.port;
      rconHost = "localhost";
      rconPort = 25575;
      rconPassword = config.mcs.serverProperties."rcon.password" or "minecraft";
      package = pkgs.mcadmin;
      users = builtins.listToAttrs (map (user: {
          name = user;
          value = {
            passwordFile = config.mcs.webAdmin.passwordFile;
            admin = true;
          };
        })
        config.mcs.webAdmin.adminUsers);
    };

    # Nginx configuration for web admin panel
    proxy.virtualHosts = mkIf (config.mcs.webAdmin.enable && config.proxy.enable) {
      "${config.mcs.domain}" = {
        forceSSL = true;
        useACMEHost = config.proxy.primaryDomain;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString config.mcs.webAdmin.port}";
          proxyWebsockets = true;
        };
      };
    };

    # Add minecraft data to backup path
    services.borgbackup.jobs.all = mkIf config.bkp.enable {
      paths = [config.mcs.dataDir];
    };

    # Firewall configuration
    networking.firewall = mkIf config.mcs.openFirewall {
      allowedTCPPorts = [config.mcs.port];
      allowedUDPPorts = [config.mcs.port];
    };
  };
}
