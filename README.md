# Bind Acme Setup

To use the Let's Encrypt DNS challenge a TXT record in your zone needs to be set upon certificate generation.
This is especially interesting for wildcard certificates.

The provided script adds a _acme-challenge.your.domain zone and configures it to be dynamically updateable with Let's Encrypt certbot (for examle with [certbot-dns-rfc2136](https://certbot-dns-rfc2136.readthedocs.io/en/stable/)) through the use of TSIG keys.

Also provided is an example primary zone setup which can be used with the script.

## Usage

* Setup your zone as shown in the example-primary zone
* To run the script you need to provide two parameters:
    * domain: the domain for which dynamic updates should be setup
    * primary dns server: the primary name server of the aformentioned domain; in a views setup the domain server Let's Encrypt servers can reach
* Run the script from a bash shell:
    ```
    $ sudo chmod 755 /usr/sbin/bind-acme-setup.sh
    $ sudo /usr/sbin/bind-acme-setup.sh example.com ns1.example.com
    ```
* Restart bind
    ```
    $ sudo systemctl restart bind9
    ```
* Read the TSIG key for certbot configuration from _/etc/bind/letsencrypt_keys/example.com.certbot.key_ (the value in the secret field):
    ```
    $ sudo cat /etc/bind/letsencrypt_keys/example.com.certbot.key
    key "example.com-certbot-key." {
        algorithm hmac-sha512;
        secret "VaSDI8jrl1TQ/eIDhct47/s7D8XS6hOb6iWtLggMH1AP99WyXvjv6Jc4Shr5IVtwbWQXJHY0CV+e4joLdGcylw==";
    };
    ```
* Certbot configuration example:
    ```
    $ sudo cat /etc/certbot/dns-rfc2136-credentials.ini
    # Target DNS server (IPv4 or IPv6 address, not a hostname)
    dns_rfc2136_server = 192.0.2.1
    # Target DNS port
    dns_rfc2136_port = 53
    # TSIG key name
    dns_rfc2136_name = example.com.certbot.key.
    # TSIG key secret
    dns_rfc2136_secret = VaSDI8jrl1TQ/eIDhct47/s7D8XS6hOb6iWtLggMH1AP99WyXvjv6Jc4Shr5IVtwbWQXJHY0CV+e4joLdGcylw==
    # TSIG key algorithm
    dns_rfc2136_algorithm = HMAC-SHA512
    ```

## Manually test domain update

* To add a TXT record:

```
debian:/var/lib/bind# nsupdate -k /etc/bind/letsencrypt_keys/example.com.certbot.key 
> server 127.0.0.1
> update add _acme-challenge.example.com 3000 TXT 202201081844
> send
> quit
```

* Check with dig

```
$ dig @127.0.0.1 _acme-challenge.example.com txt
...
;; ANSWER SECTION:
_acme-challenge.example.com. 3000 IN	TXT	"202201081844"
```

To delete the TXT record:

```
debian:/var/lib/bind# nsupdate -k /etc/bind/letsencrypt_keys/example.com.certbot.key 
> server 127.0.0.1
> update delete _acme-challenge.example.com 3000 TXT 202201081844
> send
> quit
```

## Test obtaining a certificate with certbot

Let's Encrypt offers a specific Docker image which can be used to obtain certficates using the DNS challenge with bind - [certbot/dns-rfc2136](https://hub.docker.com/r/certbot/dns-rfc2136/).

To test obtaining a certificate the staging servers of Let's Encrypt can be used:

* Create the config
    ```
    $ cat <<EOF > /var/lib/docker/volumes/certbottest/etc/example.com-rfc2136.ini
    # Target DNS server (IPv4 or IPv6 address, not a hostname)
    dns_rfc2136_server = 1.2.3.4
    # Target DNS port
    dns_rfc2136_port = 53
    # TSIG key name (created above)
    dns_rfc2136_name = example.com-certbot-key.
    # TSIG key secret (created above, secret field of the .key file)
    dns_rfc2136_secret = yBFtfmuWadcS2pEntWKaOfcMWIXGoOWOObusidSfn5quOp/MFDnohuviIydYltZHje/WJghYgc2imk4Y6STmw==
    # TSIG key algorithm
    dns_rfc2136_algorithm = HMAC-SHA512
    EOF

    $ sudo chmod 600 /var/lib/docker/volumes/certbottest/etc/example.com-rfc2136.ini
    ```
* Obtain a staging certificate
    ```
    $ docker run -it --rm --name testcertbot \
        -v "/var/lib/docker/volumes/certbottest/etc:/etc/letsencrypt" \
        -v "/var/lib/docker/volumes/certbottest/data:/var/lib/letsencrypt" \
        certbot/dns-rfc2136:latest \
        certonly \
        -n \
        --email hostmaster\@example.com \
        --agree-tos \
        --no-eff-email \
        --test-cert \
        --debug \
        --dns-rfc2136 \
        --dns-rfc2136-credentials /etc/letsencrypt/example.com-rfc2136.ini \
        --dns-rfc2136-propagation-seconds 30 \
        -d "*.example.com"
    ```
* Check the obtained certificate (look for "Issuer: C = US, O = (STAGING) Let's Encrypt, CN = (STAGING) Artificial Apricot R3")
    ```
    $ openssl x509 -in /var/lib/docker/volumes/certbottest/etc/archive/example.com/fullchain1.pem -text -noout
    ```

## Use the python script to update the zone file

Communication between the update client (certbot, nsupdate, ..) and the DNS server is unencrypted.
It is therefore a security hazard to communicate the challange as attackers could gain access to the secret to update the token
and start issuing malicious certificates.

The provided script can be run on the DNS server system itself so the network traffic is not leaving the host.

To run the script create a config file with the zone configuration - an example file is included in the repository.
Provide the zone to update and the challenge from certbot as command line parameters:

```
python3 update-txt-record.py -z example.com -c the_challange_string [-C update-txt-record.json]
```

The script expects the config file to be at _/etc/update-txt-records.json_.
If the location is different provide the config file with the -C command line option.

## Sync dynamic changes to the zone file

Dynamic changes are stored in _.jnl_-files.

On a restart of bind the zone is updated with the contents of the _.jnl_-file but the changes are not written back to the zone file.

To sync the changes to the zone file run:

```
rndc sync -clean
```
