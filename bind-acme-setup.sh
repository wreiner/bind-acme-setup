#!/bin/bash
#
# Create keys to use with Let's Encrypts certbot.
#
# DO NOT USE PERIODICALLY AS YOU'D NEED TO CHANGE THE KEYS IN ALL UPDATE LOCATIONS!
#
# Sources:
#   https://certbot-dns-rfc2136.readthedocs.io/en/stable/
#   https://john.daltons.info/home_server_documentation/lets_encrypt.html
#   https://blog.svedr.in/posts/letsencrypt-dns-verification-using-a-local-bind-instance/
#

usage()
{
    echo "USAGE: $0 <domain> <primary-dns-server>"
}

DOMAIN=$1
if [ -z "${DOMAIN}" ];
then
    echo "no DOMAIN provided, exiting."
    usage
    exit 1
fi

PRIMARY_NS=$2
if [ -z "${PRIMARY_NS}" ];
then
    echo "no PRIMARY NAMESERVER provided, exiting."
    usage
    exit 1
fi

CERTBOT_KEY_NAME="${DOMAIN}-certbot-key."
CERTBOT_KEY_FILENAME="/etc/bind/letsencrypt_keys/${DOMAIN}.certbot.key"
CERTBOT_ZONE="_acme-challenge.${DOMAIN}."
ZONE_CONFIG_DIRECTORY="/var/lib/bind"
ZONE_CONFIG_FILENAME="${ZONE_CONFIG_DIRECTORY}/_acme-challenge.${DOMAIN}.conf"
ZONE_DATA_FILENAME="${ZONE_CONFIG_DIRECTORY}/_acme-challenge.${DOMAIN}.zone"

echo "####"
echo "You provided:"
echo "  DOMAIN:                 ${DOMAIN}"
echo "  PRIMARY_NS:             ${PRIMARY_NS}"
echo
echo "Will generate the following config:"
echo "  CERTBOT_ZONE:           ${CERTBOT_ZONE}"
echo "  CERTBOT_KEY_NAME:       ${CERTBOT_KEY_NAME}"
echo "  CERTBOT_KEY_FILENAME:   ${CERTBOT_KEY_FILENAME}"
echo
echo "  ZONE_CONFIG_DIRECTORY:  ${ZONE_CONFIG_DIRECTORY}"
echo "  ZONE_CONFIG_FILENAME:   ${ZONE_CONFIG_FILENAME}"
echo "  ZONE_DATA_FILENAME:     ${ZONE_DATA_FILENAME}"
echo "####"
echo

# --- TSIG KEY

echo "creating TSIG key .."
rndc-confgen -a -A hmac-sha512 -k "${DOMAIN}-certbot-key." -c "/etc/bind/letsencrypt_keys/${DOMAIN}.certbot.key"
if [ $? -ne 0 ];
then
    echo "error creating TSIG key for DOMAIN ${DOMAIN}, exiting."
    exit 1
fi

chown -R bind: /etc/bind/letsencrypt_keys

# --- ZONE CONFIG

echo "creating zone conf in ${ZONE_CONFIG_FILENAME} .."

mkdir -p "${ZONE_CONFIG_DIRECTORY}"

cat <<EOF > "${ZONE_CONFIG_FILENAME}"
include "${CERTBOT_KEY_FILENAME}";

zone "${CERTBOT_ZONE}" {
    type master;
    file "${ZONE_DATA_FILENAME}";

    allow-query { any; };

    update-policy {
        grant ${CERTBOT_KEY_NAME} name ${CERTBOT_ZONE} txt;
    };
};
EOF

# --- ZONE DATA

echo "creating zone data in ${ZONE_DATA_FILENAME} .."

CURRENT_DATE=$(date "+%Y%m%d")

cat <<EOF > "${ZONE_DATA_FILENAME}"
\$ORIGIN .
\$TTL 600	; 10 minutes
_acme-challenge.${DOMAIN} IN SOA ${PRIMARY_NS}. domainmaster.${DOMAIN}. (
				${CURRENT_DATE}01 ; serial
				10800      ; refresh (3 hours)
				3600       ; retry (1 hour)
				604800     ; expire (1 week)
				86400      ; minimum (1 day)
				)
			NS	${PRIMARY_NS}.
			TXT	"127.0.0.1"
EOF

chown root:bind "${ZONE_DATA_FILENAME}"
chmod 664 "${ZONE_DATA_FILENAME}"

# --- ZONE DELEGATION

grep -q "_acme-challenge" "${ZONE_CONFIG_DIRECTORY}/${DOMAIN}.zone" >> /dev/null
if [ $? -eq 1 ];
then
    echo "adding zone delegation to ${ZONE_CONFIG_DIRECTORY}/${DOMAIN}.zone .."

    cp "${ZONE_CONFIG_DIRECTORY}/${DOMAIN}.zone" "${ZONE_CONFIG_DIRECTORY}/${DOMAIN}.zone.${CURRENT_DATE}"

    echo >> "${ZONE_CONFIG_DIRECTORY}/${DOMAIN}.zone"
    echo "; automatically added by $0 script">> "${ZONE_CONFIG_DIRECTORY}/${DOMAIN}.zone"
    echo "_acme-challenge IN NS ${PRIMARY_NS}." >> "${ZONE_CONFIG_DIRECTORY}/${DOMAIN}.zone"
fi

grep -q "${ZONE_CONFIG_FILENAME}" /etc/bind/named.conf.local >> /dev/null
if [ $? -eq 1 ];
then
    echo "adding ${CERTBOT_ZONE} config to bind .."

    cp "/etc/bind/named.conf.local" "/etc/bind/named.conf.local.${CURRENT_DATE}"

    echo >> /etc/bind/named.conf.local
    echo "// automatically added by $0 script">> /etc/bind/named.conf.local
    echo "include \"${ZONE_CONFIG_FILENAME}\";" >> /etc/bind/named.conf.local
fi
