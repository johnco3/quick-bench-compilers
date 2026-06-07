# quick-bench-compilers

Custom Dockerfiles and build scripts for Quick Bench compilers.
- Extends [`bench-runner`](https://github.com/FredTingaud/bench-runner)
- Supports experimental GCC, Clang, and other toolchains

## Bundled Third-Party Libraries

The image bundles a set of commonly used third-party libraries in `/usr/local`, including:

- Boost (filesystem, regex, iostreams, chrono, threads, program_options, etc.)
- jemalloc
- Ada URL
- Google Benchmark
- Abseil
- ankerl::unordered_dense
- Glaze

## Build Workflow (buildx + named builder)

This project is intended to be built as a multi-arch image (`linux/amd64` + `linux/arm64`).

### 1. One-time setup per machine (Windows PC and macOS)

Run on each machine once:

```bash
docker login
docker buildx create --name qb --driver docker-container --use
docker buildx inspect --bootstrap
docker buildx ls
```

This creates a builder `qb`.  If it is present the --builder qb is optional.

### 2. Preferred default: local cache only (no extra registry cache traffic)

Use this command for normal release pushes:

```bash
docker buildx build --builder qb --platform linux/amd64,linux/arm64 -f Dockerfile -t johnco3/quick-bench:gcc-16.1 --build-arg NPROC=16 --push .
```

Notes:
- Reusing the same `qb` builder preserves local BuildKit cache on that machine.
- On Apple Silicon Macs, arm64 build steps run natively and are typically much faster.

### 3. Optional (recommended): shared registry cache across machines

Use this only when you want cache reuse between machines (for example Windows -> Mac):

First run (seed cache):

```bash
docker buildx build --builder qb --platform linux/amd64,linux/arm64 -f Dockerfile -t johnco3/quick-bench:gcc-16.1 -t johnco3/quick-bench:latest --cache-from type=registry,ref=johnco3/quick-bench:buildcache --cache-to type=registry,ref=johnco3/quick-bench:buildcache,mode=max --build-arg NPROC=16 --load .
```

Later runs (reuse + refresh cache):

```bash
docker buildx build --builder qb --platform linux/amd64,linux/arm64 -f Dockerfile -t johnco3/quick-bench:gcc-16.1 --cache-from type=registry,ref=johnco3/quick-bench:buildcache --cache-to type=registry,ref=johnco3/quick-bench:buildcache,mode=max --build-arg NPROC=16 --load .
```

If the first run shows `ERROR importing cache manifest ... buildcache`, this is expected before cache is seeded. The build will still complete and seed cache via the `--cache-to` option.

### 4. Quick local test build before multi-arch push

Use this to validate Dockerfile changes quickly.  This builds on the local architecture and creates a local docker image.

```bash
docker buildx build --builder qb --platform linux/amd64 -f Dockerfile -t johnco3/quick-bench:gcc-16.1-local --build-arg NPROC=16 --load .
```

### 5. Verify Docker Hub contains both architectures

```bash
docker buildx imagetools inspect johnco3/quick-bench:gcc-16.1
```

Look for:
- `Platform: linux/amd64`
- `Platform: linux/arm64`

`unknown/unknown` entries are attestation manifests and are expected.

### 6. Retag and push from an existing local image

```bash
docker tag johnco3/quick-bench:gcc-16.1-local johnco3/quick-bench:gcc-16.1
docker push johnco3/quick-bench:gcc-16.1
```

### 7. Cache hygiene

- Avoid `docker builder prune` unless disk pressure requires it.
- Pruning clears local cache and can force long rebuilds.
