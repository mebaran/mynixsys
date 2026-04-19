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
in {
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Use latest kernel.
  boot.kernelPackages = pkgs.linuxPackages_latest;

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

  nix.settings.experimental-features = ["nix-command" "flakes"];

  networking.hostName = "omen"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

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
    description = "Mark Baran";
    extraGroups = ["networkmanager" "wheel"];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

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

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
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
  networking.firewall.allowedTCPPorts = [3389];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?
}
