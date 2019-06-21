#!/usr/bin/env bash

NUM_BITS=2048

yell() { echo "$0: $*" >&2; }
die() { yell "$*"; exit 111; }
try() { echo "$ $@" 1>&2; "$@" || die "cannot $*"; }

info() {
  echo -e "\033[1;34m[INFO]\033[0m ${1}"
}

warn() {
  echo -e "\033[1;33m[WARN]\033[0m ${1}"
}

error() {
  echo -e "\033[1;31m[ERROR]\033[0m ${1}"
}

init() {
  export PKI_ROOT="${PKI_ROOT:-"/etc/ssl/pki"}"

  try rm -rf $PKI_ROOT/*
  try mkdir -p $PKI_ROOT
}

main() {
  # no arguments are passed so assume user wants to run the gocd server
  # we prepend "${SERVER_WORK_DIR}/bin/go-server console" to the argument list
  if [[ $# -eq 0 ]] ; then
    set -- "nginx" "-g" "daemon off;"
  else
    try exec "$@"
  fi

  init

  # root webserver CA cert
  try easypki create --filename webserver-root --ca "webserver-root-ca.example.com"
  info "Created the following webserver root CA certificate"
  try openssl x509 -text -in ${PKI_ROOT}/webserver-root/certs/webserver-root.crt

  # intermediate webserver CA cert
  info "Creating a webserver intermediate CA"
  try easypki create --ca-name webserver-root --filename webserver-intermediate --intermediate "Acme Inc. - Webserver Internal CA"
  try openssl x509 -text -in ${PKI_ROOT}/webserver-intermediate/certs/webserver-intermediate.crt

  # some wildcard webserver cert
  try easypki create --ca-name webserver-intermediate --dns "*.internal.example.com" "*.internal.example.com"
  try openssl x509 -text -in ${PKI_ROOT}/webserver-intermediate/certs/wildcard.internal.example.com.crt


  # root ca for signing client certs
  try easypki create --filename client-root --ca "Acme Inc. Private Key Certificate Authority"
  info "Created the following client cert root CA certificate"
  try openssl x509 -text -in ${PKI_ROOT}/client-root/certs/client-root.crt

  # intermediate CA for signing client certs
  try easypki create --ca-name client-root --filename client-intermediate --intermediate "Acme Inc. - Client Internal CA"
  try openssl x509 -text -in ${PKI_ROOT}/client-intermediate/certs/client-intermediate.crt

  # client cert for some agent
  try easypki create --ca-name client-intermediate --client --email some-agent@example.com some-agent@example.com
  try openssl x509 -text -in ${PKI_ROOT}/client-intermediate/certs/some-agent@example.com.crt


  # concatenate cert chains for use by nginx

  try rm -rf /etc/nginx/ssl/
  try mkdir -p /etc/nginx/ssl/

  # for the simple self signed cert
  try cp ${PKI_ROOT}/webserver-root/certs/webserver-root.crt /etc/nginx/ssl/ssl-self-signed.crt
  try cp ${PKI_ROOT}/webserver-root/keys/webserver-root.key /etc/nginx/ssl/ssl-self-signed.key

  # cert+key for webserver wildcard certificate
  try bash -c "cat ${PKI_ROOT}/webserver-intermediate/certs/wildcard.internal.example.com.crt \
          ${PKI_ROOT}/webserver-intermediate/certs/webserver-intermediate.crt \
          ${PKI_ROOT}/webserver-root/certs/webserver-root.crt > \
          /etc/nginx/ssl/ssl-cert-chain.internal.example.com.crt"

  try cp ${PKI_ROOT}/webserver-intermediate/keys/wildcard.internal.example.com.key /etc/nginx/ssl/ssl-cert-chain.internal.example.com.key

  # cert for client cert verification
  try cp ${PKI_ROOT}/client-root/certs/client-root.crt /etc/nginx/ssl/client-cert-root.crt
  try cp ${PKI_ROOT}/client-intermediate/certs/client-intermediate.crt /etc/nginx/ssl/client-cert-intermediate.crt
  try bash -c "cat ${PKI_ROOT}/client-intermediate/certs/client-intermediate.crt \
                   ${PKI_ROOT}/client-root/certs/client-root.crt > \
                   /etc/nginx/ssl/client-cert.crt.chain"

  try cp -fv /nginx-conf/* /etc/nginx/conf.d/

  try sed -i \
              -e 's!error_log.*!error_log stderr debug;!g' \
              -e 's!$remote_addr - !$remote_addr - $ssl_client_s_dn - !g' \
              /etc/nginx/nginx.conf
  try exec "$@"
}

main "$@"
