# =============================================================================
# Stage 1: Build
# =============================================================================
FROM golang:alpine AS builder

WORKDIR /build

COPY go.mod go.sum* ./
COPY main.go ./

ARG VERSION=dev
RUN CGO_ENABLED=0 go build -ldflags="-s -w -X main.version=${VERSION}" -o kubectl-aliases .

# =============================================================================
# Stage 2: Minimal runtime
# =============================================================================
FROM alpine:latest

RUN apk add --no-cache ca-certificates && \
    adduser -D -h /home/user -u 1000 user

COPY --from=builder --chown=user:user /build/kubectl-aliases /usr/local/bin/kubectl-aliases

USER user
WORKDIR /home/user

ENTRYPOINT ["kubectl-aliases"]
CMD ["--help"]
