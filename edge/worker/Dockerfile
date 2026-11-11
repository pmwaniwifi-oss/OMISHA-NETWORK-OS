FROM rust:1.99.1-slim-bookworm AS builder
WORKDIR /src
COPY Cargo.toml Cargo.lock ./
COPY src ./src
RUN cargo build --release --locked --offline

FROM debian:bookworm-slim
RUN useradd --system --uid 10001 omisha
USER 10001:10001
COPY --from=builder /src/target/release/omisha-worker /usr/local/bin/omisha-worker
ENTRYPOINT ["/usr/local/bin/omisha-worker"]

