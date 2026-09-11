# InstaCloud deploy image: builds the native C server only (fast, small
# build); the converted INT8 Whisper Turbo model is fetched and produced
# on first boot into a persistent /data volume, so the model download
# never has to happen inside the (time/size constrained) remote image build.
FROM debian:bookworm-slim AS build
RUN apt-get update && apt-get install -y --no-install-recommends \
      gcc make libc6-dev zlib1g-dev libgomp1 \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY Makefile ./
COPY src ./src
COPY tools ./tools
RUN make server OPENMP=-fopenmp CFLAGS='-O3 -std=c11 -Wall -Wextra -Wpedantic -Werror'
RUN make build/import-ggml OPENMP=-fopenmp CFLAGS='-O3 -std=c11 -Wall -Wextra -Wpedantic -Werror'

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      libgomp1 zlib1g curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /src/build/whisper-turbo-server /usr/local/bin/whisper-turbo-server
COPY --from=build /src/build/import-ggml /usr/local/bin/import-ggml
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENV OMP_NUM_THREADS=8
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
