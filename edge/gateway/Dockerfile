FROM golang:1.27.3-alpine AS builder
WORKDIR /src
COPY go.mod main.go ./
RUN CGO_ENABLED=0 go build -trimpath -o /gateway .

FROM alpine:3.24
RUN adduser -D -u 10001 omisha
USER 10001:10001
COPY --from=builder /gateway /gateway
EXPOSE 8080
ENTRYPOINT ["/gateway"]

