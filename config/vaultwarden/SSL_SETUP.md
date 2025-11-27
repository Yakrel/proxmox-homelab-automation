# Vaultwarden SSL Certificate Setup Guide

This guide explains how to generate a self-signed CA-enabled SSL certificate for Vaultwarden that is trusted by Android and other devices on the local network (LAN).

## Prerequisites

```bash
cd /datapool/config/vaultwarden/ssl
```

## Certificate Generation

Run the following command block in your terminal. This will:
1.  Create the OpenSSL configuration (`openssl.cnf`) with critical CA and SAN settings.
2.  Generate a certificate valid for 10 years.

> **Note:** Replace `192.168.1.103` with your server's actual IP address if different.

```bash
# 1. Cleanup
rm -f cert.pem key.pem vaultwarden.p12 openssl.cnf ca.crt *.zip *.cer *.pem

# 2. Create Config (Critical: CA:TRUE and IP SAN settings)
cat > openssl.cnf <<INNEREOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = v3_ca

[dn]
C = TR
ST = Istanbul
L = Istanbul
O = Homelab
OU = Vaultwarden
CN = 192.168.1.103

[v3_ca]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:TRUE
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
subjectAltName = @alt_names

[alt_names]
IP.1 = 192.168.1.103
INNEREOF

# 3. Generate Certificate and Key
openssl req -x509 -new -nodes \
  -keyout key.pem \
  -out cert.pem \
  -days 3650 \
  -config openssl.cnf \
  -extensions v3_ca

# 4. Create copy for devices (.crt)
cp cert.pem vaultwarden-ca.crt

# 5. Set Permissions
chmod 644 cert.pem vaultwarden-ca.crt
chmod 600 key.pem

# 6. Restart Vaultwarden
docker restart vaultwarden
```

## Installation on Devices

Transfer the generated **`vaultwarden-ca.crt`** file to your device.

*   **Android:** Settings > Encryption & credentials > Install a certificate > **CA certificate**.
*   **Windows:** Double-click file > Install Certificate > **Trusted Root Certification Authorities**.
*   **iOS:** Install profile > Settings > General > About > Certificate Trust Settings > Enable full trust.
