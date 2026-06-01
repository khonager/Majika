{
  description = "Flutter & Android Development Environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            android_sdk.accept_license = true;
          };
        };

        # Android SDK components
        androidComposition = pkgs.androidenv.composeAndroidPackages {
          cmdLineToolsVersion = "8.0";
          toolsVersion = "26.1.1";
          platformToolsVersion = "36.0.2";
          buildToolsVersions = [ "28.0.3" "30.0.3" "33.0.1" "34.0.0" "35.0.0" ];
          includeEmulator = true;
          emulatorVersion = "36.4.2";
          platformVersions = [ "28" "33" "34" "36" ];
          includeSources = false;
          includeSystemImages = false;
          systemImageTypes = [ "google_apis_playstore" ];
          abiVersions = [ "armeabi-v7a" "arm64-v8a" ];
          cmakeVersions = [ "3.22.1" ];
          includeNDK = true;
          ndkVersions = [ "28.2.13676358" ];
          useGoogleAPIs = false;
          useGoogleTVAddOns = false;
          includeExtras = [
            "extras;google;gcm"
          ];
        };

        androidSdk = androidComposition.androidsdk;

      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            flutter
            jdk17
            nodejs_20
            firebase-tools
            androidSdk
            
            # Additional tools often needed for Flutter/Linux compilation
            pkg-config
            ninja
            cmake
            clang
            gtk3
            glib
            pcre2
          ];

          ANDROID_HOME = "${androidSdk}/libexec/android-sdk";
          JAVA_HOME = pkgs.jdk17.home;
          CHROME_EXECUTABLE = "${pkgs.google-chrome}/bin/google-chrome-stable";

          shellHook = ''
            export PATH="$PATH:$ANDROID_HOME/tools:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/8.0/bin:$HOME/.pub-cache/bin"

            if ! command -v flutterfire >/dev/null 2>&1; then
              echo "Installing flutterfire_cli into Dart pub cache..."
              dart pub global activate flutterfire_cli >/dev/null
            fi

            echo "📱 Flutter and Android Development Environment loaded!"
            echo "Environment variables set:"
            echo "  ANDROID_HOME=$ANDROID_HOME"
            echo "  JAVA_HOME=$JAVA_HOME"
            echo "  Firebase CLI=$(firebase --version)"
            echo "  FlutterFire CLI=$(flutterfire --version)"
            echo ""
            echo "Run 'flutter doctor' to verify the installation."
          '';
        };
      }
    );
}
