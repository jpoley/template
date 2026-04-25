#!/bin/sh
# Install the enterprise CA bundle from /tmp/enterprise-ca/enterprise-ca.crt
# into the system trust store of the current Docker image.
#
# No-op when the file is missing or empty — i.e. when this image is being
# built outside of an enterprise MITM environment. That is the *expected*
# default; the script only does work when a real cert is present.
#
# Supports both Debian/Ubuntu (update-ca-certificates) and Alpine
# (apk add ca-certificates && update-ca-certificates). Other distros: extend
# this script — every Dockerfile invokes it the same way.
set -eu

CERT_SRC="/tmp/enterprise-ca/enterprise-ca.crt"

if [ ! -s "$CERT_SRC" ]; then
  echo "[ca] no enterprise CA present — skipping" >&2
  exit 0
fi

echo "[ca] installing enterprise CA into system trust store" >&2

if [ -f /etc/debian_version ]; then
  # Debian/Ubuntu: drops in /usr/local/share/ca-certificates/ are auto-discovered.
  if ! command -v update-ca-certificates >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -y --no-install-recommends ca-certificates
    rm -rf /var/lib/apt/lists/*
  fi
  install -m 0644 "$CERT_SRC" /usr/local/share/ca-certificates/enterprise-ca.crt
  update-ca-certificates >/dev/null
elif [ -f /etc/alpine-release ]; then
  # Alpine's update-ca-certificates reads from /usr/share/ca-certificates/ and
  # only processes filenames listed in /etc/ca-certificates.conf — it does
  # NOT auto-discover /usr/local/share/ca-certificates/ the way Debian does,
  # so both the copy AND the conf entry are required.
  if ! command -v update-ca-certificates >/dev/null 2>&1; then
    apk add --no-cache ca-certificates >/dev/null
  fi
  install -m 0644 "$CERT_SRC" /usr/share/ca-certificates/enterprise-ca.crt
  if ! grep -qx 'enterprise-ca.crt' /etc/ca-certificates.conf 2>/dev/null; then
    echo 'enterprise-ca.crt' >>/etc/ca-certificates.conf
  fi
  # Also drop a copy in /usr/local/share for tools that read that path directly.
  install -m 0644 "$CERT_SRC" /usr/local/share/ca-certificates/enterprise-ca.crt
  update-ca-certificates >/dev/null 2>&1
else
  echo "[ca] unknown distro — extend certs/install-ca-in-image.sh" >&2
  exit 1
fi

# Convenience env var honoured by Node, Bun, and many other tools that bundle
# their own CA store and want a single extra PEM appended.
echo "[ca] installed at /usr/local/share/ca-certificates/enterprise-ca.crt" >&2
