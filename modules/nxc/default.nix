{ config, lib, pkgs, ... }:

with lib; {
  options.nxc = {
    enable = mkEnableOption "Enable Nextcloud";

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/nextcloud";
      description = "Directory where Nextcloud stores data";
    };

    domain = mkOption {
      type = types.str;
      default = "nextcloud.${config.proxy.primaryDomain}";
      description = "Domain for Nextcloud instance";
    };

    adminUser = mkOption {
      type = types.str;
      default = "admin";
      description = "Nextcloud admin username";
    };

    adminPassFile = mkOption {
      type = types.str;
      description = "Path to file containing admin password";
    };

    enabledApps = mkOption {
      type = types.listOf types.str;
      default = [
        "calendar"
        "contacts"
        "photos"
        "tasks"
        "mail"
        "notes"
        "deck"
      ];
      description = "List of Nextcloud apps to install";
    };

    maxUploadSize = mkOption {
      type = types.str;
      default = "10G";
      description = "Maximum upload size";
    };

    collabora = {
      enable = mkEnableOption "Enable Collabora Online integration";
      
      domain = mkOption {
        type = types.str;
        default = "collabora.${config.proxy.primaryDomain}";
        description = "Domain for Collabora Online";
      };
      
      dictionaries = mkOption {
        type = types.listOf types.str;
        default = [ "en_US" "en_GB" ];
        description = "Dictionaries to install for Collabora";
      };
    };
    
    extraSettings = mkOption {
      type = types.attrs;
      default = {};
      description = "Additional Nextcloud settings";
      example = literalExpression ''
        {
          "mail_smtpmode" = "smtp";
          "mail_smtphost" = "smtp.example.com";
        }
      '';
    };
  };

  config = mkIf (config.nxc.enable && config.proxy.enable) {
    # Ensure data directory exists
    systemd.tmpfiles.settings."nxc-data" = {
      path = config.nxc.dataDir;
      type = "d";
      mode = "0750";
      user = "nextcloud";
      group = "nextcloud";
    };

    # Configure PostgreSQL
    services.postgresql = {
      enable = true;
      ensureDatabases = [ "nextcloud" ];
      ensureUsers = [{
        name = "nextcloud";
        ensurePermissions = {
          "DATABASE nextcloud" = "ALL PRIVILEGES";
        };
      }];
    };

    # Configure Redis (using Valkey)
    services.valkey = {
      enable = true;
      package = pkgs.valkey;
      servers.nextcloud = {
        enable = true;
        bind = "127.0.0.1";
        port = 6379;
      };
    };

    # Configure Nextcloud
    services.nextcloud = {
      enable = true;
      package = pkgs.nextcloud28;
      hostName = config.nxc.domain;
      datadir = config.nxc.dataDir;
      
      # Database
      config = {
        dbtype = "pgsql";
        dbuser = "nextcloud";
        dbhost = "/run/postgresql";
        dbname = "nextcloud";
        adminuser = config.nxc.adminUser;
        adminpassFile = config.nxc.adminPassFile;
        defaultPhoneRegion = "US"; # Default phone region
      };
      
      # Redis cache
      configureRedis = true;
      redis = {
        hostname = "127.0.0.1";
        port = 6379;
        dbIndex = 0;
      };
      
      # Automatic app installation
      autoUpdateApps.enable = true;
      autoUpdateApps.startAt = "05:00:00";
      apps = config.nxc.enabledApps;
      
      # Extra settings
      extraOptions = config.nxc.extraSettings // (
        optionalAttrs config.nxc.collabora.enable {
          "office.server" = "https://${config.nxc.collabora.domain}";
        }
      );
      
      # PHP settings
      phpOptions = {
        "upload_max_filesize" = config.nxc.maxUploadSize;
        "post_max_size" = config.nxc.maxUploadSize;
        "memory_limit" = config.nxc.maxUploadSize;
        "output_buffering" = "0";
        "max_execution_time" = "3600";
        "max_input_time" = "3600";
      };
    };

    # Configure Collabora Online
    services.collabora = mkIf config.nxc.collabora.enable {
      enable = true;
      extraConfig = {
        storage.wopi.host = "${config.nxc.domain}:443";
        per_document.max_connections = 100;
        per_view.out_of_focus_timeout_secs = 60;
        per_document.idle_timeout_secs = 3600;
        net.frame_ancestors = "https://${config.nxc.domain}";
      };
      server_name = config.nxc.collabora.domain;
      dictionaries = config.nxc.collabora.dictionaries;
    };

    # Add to proxy configuration
    proxy.virtualHosts = {
      "${config.nxc.domain}" = {
        forceSSL = true;
        useACMEHost = config.proxy.primaryDomain;
        locations = {
          "/" = {
            proxyPass = "http://127.0.0.1:${toString config.services.nextcloud.port}";
            proxyWebsockets = true;
            extraConfig = ''
              client_max_body_size ${config.nxc.maxUploadSize};
              fastcgi_read_timeout 3600s;
              fastcgi_send_timeout 3600s;
              proxy_read_timeout 3600s;
              proxy_connect_timeout 3600s;
              proxy_send_timeout 3600s;
            '';
          };
        };
      };
    } // (
      optionalAttrs config.nxc.collabora.enable {
        "${config.nxc.collabora.domain}" = {
          forceSSL = true;
          useACMEHost = config.proxy.primaryDomain;
          locations = {
            "/" = {
              proxyPass = "http://127.0.0.1:${toString config.services.collabora.port}";
              proxyWebsockets = true;
              extraConfig = ''
                proxy_read_timeout 3600s;
                proxy_connect_timeout 3600s;
                proxy_send_timeout 3600s;
              '';
            };
          };
        };
      }
    );

    # Add Nextcloud backup paths when both this module and backup are enabled
    services.borgbackup.jobs.all = mkIf config.bkp.enable {
      paths = [ config.nxc.dataDir ];
    };

    # System services dependencies
    systemd.services.nextcloud-setup = {
      requires = [ "postgresql.service" ];
      after = [ "postgresql.service" "valkey-nextcloud.service" ];
    };
  };
}
