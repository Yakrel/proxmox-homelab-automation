# syntax=docker/dockerfile:1

FROM garethgeorge/backrest:latest

# Install rclone for cloud backup sync
# Using Alpine package manager since backrest image is based on Alpine
RUN apk add --no-cache rclone

# Metadata
LABEL maintainer="Yakrel"
LABEL description="Backrest with rclone for cloud backup sync"
