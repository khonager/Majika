{
  description = "Majika Flutter, Android, and Firebase development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { self, nixpkgs, flake-utils }:
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

        androidComposition = pkgs.androidenv.composeAndroidPackages {
          cmdLineToolsVersion = "8.0";
          toolsVersion = "26.1.1";
          platformToolsVersion = "36.0.2";
          buildToolsVersions = [
            "28.0.3"
            "30.0.3"
            "33.0.1"
            "34.0.0"
            "35.0.0"
          ];
          includeEmulator = true;
          emulatorVersion = "36.4.2";
          platformVersions = [
            "28"
            "33"
            "34"
            "36"
          ];
          includeSources = false;
          includeSystemImages = false;
          systemImageTypes = [ "google_apis_playstore" ];
          abiVersions = [
            "armeabi-v7a"
            "arm64-v8a"
          ];
          cmakeVersions = [ "3.22.1" ];
          includeNDK = true;
          ndkVersions = [ "28.2.13676358" ];
          useGoogleAPIs = false;
          useGoogleTVAddOns = false;
          includeExtras = [ "extras;google;gcm" ];
        };

        androidSdk = androidComposition.androidsdk;
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            flutter
            jdk17
            nodejs_20
            androidSdk

            pkg-config
            ninja
            cmake
            clang
            gtk3
            glib
            pcre2
          ];

          ANDROID_HOME = "${androidSdk}/libexec/android-sdk";
          ANDROID_SDK_ROOT = "${androidSdk}/libexec/android-sdk";
          JAVA_HOME = pkgs.jdk17.home;
          CHROME_EXECUTABLE = "${pkgs.google-chrome}/bin/google-chrome-stable";

          shellHook = ''
            export NPM_CONFIG_PREFIX="$PWD/.dart_tool/npm-global"
            export PATH="${pkgs.flutter}/bin/cache/dart-sdk/bin:$PATH:$ANDROID_HOME/tools:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/8.0/bin:$HOME/.pub-cache/bin:$NPM_CONFIG_PREFIX/bin"

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
            echo ""
            echo "Run 'flutter doctor' to verify the installation."
          '';
        };
      }
    );
}
