#!/bin/bash

set -e

# 1. Check compiler version
# Now looking for 16.1 instead of 15.2
g++ --version | grep -q "16.1" || { echo "❌ GCC 16.1 not found"; exit 1; }

# 1b. Check build tooling expected in the runtime image
cmake --version >/dev/null 2>&1 || { echo "❌ cmake not found"; exit 1; }
ninja --version >/dev/null 2>&1 || { echo "❌ ninja not found"; exit 1; }

# 2. Check libraries (hardened)
# Handles /usr/local/lib vs /usr/local/lib64 and Boost tagged names.
find_lib() {
    local pattern="$1"
    find /usr/local/lib /usr/local/lib64 -maxdepth 1 -type f -name "$pattern" 2>/dev/null | head -n 1
}

require_lib() {
    local label="$1"
    shift
    local hit=""
    for pattern in "$@"; do
        hit="$(find_lib "$pattern")"
        if [ -n "$hit" ]; then
            echo "✅ Found $label: $hit"
            return 0
        fi
    done
    echo "❌ Missing $label (checked patterns: $*)"
    return 1
}

require_lib "boost filesystem"      "libboost_filesystem.a"      "libboost_filesystem-*.a"      || exit 1
require_lib "boost program_options" "libboost_program_options.a" "libboost_program_options-*.a" || exit 1
require_lib "benchmark"             "libbenchmark.a"             "libbenchmark*.a"              || exit 1
require_lib "ada"                   "libada.a"                   "libada*.a"                    || exit 1
require_lib "absl base"             "libabsl_base.a"             "libabsl_base*.a"              || exit 1

# 3. Check headers
for header in glaze/glaze.hpp ada.h benchmark/benchmark.h absl/base/config.h ankerl/unordered_dense.h; do
    [ -f "/usr/local/include/$header" ] || { echo "❌ Missing $header"; exit 1; }
done

# 4. Smoke test - exercises ada URL parsing
cat > /tmp/smoke_test.cpp << 'EOF'
#include <ada.h>
#include <iostream>

int main() {
    auto url = ada::parse("https://github.com/johnco3/bidder?tab=repositories");
    if (!url) return 1;
    std::cout << "✓ URL parsed path: " << url->get_pathname() << "\n";
    return 0;
}
EOF

# DEBUG: Ensure we are seeing the new GCC 16 paths
echo "DEBUG: CPLUS_INCLUDE_PATH=$CPLUS_INCLUDE_PATH"
echo "DEBUG: LD_LIBRARY_PATH=$LD_LIBRARY_PATH"

# 5. Compilation Test
g++ -std=c++26 /tmp/smoke_test.cpp \
    -Wl,-rpath,/usr/local/gcc-16/lib64 \
    -lada -o /tmp/smoke_test || { echo "❌ Compilation failed"; exit 1; }

# 6. Execution Test
/tmp/smoke_test || { echo "❌ Runtime execution failed"; exit 1; }

# Cleanup
rm /tmp/smoke_test.cpp /tmp/smoke_test

echo "✅ BUILD VERIFICATION SUCCESSFUL (GCC 16.1 / Ubuntu 25.10)"