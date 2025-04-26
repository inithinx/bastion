{
  config,
  lib,
  inputs,
  pkgs,
  ...
}: {
  imports = [inputs.self.nixosModules.bastion.pxy];

  options.arr = {
    enable = lib.mkEnableOption "Media server stack";
    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/media";
      description = "Base directory where all media services store state";
    };
    user = lib.mkOption {
      type = lib.types.str;
      default = "media";
      description = "Unix user for media services";
    };
    group = lib.mkOption {
      type = lib.types.str;
      default = "users";
      description = "Unix group for media services";
    };
  };

  config = lib.mkIf (config.arr.enable && config.proxy.enable) {
    # ensure your dataDir exists
    systemd.tmpfiles.settings.mediaData = {
      path = config.arr.dataDir;
      type = "d";
      mode = "0755";
      user = "root";
      group = "root";
    };

    # permit insecure dotnet for *arr services
    nixpkgs.config.permittedInsecurePackages = [
      "aspnetcore-runtime-6.0.36"
      "aspnetcore-runtime-wrapped-6.0.36"
      "dotnet-sdk-6.0.428"
      "dotnet-sdk-wrapped-6.0.428"
    ];

    # Jellyfin
    services.jellyfin = {
      enable = true;
      user = config.arr.user;
      group = config.arr.group;
      dataDir = "${config.arr.dataDir}/jellyfin";
      cacheDir = "${config.arr.dataDir}/jellyfin/cache";
      logDir = "${config.arr.dataDir}/jellyfin/log";
    };

    # Sonarr
    services.sonarr = {
      enable = true;
      user = config.arr.user;
      group = config.arr.group;
      dataDir = "${config.arr.dataDir}/sonarr";
    };

    # Radarr
    services.radarr = {
      enable = true;
      user = config.arr.user;
      group = config.arr.group;
      dataDir = "${config.arr.dataDir}/radarr";
    };

    # Lidarr
    services.lidarr = {
      enable = true;
      user = config.arr.user;
      group = config.arr.group;
      dataDir = "${config.arr.dataDir}/lidarr";
    };

    # Prowlarr (upstream doesn’t yet support dataDir, so we skip it)
    services.prowlarr = {
      enable = true;
      # dataDir = "${config.arr.dataDir}/prowlarr";  # future when supported
    };

    # Jellyseerr (no dataDir option upstream, so skip)
    services.jellyseerr = {
      enable = true;
    };

    # Deluge
    services.deluge = {
      enable = true;
      user = config.arr.user;
      group = config.arr.group;
      web.enable = true;
      dataDir = "${config.arr.dataDir}/deluge"; # supported by module
    };

    # FlareSolverr container
    virtualisation.oci-containers = {
      backend = "docker";
      containers.flaresolverr = {
        image = "ghcr.io/flaresolverr/flaresolverr:latest";
        autoStart = true;
        ports = ["127.0.0.1:8191:8191"];
        environment = {
          LOG_LEVEL = "warning";
          LOG_HTML = "false";
          CAPTCHA_SOLVER = "hcaptcha-solver";
          TZ = "Asia/Kolkata";
        };
      };
    };

    # hook media services into nginx proxy
    services.nginx.virtualHosts =
      config.proxy.virtualHosts
      // lib.mapAttrs (
        svc: info:
          if config.services.${svc}.enable
          then {
            "${svc}.${config.proxy.primaryDomain}" = {
              forceSSL = true;
              useACMEHost = config.proxy.primaryDomain;
              locations."/" = {
                proxyPass = "http://127.0.0.1:${toString info.port}";
                proxyWebsockets = info.websockets;
              };
            };
          }
          else {}
      )
      {
        jellyfin = {
          port = 8096;
          websockets = true;
        };
        sonarr = {
          port = 8989;
          websockets = false;
        };
        radarr = {
          port = 7878;
          websockets = false;
        };
        lidarr = {
          port = 8686;
          websockets = false;
        };
        prowlarr = {
          port = 9696;
          websockets = false;
        };
        jellyseerr = {
          port = 5055;
          websockets = false;
        };
        deluge = {
          port = 8112;
          websockets = false;
        };
        flaresolverr = {
          port = 8191;
          websockets = false;
        };
      };
  };
}
