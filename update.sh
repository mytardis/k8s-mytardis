#!/bin/sh

# Build
docker build . --squash -t mytardis/k8s-mytardis:latest --target=production

# Push
docker push mytardis/k8s-mytardis:latest
