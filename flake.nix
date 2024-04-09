{
  inputs = {
    utils.url = "github:numtide/flake-utils";
  };
  outputs = {
    self,
    nixpkgs,
    utils,
  }:
    utils.lib.eachDefaultSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        devShell = pkgs.mkShell {
          buildInputs = with pkgs; [
            # self.packages.${system}.default
          ];
        };

        nixosModules = rec {
          ec2-instance-connect-config = {selfPackages}: {
            config,
            pkgs,
          }: {
            users.groups.ec2-instance-connect = {};
            users.users.ec2-instance-connect = {
              isSystemUser = true;
              group = "ec2-instance-connect";
            };

            # Ugly: sshd refuses to start if a store path is given because /nix/store is group-writable.
            # So indirect by a symlink.
            environment.etc."ssh/aws-ec2-instance-connect" = {
              mode = "0755";
              text = ''
                #!/bin/sh
                exec ${selfPackages.ec2-instance-connect-run}/bin/eic_run_authorized_keys "$@"
              '';
            };

            services.openssh = {
              # AWS Instance Connect SSH offers the following kex algorithms
              # ecdh-sha2-nistp256,ecdh-sha2-nistp384,ecdh-sha2-nistp521,ext-info-c,kex-strict-c-v00@openssh.com
              settings.KexAlgorithms =
                # TODO: replace with nixos default options value
                [
                  "sntrup761x25519-sha512@openssh.com"
                  "curve25519-sha256"
                  "curve25519-sha256@libssh.org"
                  "diffie-hellman-group-exchange-sha256"
                ]
                ++ ["ecdh-sha2-nistp521"];
              authorizedKeysCommandUser = "ec2-instance-connect";
              authorizedKeysCommand = "/etc/ssh/aws-ec2-instance-connect %u %f";
            };
          };

          default = ec2-instance-connect-config;
        };

        packages = rec {
          ec2-instance-connect-script = pkgs.stdenvNoCC.mkDerivation {
            name = "ec2-instance-connect-script";
            src = pkgs.fetchFromGitHub {
              owner = "aws";
              repo = "aws-ec2-instance-connect-config";
              rev = "1.1.17";
              hash = "sha256-XXrVcmgsYFOj/1cD45ulFry5gY7XOkyhmDV7yXvgNhI=";
            };

            dontBuild = true;
            dontPatchShebangs = true;
            dontPatch = true;

            installPhase = ''
              mkdir -p $out/bin
              cp $src/src/bin/eic_parse_authorized_keys $out/bin
              cp $src/src/bin/eic_run_authorized_keys $out/bin
              # TODO: move to fixup phase!
              sed "s%^ca_path=/etc/ssl/certs$%ca_path=/etc/ssl/certs/ca-bundle.crt%" "src/bin/eic_curl_authorized_keys" > "$out/bin/eic_curl_authorized_keys"
              chmod a+x  "$out/bin/eic_curl_authorized_keys"
            '';
          };

          ec2-instance-connect-run = pkgs.buildFHSEnv {
            name = "eic_run_authorized_keys";
            runScript = "${ec2-instance-connect-script}/bin/eic_run_authorized_keys";
            targetPkgs = p:
              with p; [
                coreutils
                curl
                openssh
                cacert
                gnugrep
                util-linux
                openssl
                gawk
                gnused
              ];
          };

          default = ec2-instance-connect-run;
        };
      }
    );
}
