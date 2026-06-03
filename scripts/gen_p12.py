#!/usr/bin/env python3
import sys
import datetime
from cryptography import x509
from cryptography.x509.oid import NameOID
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs12

p12_path = sys.argv[1]
team_id = sys.argv[2]

key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
name = x509.Name([
    x509.NameAttribute(NameOID.COMMON_NAME, f"Apple Distribution: LuxGram ({team_id})"),
    x509.NameAttribute(NameOID.ORGANIZATIONAL_UNIT_NAME, "SELFSIGNED"),
    x509.NameAttribute(NameOID.COUNTRY_NAME, "US"),
])
now = datetime.datetime.now(datetime.timezone.utc)
cert = (
    x509.CertificateBuilder()
    .subject_name(name)
    .issuer_name(name)
    .public_key(key.public_key())
    .serial_number(x509.random_serial_number())
    .not_valid_before(now)
    .not_valid_after(now + datetime.timedelta(days=3650))
    .add_extension(x509.BasicConstraints(ca=True, path_length=None), critical=True)
    .sign(key, hashes.SHA256())
)

p12_data = pkcs12.serialize_key_and_certificates(
    name=b"LuxGram",
    key=key,
    cert=cert,
    cas=None,
    encryption_algorithm=serialization.BestAvailableEncryption(b""),
)
open(p12_path, "wb").write(p12_data)
open("/tmp/lux.crt", "wb").write(cert.public_bytes(serialization.Encoding.PEM))
print(f"Generated p12: {len(p12_data)} bytes")
