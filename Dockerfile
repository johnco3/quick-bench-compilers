# syntax=docker/dockerfile:1.4

############### Stage 1: Build GCC & Libs ###############
# Using ubuntu:25.10 (bare tag) until 26.04 has CVEs resolved.
# The bare tag resolves to the current multi-arch manifest list, so
# linux/amd64 and linux/arm64 builds both work without manual digest pinning.
FROM ubuntu:25.10 AS builder
ARG DEBIAN_FRONTEND=noninteractive

# 2. Build Dependencies
# apt-get -y upgrade pulls in security fixes published since the base image
# was last rebuilt, so we stay current without re-pinning.
RUN apt-get update \
    && apt-get -y upgrade \
    && apt-get install -y --no-install-recommends \
       build-essential ca-certificates wget curl git cmake ninja-build \
       python3 zlib1g-dev xz-utils bzip2 file \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# --- UPDATED TO GCC 16.1 ---
ARG GCC_VERSION=16.1.0
# Optional override for parallel build jobs, e.g. --build-arg NPROC=16
ARG NPROC

# 3. Build GCC 16.1
WORKDIR /tmp
RUN wget https://gcc.gnu.org/pub/gcc/releases/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.xz && \
    tar -xf gcc-${GCC_VERSION}.tar.xz && \
    mv gcc-${GCC_VERSION} gcc-source && \
    cd gcc-source && ./contrib/download_prerequisites

WORKDIR /tmp/gcc-build
# Keep configure/build/install in separate layers so cache can be reused
# across minor downstream changes (e.g. script edits in the final stage).
RUN /tmp/gcc-source/configure \
    --prefix=/usr/local/gcc-16 \
    --enable-languages=c,c++ \
    --disable-multilib \
    --enable-threads=posix \
    --enable-shared \
    --disable-static \
    --program-suffix=-16

RUN make -j${NPROC:-$(nproc)}

# Install stripped binaries/libs to reduce final image size.
# make install-strip only strips the driver binaries (gcc-16, g++-16).
# The large internal executables in libexec/ (cc1, cc1plus, lto1) must be
# stripped explicitly; this alone saves ~500-800 MB from the final image.
RUN make install-strip \
    && find /usr/local/gcc-16 -type f \
       \( -name "cc1" -o -name "cc1plus" -o -name "lto1" -o -name "lto-wrapper" \
          -o -name "collect2" -o -name "f951" \) \
       -exec strip --strip-unneeded {} \; 2>/dev/null || true

# 4. Static Library Builds
# Keep pinned tarball builds before moving git HEAD clones to maximize cache reuse.
# jemalloc (Pinned to latest stable release after a multi-year hiatus)
ARG JEMALLOC_VERSION=5.3.1
RUN wget https://github.com/jemalloc/jemalloc/releases/download/${JEMALLOC_VERSION}/jemalloc-${JEMALLOC_VERSION}.tar.bz2 && \
    tar -xf jemalloc-${JEMALLOC_VERSION}.tar.bz2 && \
    cd jemalloc-${JEMALLOC_VERSION} && \
    ./configure --prefix=/usr/local && \
    make -j${NPROC:-$(nproc)} && \
    make install && \
    rm -rf /tmp/jemalloc-${JEMALLOC_VERSION} /tmp/jemalloc-${JEMALLOC_VERSION}.tar.bz2

# Boost 1.91.0 with selected static libs
ARG BOOST_VERSION_UNDERSCORE=1_91_0
RUN wget https://archives.boost.io/release/1.91.0/source/boost_${BOOST_VERSION_UNDERSCORE}.tar.bz2 && \
    tar -xf boost_${BOOST_VERSION_UNDERSCORE}.tar.bz2 && \
    cd boost_${BOOST_VERSION_UNDERSCORE} && \
    ./bootstrap.sh --prefix=/usr/local --with-toolset=gcc && \
    ./b2 install \
      --with-filesystem \
      --with-regex \
      --with-program_options \
      --with-iostreams \
      --with-thread \
      --with-chrono \
      --with-date_time \
      --with-atomic \
      --layout=system \
      --prefix=/usr/local \
      --libdir=/usr/local/lib \
      toolset=gcc \
      variant=release \
      link=static \
      threading=multi \
      cxxflags="-fPIC" && \
    (find /usr/local/lib -type f -name "libboost_*.a" -exec strip --strip-debug {} \; || true) && \
    find /usr/local/lib -maxdepth 1 -type f -name "libboost_*.a" | sort && \
    cd .. && \
    rm -rf boost_${BOOST_VERSION_UNDERSCORE} boost_${BOOST_VERSION_UNDERSCORE}.tar.bz2

# Ada-URL - latest greatest
RUN git clone --depth 1 https://github.com/ada-url/ada.git /tmp/ada && \
    cmake -S /tmp/ada -B /tmp/ada/build -GNinja -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF -DCMAKE_CXX_COMPILER=/usr/local/gcc-16/bin/g++-16 \
    -DCMAKE_INSTALL_PREFIX=/usr/local -DCMAKE_POSITION_INDEPENDENT_CODE=ON && \
    ninja -C /tmp/ada/build install

