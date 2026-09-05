# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).
{
  config,
  pkgs,
  utils,
  ...
}: let
  usbKeyFsUuid = "1E71-D655";
  luksRootUuid = "89d4e83d-85cf-44c0-8d7e-6ecdd790ecc1";
  luksRootName = "luks-${luksRootUuid}";
  luksRootCryptsetupUnit = "systemd-cryptsetup@${utils.escapeSystemdPath luksRootName}.service";
  playitLogin = pkgs.writeShellApplication {
    name = "playit-login";
    runtimeInputs = [
      config.services.playit.finalPackage
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.systemd
    ];
    text = ''
      secret_path=/etc/playit/secret.toml

      if [ -e "$secret_path" ]; then
        read -r -p "$secret_path already exists; replace it? [y/N] " answer </dev/tty
        case "$answer" in
          y|Y|yes|YES) ;;
          *) echo "Cancelled."; exit 0 ;;
        esac
      fi

      claim_code="$(playit-cli claim generate)"
      claim_url="$(playit-cli claim url "$claim_code")"
      echo "Open this URL and approve the agent:"
      echo "$claim_url"
      echo

      exchange_output="$(mktemp)"
      secret_file="$(mktemp)"
      trap 'rm -f "$exchange_output" "$secret_file"' EXIT
      chmod 0600 "$exchange_output" "$secret_file"

      # Keep the returned key out of the displayed output while retaining it
      # long enough to install the service credential.
      playit-cli --stdout claim exchange "$claim_code" 2>&1 \
        | tee "$exchange_output" \
        | sed -E 's/[[:xdigit:]]{64}/[secret received]/g'

      secret_key="$(grep -Eo '[[:xdigit:]]{64}' "$exchange_output" | tail -n 1)"
      if [ -z "$secret_key" ]; then
        echo "Could not find a Playit secret in the claim response." >&2
        exit 1
      fi

      printf 'secret_key = "%s"\n' "$secret_key" >"$secret_file"
      ${pkgs.sudo}/bin/sudo install -D -m 0400 -o root -g root \
        "$secret_file" "$secret_path"
      ${pkgs.sudo}/bin/sudo systemctl restart playit.service

      echo "Installed $secret_path and restarted playit.service."
    '';
  };
in {
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 1;
  boot.loader.efi.canTouchEfiVariables = true;

  # Use latest kernel.
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.extraModprobeConfig = ''
    options hid_apple fnmode=2
  '';

  boot.initrd.supportedFilesystems = ["vfat"];
  boot.initrd.luks.devices.${luksRootName} = {
    device = "/dev/disk/by-uuid/${luksRootUuid}";
    keyFile = "/key/luks.key";
    keyFileTimeout = 10;
  };

  boot.initrd.systemd.services.mount-luks-key-usb = {
    description = "Mount USB LUKS key";
    requiredBy = [luksRootCryptsetupUnit];
    before = [
      luksRootCryptsetupUnit
      "cryptsetup-pre.target"
      "shutdown.target"
    ];
    conflicts = ["shutdown.target"];
    startLimitBurst = 0;
    startLimitIntervalSec = 0;
    unitConfig.DefaultDependencies = false;
    script = ''
      mkdir -p /key

      for _ in $(seq 1 10); do
        if [ -b /dev/disk/by-uuid/${usbKeyFsUuid} ]; then
          exec mount -t vfat -o ro /dev/disk/by-uuid/${usbKeyFsUuid} /key
        fi
        sleep 1
      done

      echo "USB key partition /dev/disk/by-uuid/${usbKeyFsUuid} not found"
      exit 0
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };

  systemd.services.umount-luks-key-usb = {
    description = "Unmount USB LUKS key after boot";
    wantedBy = ["multi-user.target"];
    after = ["local-fs.target"];
    unitConfig.ConditionPathIsMountPoint = "/key";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.util-linux}/bin/umount /key";
    };
  };

  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
    trusted-users = ["root" "mebaran"];
  };

  networking.hostName = "omen"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;
  # NetworkManager manages the host's real connectivity; avoid networkd's
  # wait-online delay during rebuilds.
  systemd.network.wait-online.enable = false;

  # Set your time zone.
  time.timeZone = "America/Los_Angeles";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.mebaran = {
    isNormalUser = true;
    uid = 1000;
    description = "Mark Baran";
    extraGroups = ["hermes" "networkmanager" "uinput" "wheel"];
    linger = true;
  };

  users.groups.hermes = {};
  users.users.hermes = {
    isSystemUser = true;
    group = "hermes";
    home = "/var/lib/hermes-podman";
    createHome = true;
    linger = true;
    subUidRanges = [
      {
        startUid = 200000;
        count = 65536;
      }
    ];
    subGidRanges = [
      {
        startGid = 200000;
        count = 65536;
      }
    ];
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable remote terminal access.
  services.openssh.enable = true;
  services.eternal-terminal.enable = true;
  services.playit = {
    enable = true;
    secretPath = "/etc/playit/secret.toml";
  };
  services.logrotate.enable = true;
  environment.systemPackages = [playitLogin];
  services.sunshine = {
    package = pkgs.sunshine.override {
      cudaSupport = true;
    };
    enable = true;
    autoStart = true;
    capSysAdmin = true;
    openFirewall = true;
  };
  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;
  # enable RDP ports too
  networking.firewall.allowedTCPPorts = [
    config.services.eternal-terminal.port # Eternal Terminal
    3389 # RDP
  ];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?
}
