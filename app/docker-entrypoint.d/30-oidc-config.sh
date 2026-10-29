#!/bin/sh
set -eu
cat > /usr/share/nginx/html/oidc-config.js <<EOF
window.ESMA_OIDC_CONFIG = { url: "${OIDC_URL}", realm: "${OIDC_REALM:-esma}", clientId: "${OIDC_CLIENT_ID:-esma-web}" };
EOF
