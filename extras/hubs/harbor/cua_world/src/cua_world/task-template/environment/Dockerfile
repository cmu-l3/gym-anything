# Generic runtime for gym-anything Harbor tasks: QEMU inside the container
# boots the task's guest VM (the same shape gym-anything's ModalRunner
# sandbox uses). This file is identical across tasks; the task identity
# lives in gym-anything.json.
FROM python:3.12-slim-bookworm

RUN apt-get update && apt-get install --no-install-recommends -y \
        git \
        qemu-system-x86 \
        qemu-utils \
        wget \
        curl \
        ca-certificates \
        genisoimage \
        openssh-client \
        procps \
        unzip \
        zstd \
        tini \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

ARG GYM_ANYTHING_REF=__GYM_ANYTHING_REF__
RUN pip install --no-cache-dir \
    "gym-anything[vlm] @ git+https://github.com/cmu-l3/gym-anything@${GYM_ANYTHING_REF}"

COPY gym-anything.json /harbor-task/gym-anything.json

ENV GYM_ANYTHING_QEMU_CACHE=/gym-anything-cache/qemu \
    GA_HARBOR_PORT=7317 \
    GA_HARBOR_RUNNER=qemu

ENTRYPOINT ["tini", "-s", "--", "python", "-m", "gym_anything.integrations.harbor.container", "serve"]
