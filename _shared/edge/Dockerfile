FROM golang:1.23-alpine AS build
WORKDIR /src
COPY go.mod ./
COPY main.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/edge .

FROM alpine:3.20
RUN apk add --no-cache ca-certificates && adduser -D -u 10001 edge
USER edge
COPY --from=build /out/edge /usr/local/bin/edge
EXPOSE 8080 8443
ENTRYPOINT ["/usr/local/bin/edge"]
