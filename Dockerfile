# syntax=docker/dockerfile:1.4

############### Stage 1: Build GCC ###############
FROM ubuntu:25.04 AS builder

ARG DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    build-essential \
    wget \
    curl \
    git \
    cmake \
    flex \
    bison \
    libgmp-dev \
    libmpfr-dev \
    libmpc-dev \
    libisl-dev \
    zlib1g-dev \
    libzstd-dev \
    python3 \
    ninja-build \
    xz-utils \
    bzip2 \
    && rm -rf /var/lib/apt/lists/*

ARG GCC_VERSION=15.2.0

WORKDIR /tmp
RUN wget https://gcc.gnu.org/pub/gcc/releases/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.xz && \
    tar -xf gcc-${GCC_VERSION}.tar.xz && \
    mv gcc-${GCC_VERSION} gcc-source && \
    rm gcc-${GCC_VERSION}.tar.xz

WORKDIR /tmp/gcc-source
RUN ./contrib/download_prerequisites

WORKDIR /tmp/gcc-build
RUN /tmp/gcc-source/configure \
    --prefix=/usr/local/gcc-15 \
    --enable-languages=c,c++ \
    --disable-multilib \
    --enable-threads=posix \
    --enable-shared \
    --disable-static \
    --enable-__cxa_atexit \
    --enable-clocale=gnu \
    --enable-gnu-unique-object \
    --enable-linker-build-id \
    --enable-lto \
    --enable-plugin \
    --disable-werror \
    --enable-checking=release \
    --with-system-zlib \
    --program-suffix=-15

RUN make -j$(nproc) && make install

RUN find /usr/local/gcc-15 -type f -executable -exec strip {} + 2>/dev/null || true
RUN rm -rf /usr/local/gcc-15/share/man \
           /usr/local/gcc-15/share/info \
           /usr/local/gcc-15/share/locale

# Range-v3 headers
RUN git clone --depth 1 --branch 0.3.0 https://github.com/ericniebler/range-v3.git /tmp/range-v3 && \
    mkdir -p /usr/local/include/range-v3 && \
    cp -r /tmp/range-v3/include/* /usr/local/include/ && \
    rm -rf /tmp/range-v3

# Boost headers (header-only libraries)
ARG BOOST_VERSION=1.89.0
ARG BOOST_VERSION_UNDERSCORE=1_89_0

RUN wget https://archives.boost.io/release/${BOOST_VERSION}/source/boost_${BOOST_VERSION_UNDERSCORE}.tar.bz2 && \
    tar -xf boost_${BOOST_VERSION_UNDERSCORE}.tar.bz2 && \
    cp -r boost_${BOOST_VERSION_UNDERSCORE}/boost /usr/local/include/ && \
    rm -rf boost_${BOOST_VERSION_UNDERSCORE}*

# Build & install Google Benchmark from source
WORKDIR /tmp
RUN git clone --depth=1 https://github.com/google/benchmark.git && \
    git clone --depth=1 https://github.com/google/googletest.git benchmark/googletest && \
    mkdir -p benchmark/build && cd benchmark/build && \
    cmake -GNinja -DCMAKE_BUILD_TYPE=Release .. && \
    ninja && ninja install && \
    rm -rf /tmp/benchmark

# Final Stage 1 cleanup - remove build artifacts
RUN rm -rf /tmp/gcc-source /tmp/gcc-build

############### Stage 2: Runtime ###############
FROM ubuntu:25.04

ARG DEBIAN_FRONTEND=noninteractive

# Install runtime packages (minimal; no nodejs, no docker)
RUN apt-get update && apt-get install -y --no-install-recommends \
    binutils \
    libc6-dev \
    linux-libc-dev \
    linux-perf \
    linux-tools-generic \
    linux-tools-common \
    time \
    util-linux \
    vmtouch \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/gcc-15 /usr/local/gcc-15
COPY --from=builder /usr/local/lib /usr/local/lib
COPY --from=builder /usr/local/include /usr/local/include

ENV PATH="/usr/local/gcc-15/bin:/usr/local/bin:${PATH}"
ENV LD_LIBRARY_PATH="/usr/local/gcc-15/lib64:/usr/local/lib:/usr/local/gcc-15/lib"
ENV CC="/usr/local/gcc-15/bin/gcc-15"
ENV CXX="/usr/local/gcc-15/bin/g++-15"

RUN ln -sf /usr/local/gcc-15/bin/gcc-15 /usr/local/bin/gcc && \
    ln -sf /usr/local/gcc-15/bin/g++-15 /usr/local/bin/g++

RUN useradd -m builder
RUN usermod -g users builder
RUN chown builder:users \
    /home/builder/.bash_logout \
    /home/builder/.bashrc \
    /home/builder/.profile

WORKDIR /home/builder

COPY scripts/* /home/builder/

RUN for f in about-me annotate build prebuild run time-build; do \
    chmod +x /home/builder/$f; \
    done && \
    chmod -x /home/builder/experimental-flags

# Final checks
RUN /usr/local/gcc-15/bin/gcc-15 --version && \
    /usr/local/gcc-15/bin/g++-15 --version && \
    echo "Built for architecture: $(uname -m)" && \
    which perf && perf --version || true && \
    which vmtouch && (vmtouch 2>&1 | head -n 1 | grep -q vmtouch) && \
    echo "All mandatory tools verified - GCC 15.2 container ready for Quick Bench"

# Switch to non-root user
USER builder