# Google Benchmark - latest greatest
RUN git clone --depth 1 https://github.com/google/benchmark.git /tmp/benchmark && \
    cmake -S /tmp/benchmark -B /tmp/benchmark/build -GNinja \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DBENCHMARK_ENABLE_TESTING=OFF \
    -DBENCHMARK_ENABLE_GTEST_TESTS=OFF \
    -DBENCHMARK_USE_BUNDLED_GTEST=OFF \
    -DCMAKE_CXX_COMPILER=/usr/local/gcc-16/bin/g++-16 \
    -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON && \
    ninja -C /tmp/benchmark/build install && \
    rm -rf /tmp/benchmark

# Abseil
RUN git clone --depth 1 https://github.com/abseil/abseil-cpp.git /tmp/abseil-cpp && \
    cmake -S /tmp/abseil-cpp -B /tmp/abseil-cpp/build -GNinja \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DABSL_BUILD_TESTING=OFF \
    -DABSL_PROPAGATE_CXX_STD=ON \
    -DCMAKE_CXX_COMPILER=/usr/local/gcc-16/bin/g++-16 \
    -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON && \
    ninja -C /tmp/abseil-cpp/build install && \
    rm -rf /tmp/abseil-cpp

# ankerl::unordered_dense (Header-Only)
RUN git clone --depth 1 https://github.com/martinus/unordered_dense.git /tmp/unordered_dense && \
    cp -r /tmp/unordered_dense/include/ankerl /usr/local/include/ && \
    rm -rf /tmp/unordered_dense

# Glaze (Header-Only)
RUN git clone --depth 1 https://github.com/stephenberry/glaze.git /tmp/glaze && \
    cp -r /tmp/glaze/include/glaze /usr/local/include/


############### Stage 2: Final Runtime ###############
FROM ubuntu:25.10

ARG DEBIAN_FRONTEND=noninteractive

# 1. Install Runtime & Development headers
# Same upgrade-then-install pattern as the builder stage.
RUN apt-get update \
    && apt-get -y upgrade \
    && apt-get install -y --no-install-recommends \
    cmake ninja-build gdb python3 vim jq ripgrep sudo \
       dpkg-dev binutils libc6-dev linux-libc-dev libuv1-dev libfmt-dev \
         ca-certificates curl procmail git rapidjson-dev \
       liblog4cplus-dev libspdlog-dev \
       linux-perf linux-tools-generic \
       librange-v3-dev libssl-dev libsnappy-dev libhiredis-dev libyaml-cpp-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. Version Tracking & Metadata
ADD https://api.github.com/repos/johnco3/quick-bench-back-end/git/refs/heads/main /opt/backend-version.json

# 3. Copy toolchain and artifacts
COPY --from=builder /usr/local/gcc-16 /usr/local/gcc-16
COPY --from=builder /usr/local/lib /usr/local/lib
COPY --from=builder /usr/local/include /usr/local/include
COPY --from=builder /usr/local/bin/jemalloc-config /usr/local/bin/jemalloc-config

# Configure GDB to load libstdc++ pretty-printers for the custom GCC toolchain
RUN mkdir -p /etc/gdb \
    && printf '%s\n' \
       'set print pretty on' \
       'set print object on' \
       'set print elements 0' \
       'python import sys' \
       'python sys.path.insert(0, "/usr/local/gcc-16/share/gcc-16/python")' \
       'python sys.path.insert(0, "/usr/share/gcc/python")' \
       'python from libstdcxx.v6.printers import register_libstdcxx_printers' \
       'python register_libstdcxx_printers(None)' \
       > /etc/gdb/gdbinit

# 4. Environment & Linker Configuration
ENV PATH="/usr/local/gcc-16/bin:/usr/local/bin:${PATH}"
ENV CC="gcc-16"
ENV CXX="g++-16"
# Note: GCC 16 stores libs in lib64 on x86_64 Ubuntu
ENV LD_LIBRARY_PATH="/usr/local/gcc-16/lib64:/usr/local/lib"
RUN ldconfig

# Set global aliases so 'gcc' calls 'gcc-16'
RUN ln -sf /usr/local/gcc-16/bin/gcc-16 /usr/local/bin/gcc && \
    ln -sf /usr/local/gcc-16/bin/g++-16 /usr/local/bin/g++

# 5. User Setup
RUN useradd -m -s /bin/bash builder
RUN usermod -aG sudo builder \
    && printf 'builder ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/builder \
    && chmod 0440 /etc/sudoers.d/builder
WORKDIR /home/builder

# 6. Copy and assign permissions to scripts
COPY scripts/* /home/builder/

RUN for f in about-me annotate build prebuild run time-build verify-build.sh; do \
    if [ -f "/home/builder/$f" ]; then \
    chmod +x "/home/builder/$f"; \
    else \
    echo "Error: Script $f missing"; exit 1; \
    fi; \
    done && \
    chmod -x /home/builder/experimental-flags && \
    chown -R builder:builder /home/builder

# 7. Quality Assurance
USER builder
RUN /home/builder/verify-build.sh

# Keep a non-root default, but allow overrides at build time:
# docker build --build-arg DEFAULT_USER=root ...
ARG DEFAULT_USER=builder
USER ${DEFAULT_USER}
