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

# Range-v3 headers (as in your original)
RUN git clone --depth 1 --branch 0.3.0 https://github.com/ericniebler/range-v3.git /tmp/range-v3 && \
    cp -r /tmp/range-v3/include/* /usr/local/gcc-15/include/ && \
    rm -rf /tmp/range-v3

# Build & install Google Benchmark from source
WORKDIR /tmp
RUN git clone --depth=1 https://github.com/google/benchmark.git && \
    git clone --depth=1 https://github.com/google/googletest.git benchmark/googletest && \
    mkdir -p benchmark/build && cd benchmark/build && \
    cmake -GNinja -DCMAKE_BUILD_TYPE=Release .. && \
    ninja && ninja install && \
    rm -rf /tmp/benchmark

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
WORKDIR /home/builder

# --- Heredoc scripts (unchanged from your version) ---

# build
COPY <<'EOF' /home/builder/build
#!/bin/bash
$CXX "$@" bench-file.cpp -o bench -lbenchmark -lpthread
EOF

# run
COPY <<'EOF' /home/builder/run
#!/bin/bash
./bench --benchmark_format=json --benchmark_out=/home/builder/bench.out
EOF

# time-build
COPY <<'EOF' /home/builder/time-build
#!/bin/bash
set -e

FILENAME=$1
PARAMETERS="${@:2}"
COUNTER=0
SECONDS=0
# default 60s timeout can be changed with an environment variable
MAX_TIME="${BB_TIMEOUT:-60}"
MAX_COUNTER="${BB_MAX:-20}"
LAST_TIME=0
MAX_DURATION=0

# Generate a list of all used includes to display
$CXX -H -fsyntax-only $PARAMETERS "$FILENAME" 2> bench.inc
# Make a cleaned copy that can be used as input for vmtouch
sed -r 's/\.+ //' bench.inc | xargs -r realpath > bench.cache
echo "$1" >> bench.cache

while [[ $COUNTER -lt $MAX_COUNTER && $SECONDS -lt $((MAX_TIME - MAX_DURATION)) ]]; do
  # Make sure no include is in the cache before starting the build
  vmtouch -eq $(< bench.cache) || true
  script --flush --quiet --return output.txt --command "/usr/bin/time -o one-bench.out -f \"%U\\t%S\\t%M\\t%I\\t%O\\t%F\\t%R\" $CXX -c $PARAMETERS $FILENAME"
  (( COUNTER=COUNTER+1 ))
  if (( MAX_DURATION < SECONDS-LAST_TIME ))
  then
   (( MAX_DURATION = SECONDS-LAST_TIME ))  || true
  fi
  cat one-bench.out >> bench.out
  (( LAST_TIME=SECONDS )) || true
done
EOF

# prebuild
COPY <<'EOF' /home/builder/prebuild
#!/bin/bash
set -e

FILENAME=$1
PREPROC=$2
ASM=$3
PARAMETERS="${@:4}"

if [ $PREPROC = true ]; then
    $CXX -E $PARAMETERS $FILENAME > bench.i
fi

if [ "$ASM" != "none" ]; then
    $CXX -S -masm=$ASM -o bench.ss $PARAMETERS $FILENAME
    # -S tries to remove the output instead of overwriting it.
    # So instead we use a temp file then cp on the target, that will overwrite
    cp bench.ss bench.s
fi
EOF

# annotate
COPY <<'EOF' /home/builder/annotate
#!/bin/bash

while read -r line ;
do echo "----------- $line" >> bench.perf
perf annotate "$@" --stdio $line >> bench.perf 2>/dev/null || echo "Could not annotate $line" >> bench.perf ;
done <bench.func
EOF

# about-me
COPY <<'EOF' /home/builder/about-me
#!/bin/bash

stty cols 200

echo "[version]"
echo "1"

echo "[std]"
g++ --help -v 2>/dev/null | grep -E "\-std=c\+\+(11|14|17|20|23|26|2c)" | grep -v "Deprecated" | grep -v "Same as" | grep -oE "c\+\+(11|14|17|20|23|26|2c)" | sort -u

echo "[experimental]"
g++ --help -v 2>/dev/null | ( grep -oFwf /home/builder/experimental-flags || [ "$?" == "1" ] )

echo "[boost]"

echo "[libs]"
echo "gnu"

echo "[flags]"
echo "-ffast-math"
echo "-fno-exceptions"
echo "-fno-rtti"
echo "-march=native"
echo "-mtune=native"
EOF

# experimental-flags
COPY <<'EOF' /home/builder/experimental-flags
-fcoroutines
-fconcepts
-fconcepts-ts
-fmodules-ts
-fchar8_t
-fconsteval
-fconstinit
-fimplicit-move
EOF

# Ensure scripts are executable and LF-only
RUN chmod +x /home/builder/* \
 && for f in /home/builder/*; do sed -i 's/\r$//' "$f"; done

# Final checks
RUN /usr/local/gcc-15/bin/gcc-15 --version && \
    /usr/local/gcc-15/bin/g++-15 --version && \
    echo "Built for architecture: $(uname -m)" && \
    which perf && perf --version || true && \
    which vmtouch && (vmtouch 2>&1 | head -n 1 | grep -q vmtouch) && \
    echo "All mandatory tools verified - GCC 15.2 container ready for Quick Bench"

USER builder

