#!/bin/bash
set -euo pipefail

dnf5 install -y --setopt=install_weak_deps=False \
    cmake gcc-c++ make qt5-qtbase-devel qt6-qtbase-devel qt6-qtshadertools

for major in 5 6; do
    cmake -S /source/native/qt-theme -B "/tmp/qt${major}" \
        -DQT_MAJOR="$major" -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF
    cmake --build "/tmp/qt${major}" --parallel 2
    mkdir -p "/out/qt-theme/qt${major}"
    cp -R "/tmp/qt${major}/plugins" "/out/qt-theme/qt${major}/"
done

rpm -q --qf '%{NAME}-%{EVR}.%{ARCH}\n' \
    qt5-qtbase qt5-qtbase-common qt5-qtbase-gui \
    qt6-qtbase qt6-qtbase-common qt6-qtbase-gui > /out/qt-packages

mkdir -p /out/shaders
for shader in /source/assets/shaders/*.vert /source/assets/shaders/*.frag; do
    qsb-qt6 --glsl '100 es,120,150' --hlsl 50 --msl 12 \
        -o "/out/shaders/$(basename "$shader").qsb" "$shader"
done
