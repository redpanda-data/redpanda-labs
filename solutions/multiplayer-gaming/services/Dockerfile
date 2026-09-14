# One image recipe for the four Go programs. docker-compose.yml passes
# SERVICE=simulator|leaderboard|dashboard|achievements as a build argument.
FROM golang:1.26-alpine AS build
ARG SERVICE
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/service ./${SERVICE}

FROM alpine:3.22
RUN apk add --no-cache ca-certificates
COPY --from=build /out/service /service
USER 65532:65532
ENTRYPOINT ["/service"]
