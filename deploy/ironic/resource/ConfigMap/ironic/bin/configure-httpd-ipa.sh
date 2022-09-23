#!/usr/bin/bash

IRONIC_CERT_FILE=${IRONIC_CERT_FILE:-/certs/ironic/tls.crt}
export HTTP_PORT=${HTTP_PORT:-"80"}

# Whether to enable fast_track provisioning or not
IRONIC_FAST_TRACK=${IRONIC_FAST_TRACK:-true}

wait_for_interface_or_ip

mkdir -pm 0777 /shared/html

if [ -f "$IRONIC_CERT_FILE" ]; then
    IRONIC_BASE_URL="https://${IRONIC_URL_HOST}"
else
    IRONIC_BASE_URL="http://${IRONIC_URL_HOST}"
fi

if [[ $IRONIC_FAST_TRACK == true ]]; then
    INSPECTOR_EXTRA_ARGS=" ipa-api-url=${IRONIC_API_BASE_URL} ipa-inspection-callback-url=${IRONIC_INSPECTOR_BASE_URL}/v1/continue"
else
    INSPECTOR_EXTRA_ARGS=" ipa-inspection-callback-url=${IRONIC_INSPECTOR_BASE_URL}/v1/continue"
fi

# Copy files to shared mount
render_j2_config /tmp/inspector.ipxe.j2 /shared/html/inspector.ipxe
cp /tmp/uefi_esp.img /shared/html/

sed -i 's/^Listen .*$/Listen [::]:'"$HTTP_PORT"'/' /etc/httpd/conf/httpd.conf
sed -i -e 's|\(^[[:space:]]*\)\(DocumentRoot\)\(.*\)|\1\2 "/shared/html"|' \
    -e 's|<Directory "/var/www/html">|<Directory "/shared/html">|' \
    -e 's|<Directory "/var/www">|<Directory "/shared">|' /etc/httpd/conf/httpd.conf

# Log to std out/err
sed -i -e 's%^ \+CustomLog.*%    CustomLog /dev/stderr combined%g' /etc/httpd/conf/httpd.conf
sed -i -e 's%^ErrorLog.*%ErrorLog /dev/stderr%g' /etc/httpd/conf/httpd.conf
