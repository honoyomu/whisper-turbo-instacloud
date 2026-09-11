# InstaCloud deploy image: builds the native C server AND bakes in the
# converted INT8 Whisper Turbo model, so the container is self-contained.
# Multi-stage: compile tools/server, download+verify+convert the model,
# then assemble a minimal runtime image.

FROM debian:bookworm-slim AS build
RUN apt-get update && apt-get install -y --no-install-recommends \
      gcc make libc6-dev zlib1g-dev libgomp1 curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY Makefile ./
COPY src ./src
COPY tools ./tools
RUN make server OPENMP=-fopenmp CFLAGS='-O3 -std=c11 -Wall -Wextra -Wpedantic -Werror'
RUN make x86-tools OPENMP=-fopenmp

FROM build AS model
WORKDIR /model
# Pinned upstream GGML F16 checkpoint (see docs/pins.json in the source repo).
ARG GGML_URL=https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin
ARG GGML_SHA256=1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69
RUN curl -fL -o ggml-large-v3-turbo.bin "$GGML_URL" \
    && echo "${GGML_SHA256}  ggml-large-v3-turbo.bin" | sha256sum -c - \
    && /src/build/import-ggml ggml-large-v3-turbo.bin turbo-q8.whtrbo \
    && rm -f ggml-large-v3-turbo.bin

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends libgomp1 zlib1g \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /src/build/whisper-turbo-server /usr/local/bin/whisper-turbo-server
COPY --from=model /model/turbo-q8.whtrbo /models/turbo-q8.whtrbo
RUN chmod 0644 /models/turbo-q8.whtrbo
USER 65534:65534
ENV OMP_NUM_THREADS=8
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/whisper-turbo-server"]
CMD ["/models/turbo-q8.whtrbo", "8080", "0.0.0.0"]
