{
  description = "Majika Flutter, Android, and Firebase development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    android-nixpkgs = {
      url = "github:tadfisher/android-nixpkgs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      android-nixpkgs,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            android_sdk.accept_license = true;
          };
        };

        isLinux = pkgs.stdenv.isLinux;
        isDarwin = pkgs.stdenv.isDarwin;

        androidSdk = android-nixpkgs.sdk.${system} (
          sdkPkgs:
          with sdkPkgs;
          [
            cmdline-tools-latest
            build-tools-36-0-0
            build-tools-35-0-0
            build-tools-34-0-0
            platform-tools

            platforms-android-36
            platforms-android-35
            platforms-android-34
            platforms-android-33
            platforms-android-31

            ndk-28-2-13676358
            cmake-3-22-1
          ]
          ++ pkgs.lib.optionals isLinux [
            emulator
          ]
        );

        shellProfile = ''
          export ANDROID_HOME="${androidSdk}/share/android-sdk"
          export ANDROID_SDK_ROOT="$ANDROID_HOME"
          export JAVA_HOME="${pkgs.jdk17}"
          export NPM_CONFIG_PREFIX="$PWD/.dart_tool/npm-global"
          export PATH="$PATH:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$HOME/.pub-cache/bin:$NPM_CONFIG_PREFIX/bin"
          export GRADLE_USER_HOME="$HOME/.gradle"

          if [ -d "android" ]; then
            echo "sdk.dir=$ANDROID_HOME" > android/local.properties
            echo "flutter.sdk=${pkgs.flutter}" >> android/local.properties
          fi

          ln -sfn "${pkgs.flutter}" .nix-flutter-sdk

          if [ -f ".dart_tool/package_config.json" ]; then
            existing_flutter_root="$(sed -n 's/.*"flutterRoot": "\(.*\)",/\1/p' .dart_tool/package_config.json | head -n 1)"
            expected_flutter_root="file://${pkgs.flutter}"
            if [ -n "$existing_flutter_root" ] && [ "$existing_flutter_root" != "$expected_flutter_root" ]; then
              echo "Detected Flutter SDK switch; regenerating .dart_tool metadata for ${pkgs.flutter}"
              rm -f .dart_tool/package_config.json .dart_tool/package_config_subset .dart_tool/version
              flutter pub get >/dev/null || true
            fi
          fi

          echo "Ensuring flutterfire_cli is available..."
          dart pub global activate flutterfire_cli 1.3.2 >/dev/null

          if ! command -v firebase >/dev/null 2>&1; then
            echo "Installing firebase-tools into project npm cache..."
            npm install --global firebase-tools@14.26.0 >/dev/null
          fi

          echo "Majika development environment ready."
          echo "  ANDROID_HOME=$ANDROID_HOME"
          echo "  JAVA_HOME=$JAVA_HOME"
          echo "  Firebase CLI=$(command -v firebase)"
          echo "  FlutterFire CLI=$(command -v flutterfire)"
        '';

        linuxDevShell = pkgs.buildFHSEnv {
          name = "majika-dev-env";
          targetPkgs =
            pkgs:
            with pkgs;
            [
              androidSdk
              flutter
              jdk17
              nodejs_20

              glibc
              zlib
              ncurses5
              stdenv.cc.cc.lib
              openssl
              expat

              pkg-config
              ninja
              cmake
              clang
              gtk3
              glib
              pcre2
              libselinux
              libsepol
              util-linux
              libepoxy
              libGL
              libx11
              libxcursor
              libxi
              libxrandr
              vulkan-loader

              git
              curl
              unzip
              which
              google-chrome
              gsettings-desktop-schemas
              adwaita-icon-theme
              hicolor-icon-theme
              nspr
              nss
            ];

          runScript = "bash";

          profile = ''
            export XDG_DATA_DIRS="${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}:${pkgs.adwaita-icon-theme}/share:${pkgs.hicolor-icon-theme}/share:$XDG_DATA_DIRS"
            export LD_LIBRARY_PATH="${
              pkgs.lib.makeLibraryPath [
                pkgs.vulkan-loader
                pkgs.libGL
                pkgs.libx11
                pkgs.libxcursor
                pkgs.libxi
                pkgs.libxrandr
                pkgs.gtk3
                pkgs.glib
                pkgs.libepoxy
                pkgs.nspr
                pkgs.nss
                pkgs.openssl
                pkgs.expat
              ]
            }''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
            export CHROME_EXECUTABLE="${pkgs.google-chrome}/bin/google-chrome-stable"

            ${shellProfile}
          '';
        };

        darwinDevShell = pkgs.mkShell {
          buildInputs = with pkgs; [
            androidSdk
            flutter
            jdk17
            nodejs_20
            cocoapods

            git
            curl
            unzip
            which
          ];

          shellHook = ''
            unset AR
            unset CC
            unset CXX
            unset DEVELOPER_DIR
            unset LD
            unset MACOSX_DEPLOYMENT_TARGET
            unset NM
            unset RANLIB
            unset SDKROOT
            unset STRIP

            if [ -e "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ]; then
              export CHROME_EXECUTABLE="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
            elif [ -e "/Applications/Chromium.app/Contents/MacOS/Chromium" ]; then
              export CHROME_EXECUTABLE="/Applications/Chromium.app/Contents/MacOS/Chromium"
            fi

            ${shellProfile}
          '';
        };
      in
      {
        devShells.default = if isDarwin then darwinDevShell else linuxDevShell.env;
      }
    );
}
