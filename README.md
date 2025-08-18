# quick-bench-compilers

Custom Dockerfiles and build scripts for Quick Bench compilers.
- Extends [`bench-runner`](https://github.com/FredTingaud/bench-runner)
- Supports experimental GCC, Clang, and other toolchains
- docker buildx build --platform linux/amd64,linux/arm64 -f Dockerfile -t johnco3/quick-bench:gcc-15.2 -t johnco3/quick-bench:latest --push .
- the following command inspects the published docker tag
```bash
docker buildx imagetools inspect johnco3/quick-bench:latest
```
```docker
Name:      docker.io/johnco3/quick-bench:latest
MediaType: application/vnd.oci.image.index.v1+json
Digest:    sha256:8fac2ce77a99507f4c7737775697c45f73432728477aa17fe79506dddb85cab7

Manifests:
  Name:        docker.io/johnco3/quick-bench:latest@sha256:7731714eb062037fcb4552b2c4c55a320923f25a77fcda8c87908fc99ce0daa8
  MediaType:   application/vnd.oci.image.manifest.v1+json
  Platform:    linux/amd64

  Name:        docker.io/johnco3/quick-bench:latest@sha256:4faa6888d93c6bb8f7fb1692693d1de8ececd09bd3380deb5a7c0f08df36e3e1
  MediaType:   application/vnd.oci.image.manifest.v1+json
  Platform:    linux/arm64

  Name:        docker.io/johnco3/quick-bench:latest@sha256:4f11299f0aae3bc16d700d2eda7c89df67480a178a11d7397f68d58d5847e8ff
  MediaType:   application/vnd.oci.image.manifest.v1+json
  Platform:    unknown/unknown
  Annotations:
    vnd.docker.reference.digest: sha256:7731714eb062037fcb4552b2c4c55a320923f25a77fcda8c87908fc99ce0daa8
    vnd.docker.reference.type:   attestation-manifest

  Name:        docker.io/johnco3/quick-bench:latest@sha256:71c017491e39580c68917e64f4959bf3a37debc8e1b3aeca0415b9b68a9cc327
  MediaType:   application/vnd.oci.image.manifest.v1+json
  Platform:    unknown/unknown
  Annotations:
    vnd.docker.reference.digest: sha256:4faa6888d93c6bb8f7fb1692693d1de8ececd09bd3380deb5a7c0f08df36e3e1
    vnd.docker.reference.type:   attestation-manifest
    vnd.docker.reference.digest: sha256:4faa6888d93c6bb8f7fb1692693d1de8ececd09bd3380deb5a7c0f08df36e3e1
```
    vnd.docker.reference.type:   attestation-manifest
```
