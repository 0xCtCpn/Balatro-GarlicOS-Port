FROM debian:bookworm
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    gcc g++ make pkg-config git python3 curl ca-certificates \
    autoconf automake libtool file xz-utils bzip2 unzip zip \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /build

# musl cross for C bits (alsa + garlic-audio), same INTERP trick as HalfLife
RUN curl -sL https://musl.cc/armv7l-linux-musleabihf-cross.tgz -o musl.tgz && \
    tar xzf musl.tgz -C /opt && rm musl.tgz
ENV PATH=/opt/armv7l-linux-musleabihf-cross/bin:$PATH
ENV MUSL_TRIPLE=armv7l-linux-musleabihf

# alsa-lib for ARM (Garlic audio path, same prefix layout as HalfLife)
RUN curl -sSL --retry 3 --retry-all-errors https://www.alsa-project.org/files/pub/lib/alsa-lib-1.2.12.tar.bz2 -o alsa.tar.bz2 && \
    tar xjf alsa.tar.bz2 && cd alsa-lib-1.2.12 && \
    CC=${MUSL_TRIPLE}-gcc CFLAGS="-march=armv7-a -mfpu=neon -mfloat-abi=hard -O2" \
    ./configure --host=${MUSL_TRIPLE} --prefix=/opt/arm-alsa \
      --disable-python --disable-aload --without-debug && \
    make -j$(nproc) && make install

# Rust 1.97.1 + Zig 0.16.0 + cargo-zigbuild 0.23.4 (matches upstream)
RUN curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain 1.97.1 && \
    (curl -sSL --retry 3 https://ziglang.org/download/0.16.0/zig-x86_64-linux-0.16.0.tar.xz -o zig.tar.xz || \
     curl -sSL --retry 3 https://github.com/ziglang/zig/releases/download/0.16.0/zig-x86_64-linux-0.16.0.tar.xz -o zig.tar.xz) && \
    tar xf zig.tar.xz -C /opt && ln -sf /opt/zig-x86_64-linux-0.16.0/zig /usr/local/bin/zig
ENV PATH=/root/.cargo/bin:$PATH
RUN cargo install --locked cargo-zigbuild --version 0.23.4 && \
    rustup target add armv7-unknown-linux-musleabihf

COPY upstream /build/upstream
COPY native /build/native-patch
# Garlic audio-platform edit is already applied in upstream working copy
# (see patches/garlic-platform.patch as reference). Verify it is present:
RUN grep -q 'Ok("garlic")' /build/upstream/crates/love-api/src/audio/output.rs && echo "garlic patch present"

# LuaJIT static cross from x86_64 host: HOST_CC must emit 32-bit (gcc -m32),
# CROSS prefix selects the arm musl tools (per LuaJIT "pointer size mismatch" msg)
RUN apt-get update && apt-get install -y gcc-multilib && rm -rf /var/lib/apt/lists/* && \
    cd /build/upstream && \
    export BALATRO_LUAJIT_DIR=/build/luajit-armv7-musl && \
    mkdir -p $BALATRO_LUAJIT_DIR && \
    cargo fetch --locked && \
    SRC=$(find /root/.cargo/registry/src -maxdepth 2 -type d -name "luajit-src-*" -print -quit) && \
    echo "luajit src $SRC" && \
    rm -rf /tmp/lj && cp -a $SRC/luajit2 /tmp/lj && \
    make -C /tmp/lj -j$(nproc) BUILDMODE=static CC=${MUSL_TRIPLE}-gcc HOST_CC="gcc -m32" \
      STATIC_CC=${MUSL_TRIPLE}-gcc TARGET_LD=${MUSL_TRIPLE}-gcc CROSS=${MUSL_TRIPLE}- TARGET_SYS=Linux && \
    cp /tmp/lj/src/libluajit.a $BALATRO_LUAJIT_DIR/libluajit-5.1.a && \
    cp /opt/armv7l-linux-musleabihf-cross/armv7l-linux-musleabihf/lib/libgcc.a $BALATRO_LUAJIT_DIR/libgcc.a || \
    ${MUSL_TRIPLE}-gcc -print-libgcc-file-name | xargs -I{} cp {} $BALATRO_LUAJIT_DIR/libgcc.a

# SLEEF (upstream script hardcodes cortex_a7+neon-vfpv4 for Miyoo A7;
# base RG35XX is Cortex-A9: no VFPv4, SIGILL otherwise. Retarget before build.)
RUN cd /build/upstream && \
    sed -i 's/-mcpu=cortex_a7/-mcpu=cortex_a9/g; s/-mfpu=neon-vfpv4/-mfpu=neon/g' scripts/build-sleef.sh && \
    grep -n "mcpu\|mfpu" scripts/build-sleef.sh && \
    sh scripts/build-sleef.sh

# Runtime (Cortex-A9 + NEON only: no +vfp4, A9 traps VFPv4 as SIGILL)
RUN cd /build/upstream && \
    export LUA_LIB=/build/luajit-armv7-musl LUA_LIB_NAME=luajit-5.1 LUA_LINK=static && \
    export RUSTFLAGS="-C target-cpu=cortex-a9 -C target-feature=+neon -L native=/build/luajit-armv7-musl -l static=gcc" && \
    cargo zigbuild --locked --release -p balatro-runtime --target armv7-unknown-linux-musleabihf --features arm-neon,flame-simd,layer-pairs

# garlic-audio helper (musl + alsa; INTERP must be /tmp like HalfLife:
# SYSTEM /lib is read-only EGLIBC, loader is staged there by Balatro.sh)
RUN ${MUSL_TRIPLE}-gcc -march=armv7-a -mfpu=neon -mfloat-abi=hard -O2 -s -Wall \
    -Wl,--dynamic-linker,/tmp/ld-musl-armhf.so.1 \
    -I/opt/arm-alsa/include /build/native-patch/garlic-audio.c \
    -L/opt/arm-alsa/lib -lasound -o /build/upstream/target/armv7-unknown-linux-musleabihf/release/balatro-audio && \
    ${MUSL_TRIPLE}-readelf -l /build/upstream/target/armv7-unknown-linux-musleabihf/release/balatro-audio | grep -A1 INTERP || true; \
    ${MUSL_TRIPLE}-readelf -d /build/upstream/target/armv7-unknown-linux-musleabihf/release/balatro-audio | grep NEEDED || true

CMD mkdir -p /out && \
    cp /build/upstream/target/armv7-unknown-linux-musleabihf/release/balatro-runtime /out/ && \
    cp /build/upstream/target/armv7-unknown-linux-musleabihf/release/balatro-audio /out/ && \
    cp -r /opt/arm-alsa/share/alsa /out/share 2>/dev/null || (mkdir -p /out/share && cp -r /opt/arm-alsa/share/alsa /out/share/); \
    cp /opt/arm-alsa/lib/libasound.so* /out/ 2>/dev/null || true; \
    MUSLLIB=/opt/armv7l-linux-musleabihf-cross/armv7l-linux-musleabihf/lib; \
    cp $MUSLLIB/libc.so /out/ 2>/dev/null || true; \
    cp $MUSLLIB/libc.so /out/ld-musl-armhf.so.1 2>/dev/null || true; \
    ls -lh /out/ && \
    echo "--- NEEDED balatro-audio ---" && ${MUSL_TRIPLE}-readelf -d /out/balatro-audio | grep NEEDED || true; \
    echo "--- no GLIBC expected in runtime (static) ---" && ${MUSL_TRIPLE}-readelf -sW --dyn-syms /out/balatro-runtime 2>/dev/null | grep -o "@GLIBC_[0-9.]*" | sort -u || true
