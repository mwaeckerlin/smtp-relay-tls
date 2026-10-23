#!/usr/bin/env bash
# Image contract: `postfix check` accepts the configuration, the container
# starts the postfix master, the effective configuration carries TLS
# with the certificate of MAILHOST and the OPENDKIM milter, and postconf
# prints no warning about the configuration, neither in the image nor
# after start.sh.
#
# `--network none` keeps every container off the network; `--pull=never`
# tests the local build.
#
# Usage: tests/image-contract.sh IMAGE

set -uo pipefail

# the last argument, so `npm test -- <image>` measures another image
IMAGE="${!#}"
PASS=0
FAIL=0
declare -a FAILED_NAMES
declare -a CONTAINERS

_pass() { PASS=$((PASS + 1)); echo "  PASS  $1"; }
_fail() { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); echo "  FAIL  $1: $2"; }

_cleanup() {
    [[ ${#CONTAINERS[@]} -gt 0 ]] && docker rm -f "${CONTAINERS[@]}" > /dev/null 2>&1
}
trap _cleanup EXIT

# postconf writes every warning about main.cf and master.cf to stderr
_no_warnings() {
    local name="$1" warnings
    warnings=$(docker exec "${CID}" /usr/sbin/postconf -n 2>&1 > /dev/null)
    if [[ -z "${warnings}" ]]; then
        _pass "${name}"
    else
        _fail "${name}" "postconf warns: ${warnings}"
    fi
}

_results() {
    echo ""
    echo "==> Image contract results: ${PASS} passed, ${FAIL} failed"
    if [[ ${FAIL} -gt 0 ]]; then
        echo "==> Failed contracts: ${FAILED_NAMES[*]}"
        exit 1
    fi
}

# sets CID once `postfix status` reports the master running, fails after 60 probes
_start() {
    local name="$1" i
    shift
    CID=$(docker run -d --pull=never --network none "$@" "${IMAGE}")
    CONTAINERS+=("${CID}")
    for i in $(seq 1 60); do
        if docker exec "${CID}" /usr/sbin/postfix status > /dev/null 2>&1; then
            _pass "${name}_started"
            return 0
        fi
        sleep 1
    done
    _fail "${name}_started" "postfix master never came up: $(docker logs "${CID}" 2>&1)"
    return 1
}

# postconf prints the value on stdout and its warnings on stderr
_expect() {
    local name="$1" param="$2" want="$3" got
    got=$(docker exec "${CID}" /usr/sbin/postconf -h "${param}" 2>/dev/null)
    if [[ "${got}" == "${want}" ]]; then
        _pass "${name}"
    else
        _fail "${name}" "${param} = '${got}', expected '${want}' / $(docker exec "${CID}" /usr/sbin/postconf -h "${param}" 2>&1)"
    fi
}

echo "==> Image contract: ${IMAGE}"

if ! docker image inspect "${IMAGE}" > /dev/null 2>&1; then
    _fail "image_exists" "image not built — run 'npm run build' first"
    _results
fi

if OUT=$(timeout 60 docker run --rm --pull=never --network none --entrypoint /usr/sbin/postfix "${IMAGE}" check 2>&1); then
    _pass "postfix_check"
else
    _fail "postfix_check" "${OUT}"
fi

WARNINGS=$(docker run --rm --pull=never --network none --entrypoint /usr/sbin/postconf "${IMAGE}" -n 2>&1 > /dev/null)
if [[ -z "${WARNINGS}" ]]; then
    _pass "image_no_postconf_warnings"
else
    _fail "image_no_postconf_warnings" "postconf warns: ${WARNINGS}"
fi

if _start defaults; then
    _expect default_tls      smtpd_tls_security_level may
    _expect default_cert     smtpd_tls_cert_file /etc/letsencrypt/live/localhost/fullchain.pem
    _expect default_key      smtpd_tls_key_file  /etc/letsencrypt/live/localhost/privkey.pem
    _expect default_milters  smtpd_milters ""
    _no_warnings defaults_no_postconf_warnings
fi

if _start mailhost_opendkim -e MAILHOST=mail.example.com -e OPENDKIM=opendkim; then
    _expect mailhost_cert         smtpd_tls_cert_file /etc/letsencrypt/live/mail.example.com/fullchain.pem
    _expect mailhost_key          smtpd_tls_key_file  /etc/letsencrypt/live/mail.example.com/privkey.pem
    _expect opendkim_default_port smtpd_milters       "inet:opendkim:10026"
    _expect opendkim_non_smtpd    non_smtpd_milters   "inet:opendkim:10026"
    _no_warnings mailhost_opendkim_no_postconf_warnings
fi

if _start opendkim_port -e OPENDKIM=dkim.example.com:8891; then
    _expect opendkim_given_port smtpd_milters "inet:dkim.example.com:8891"
fi

_results
