#!/usr/bin/env python3
"""Creates everything needed to sign Little Log for TestFlight, using only an
App Store Connect API key, so no Mac or Xcode account is needed.

Each run:
  1. makes sure the app's bundle ID (with push notifications on) and the widget
     extension's bundle ID (BUNDLE_ID + ".widgets") are registered,
  2. creates a fresh Apple Distribution certificate (revoking the oldest ones so
     the account never hits Apple's limit),
  3. creates matching App Store provisioning profiles for both,
and writes cert.p12, profile.mobileprovision and widget.mobileprovision to OUT_DIR.
PROFILE_NAME, PROFILE_UUID, WIDGET_PROFILE_NAME and WIDGET_PROFILE_UUID are
appended to $GITHUB_ENV for the following workflow steps.

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
WIDGET_PROFILE_NAME = "LittleLog Widgets CI"
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


def ensure_bundle_id(identifier, name, push):
    found = call("GET", "/bundleIds", query={"filter[identifier]": identifier, "limit": 200})
    match = next((b for b in found["data"] if b["attributes"]["identifier"] == identifier), None)
    if match:
        bundle_id = match["id"]
        print(f"Bundle ID {identifier} is registered")
    else:
        created = call("POST", "/bundleIds", {
            "data": {
                "type": "bundleIds",
                "attributes": {"identifier": identifier, "name": name, "platform": "IOS"},
            }
        })
        bundle_id = created["data"]["id"]
        print(f"Registered bundle ID {identifier}")

    if not push:
        return bundle_id
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


def create_profile(name, bundle_id, certificate_id, path):
    old = call("GET", "/profiles", query={"filter[name]": name, "limit": 200})["data"]
    for profile in old:
        call("DELETE", f"/profiles/{profile['id']}")
    created = call("POST", "/profiles", {
        "data": {
            "type": "profiles",
            "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle_id}},
                "certificates": {"data": [{"type": "certificates", "id": certificate_id}]},
            },
        }
    })
    attributes = created["data"]["attributes"]
    with open(path, "wb") as f:
        f.write(base64.b64decode(attributes["profileContent"]))
    print(f"Created provisioning profile {name}")
    return attributes["uuid"]


def main():
    out_dir = env("OUT_DIR")
    os.makedirs(out_dir, exist_ok=True)
    app_bundle = env("BUNDLE_ID")
    app_id = ensure_bundle_id(app_bundle, "Little Log", push=True)
    widget_id = ensure_bundle_id(app_bundle + ".widgets", "Little Log Widgets", push=False)
    certificate_id = create_certificate(out_dir, env("P12_PASSWORD"))
    uuid = create_profile(PROFILE_NAME, app_id, certificate_id, os.path.join(out_dir, "profile.mobileprovision"))
    widget_uuid = create_profile(WIDGET_PROFILE_NAME, widget_id, certificate_id, os.path.join(out_dir, "widget.mobileprovision"))
    github_env = os.environ.get("GITHUB_ENV")
    if github_env:
        with open(github_env, "a") as f:
            f.write(f"PROFILE_NAME={PROFILE_NAME}\nPROFILE_UUID={uuid}\n")
            f.write(f"WIDGET_PROFILE_NAME={WIDGET_PROFILE_NAME}\nWIDGET_PROFILE_UUID={widget_uuid}\n")


if __name__ == "__main__":
    main()
