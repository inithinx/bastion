{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
  options = {
    proxy = {
      enable = mkEnableOption "Enable nginx-Quic reverse-proxy + ACME";
      primaryDomain = mkOption {
        type = types.str;
        description = "The apex domain (e.g. example.com)";
      };
      dataDir = mkOption {
        type = types.str;
        default = "/var/lib/proxy";
        description = "Base directory where proxy/ACME store state";
      };
      acme = {
        email = mkOption {
          type = types.str;
          description = "Email for Let's Encrypt registration";
        };
        environmentFile = mkOption {
          type = types.str;
          description = "Path to env file with DNS-API creds";
        };
        dnsProvider = mkOption {
          type = types.str;
          description = "NixOS DNS provider name (e.g. cloudflare)";
        };
      };
      virtualHosts = mkOption {
        type = types.attrsOf types.submodule;
        description = "User-defined nginx vhosts";
        default = {};
      };
      catchAllRedirect = mkOption {
        type = types.str;
        default = "https://${config.proxy.primaryDomain}";
        description = "URL to redirect unmatched subdomains to";
      };
    };
  };

  config = mkIf config.proxy.enable {
    # ensure your dataDir exists
    systemd.tmpfiles.settings = {
      "proxy-data" = {
        path = config.proxy.dataDir;
        type = "d"; # directory
        mode = "0755";
        user = "root";
        group = "root";
      };
    };

    # nginx + vhosts
    services.nginx = {
      enable = true;
      package = pkgs.nginxQuic;
      recommendedZstdSettings = true;
      recommendedBrotliSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;

      virtualHosts =
        config.proxy.virtualHosts
        // {
          "${config.proxy.primaryDomain}" = {
            forceSSL = true;
            useACMEHost = config.proxy.primaryDomain;
            locations."/" = {proxyPass = "http://127.0.0.1:3000";};
          };
          "~^(?<sub>.+)\\.${config.proxy.primaryDomain}" = {
            forceSSL = true;
            useACMEHost = config.proxy.primaryDomain;
            locations."/" = {
              return = "301 ${config.proxy.catchAllRedirect}";
              priority = 999;
            };
          };
        };
    };

    # ACME state under your dataDir/acme
    security.acme = {
      acceptTerms = true;
      defaults = {
        email = config.proxy.acme.email;
        environmentFile = config.proxy.acme.environmentFile;
        dnsResolver = "1.1.1.1:53";
        reloadServices = ["nginx"];
        directory = "${config.proxy.dataDir}/acme";
      };
      providers = {"${config.proxy.acme.dnsProvider}" = {};};
      certs = {
        "${config.proxy.primaryDomain}" = {
          domain = "*.${config.proxy.primaryDomain}";
          extraDomainNames = [config.proxy.primaryDomain];
          dnsProvider = config.proxy.acme.dnsProvider;
          group = "nginx";
        };
      };
    };
  };
  # Add proxy data to backup when both this module and backup are enabled
  services.borgbackup.jobs.all = mkIf (config.proxy.enable && config.bkp.enable) {
    paths = [ config.proxy.dataDir ];
  };
}
