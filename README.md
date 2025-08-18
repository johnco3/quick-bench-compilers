# quick-bench-compilers

Custom Dockerfiles and build scripts for Quick Bench compilers.
- Extends [`bench-runner`](https://github.com/FredTingaud/bench-runner)
- Supports experimental GCC, Clang, and other toolchains
- docker buildx build --platform linux/amd64,linux/arm64 -f Dockerfile -t johnco3/quick-bench:gcc-15.2.0 -t johnco3/quick-bench:latest --push .
- the following command inspects the published docker tag
```bash
docker buildx imagetools inspect johnco3/quick-bench:gcc-15.2.0
Name:      docker.io/johnco3/quick-bench:gcc-15.2.0
MediaType: application/vnd.oci.image.index.v1+json
Digest:    sha256:1ff3d431960d9db9d7e5217a6032ea870f4c0175e5cbc02a3d34616eb1131fd3

Manifests:
  Name:        docker.io/johnco3/quick-bench:gcc-15.2.0@sha256:7731714eb062037fcb4552b2c4c55a320923f25a77fcda8c87908fc99ce0daa8
  MediaType:   application/vnd.oci.image.manifest.v1+json
  Platform:    linux/amd64

  Name:        docker.io/johnco3/quick-bench:gcc-15.2.0@sha256:4faa6888d93c6bb8f7fb1692693d1de8ececd09bd3380deb5a7c0f08df36e3e1
  MediaType:   application/vnd.oci.image.manifest.v1+json
  Platform:    linux/arm64

  Name:        docker.io/johnco3/quick-bench:gcc-15.2.0@sha256:53a78d640fe52c88c8bd1e1453d75e6e3a303ffc5399f24dd998c0a3ad38c2e8
  MediaType:   application/vnd.oci.image.manifest.v1+json
  Platform:    unknown/unknown
  Annotations:
    vnd.docker.reference.digest: sha256:7731714eb062037fcb4552b2c4c55a320923f25a77fcda8c87908fc99ce0daa8
    vnd.docker.reference.type:   attestation-manifest

  Name:        docker.io/johnco3/quick-bench:gcc-15.2.0@sha256:64ca942dd9500fe7946913a34dc66962c8475af08303b268955d6ba924345c51
  MediaType:   application/vnd.oci.image.manifest.v1+json
  Platform:    unknown/unknown
  Annotations:
    vnd.docker.reference.digest: sha256:4faa6888d93c6bb8f7fb1692693d1de8ececd09bd3380deb5a7c0f08df36e3e1
    vnd.docker.reference.type:   attestation-manifest
```
