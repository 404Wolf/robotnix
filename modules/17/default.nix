# SPDX-FileCopyrightText: 2026 robotnix contributors
# SPDX-License-Identifier: MIT

{ config, lib, ... }:
# Android 17 (GrapheneOS 2026110200+, build IDs C*). Starts as a copy of
# modules/16; the patches were re-checked against the 2026110200 sources.
lib.mkIf (config.androidVersion == 17) {
  source.dirs = {
    "system/core".patches = [
      ./platform_system_core_permissions.patch
    ];

    "build/make".patches = [
      ./0001-Readonly-source-fix.patch
    ];

    "external/avb".patches = [
      ./avbtool-set-perms.patch
    ];

    # Signing (sign_target_files_apks -> apexer) runs outside the build
    # sandbox, where /bin/cp and /usr/bin/fallocate need not exist.
    "system/apex".patches = [
      ./apexer-host-tools-on-path.patch
    ];
  };

  # In https://android.googlesource.com/platform/build/+/322b51b245bc70bcbbd5538d40dd47c45565b67f,
  # AOSP switched over to using Soong for otatools.zip.
  otatoolsOutPath = "$ANDROID_HOST_OUT/obj/ETC/otatools-packagelinux_glibc_x86_64_intermediates/otatools-packagelinux_glibc_x86_64";

}
