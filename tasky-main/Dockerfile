# STEP 1: Build Stage — Using outdated Golang (1+ year old requirement)
FROM golang:1.19 AS build

WORKDIR /go/src/tasky
COPY . .
RUN go mod download
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /go/src/tasky/tasky

# STEP 2: Release Stage — Using outdated Alpine (1+ year old requirement)
FROM alpine:3.17.0 AS release

# MANDATORY: Candidate identity file
RUN echo "Rahul Kuppachhi" > /wizexercise.txt

WORKDIR /app
COPY --from=build /go/src/tasky/tasky .
COPY --from=build /go/src/tasky/assets ./assets

EXPOSE 8080
ENTRYPOINT ["/app/tasky"]
