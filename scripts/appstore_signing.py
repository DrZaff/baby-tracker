#!/usr/bin/env python3
"""Creates everything needed to sign Little Log for TestFlight, using only an
App Store Connect API key, so no Mac or Xcode account is needed.

Each run:
  1. makes sure the app's bundle ID is registered with push notifications on,
  2. creates a fresh Apple Distribution certificate (revoking the oldest ones so
     the account never hits Apple's limit),
  3. creates a matching App Store provisioning profile,
and writes cert.p12 and the profile to OUT_DIR. PROFILE_NAME and PROFILE_UUID
are appended to $GITHUB_ENV for the following workflow steps.

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, BUNDLE_ID, OUT_DIR, P12_PASSWORD.
"""
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID

API = "https://api.appstoreconnect.apple.com/v1"
PROFILE_NAME = "LittleLog CI"
KEEP_CERTIFICATES = 1  # existing certificates kept besides the new one


def env(name):
    value = os.environ.get(name)
    if not value:
        sys.exit(f"Missing environment variable {name}")
    return value


def token():
    with open(env("ASC_KEY_PATH")) as f:
        key = f.read()
    now = int(time.time())
    return jwt.encode(
        {"iss": env("ASC_ISSUER_ID"), "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"},
        key,
        algorithm="ES256",
        headers={"kid": env("ASC_KEY_ID"), "typ": "JWT"},
    )


def call(method, path, body=None, query=None):
    url = API + path
    if query:
        url += "?" + urllib.parse.urlencode(query)
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, method=method)
    request.add_header("Authorization", f"Bearer {token()}")
    request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        raise SystemExit(f"App Store Connect API {method} {path} failed ({error.code}): {detail}")


def ensure_bundle_id(identifier):
    found = call("GET", "/bundleIds", query={"filter[identifier]": identifier, "limit": 200})
    match = next((b for b in found["data"] if b["attributes"]["identifier"] == identifier), None)
    if match:
        bundle_id = match["id"]
        print(f"Bundle ID {identifier} is registered")
    else:
        created = call("POST", "/bundleIds", {
            "data": {
                "type": "bundleIds",
                "attributes": {"identifier": identifier, "name": "Little Log", "platform": "IOS"},
            }
        })
        bundle_id = created["data"]["id"]
        print(f"Registered bundle ID {identifier}")

    capabilities = call("GET", f"/bundleIds/{bundle_id}/bundleIdCapabilities")
    if not any(c["attributes"]["capabilityType"] == "PUSH_NOTIFICATIONS" for c in capabilities["data"]):
        call("POST", "/bundleIdCapabilities", {
            "data": {
                "type": "bundleIdCapabilities",
                "attributes": {"capabilityType": "PUSH_NOTIFICATIONS"},
                "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bundle_id}}},
            }
        })
        print("Turned on push notifications for the bundle ID")
    return bundle_id


def create_certificate(out_dir, password):
    existing = call("GET", "/certificates", query={"filter[certificateType]": "DISTRIBUTION", "limit": 200})["data"]
    existing.sort(key=lambda c: c["attributes"].get("expirationDate", ""))
    while len(existing) > KEEP_CERTIFICATES:
        old = existing.pop(0)
        call("DELETE", f"/certificates/{old['id']}")
        print(f"Revoked an older distribution certificate ({old['attributes'].get('name')})")

    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    csr = (
        x509.CertificateSigningRequestBuilder()
        .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Little Log CI")]))
        .sign(key, hashes.SHA256())
    )
    csr_pem = csr.public_bytes(serialization.Encoding.PEM).decode()
    created = call("POST", "/certificates", {
        "data": {
            "type": "certificates",
            "attributes": {"certificateType": "DISTRIBUTION", "csrContent": csr_pem},
        }
    })
    cert = x509.load_der_x509_certificate(base64.b64decode(created["data"]["attributes"]["certificateContent"]))

    # macOS `security import` needs the older 3DES/SHA1 PKCS#12 format.
    encryption = (
        serialization.PrivateFormat.PKCS12.encryption_builder()
        .kdf_rounds(50000)
        .key_cert_algorithm(pkcs12.PBES.PBESv1SHA1And3KeyTripleDESCBC)
        .hmac_hash(hashes.SHA1())
        .build(password.encode())
    )
    p12 = pkcs12.serialize_key_and_certificates(b"Little Log CI", key, cert, None, encryption)
    with open(os.path.join(out_dir, "cert.p12"), "wb") as f:
        f.write(p12)
    print("Created a new Apple Distribution certificate")
    return created["data"]["id"]


def create_profile(bundle_id, certificate_id, out_dir):
    old = call("GET", "/profiles", query={"filter[name]": PROFILE_NAME, "limit": 200})["data"]
    for profile in old:
        call("DELETE", f"/profiles/{profile['id']}")
    created = call("POST", "/profiles", {
        "data": {
            "type": "profiles",
            "attributes": {"name": PROFILE_NAME, "profileType": "IOS_APP_STORE"},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle_id}},
                "certificates": {"data": [{"type": "certificates", "id": certificate_id}]},
            },
        }
    })
    attributes = created["data"]["attributes"]
    with open(os.path.join(out_dir, "profile.mobileprovision"), "wb") as f:
        f.write(base64.b64decode(attributes["profileContent"]))
    print(f"Created provisioning profile {PROFILE_NAME}")
    return attributes["uuid"]


def main():
    out_dir = env("OUT_DIR")
    os.makedirs(out_dir, exist_ok=True)
    bundle_id = ensure_bundle_id(env("BUNDLE_ID"))
    certificate_id = create_certificate(out_dir, env("P12_PASSWORD"))
    uuid = create_profile(bundle_id, certificate_id, out_dir)
    github_env = os.environ.get("GITHUB_ENV")
    if github_env:
        with open(github_env, "a") as f:
            f.write(f"PROFILE_NAME={PROFILE_NAME}\nPROFILE_UUID={uuid}\n")


if __name__ == "__main__":
    main()
