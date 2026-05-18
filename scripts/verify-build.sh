#!/bin/bash

set -e

# 1. Check compiler version
# Now looking for 16.1 instead of 15.2
g++ --version | grep -q "16.1" || { echo "❌ GCC 16.1 not found"; exit 1; }

# 1b. Check build tooling expected in the runtime image
cmake --version >/dev/null 2>&1 || { echo "❌ cmake not found"; exit 1; }
ninja --version >/dev/null 2>&1 || { echo "❌ ninja not found"; exit 1; }

# 2. Check libraries
# These paths remain the same as they are installed to /usr/local/lib
for lib in libboost_filesystem.a libboost_program_options.a libbenchmark.a libada.a libabsl_base.a; do
    [ -f "/usr/local/lib/$lib" ] || { echo "❌ Missing $lib"; exit 1; }
done

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