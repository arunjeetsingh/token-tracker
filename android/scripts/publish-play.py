#!/usr/bin/env python3
"""
publish-play.py — upload a signed AAB to a Google Play track via the
play-publisher service account. Mirrors the CI r0adkll/upload-google-play step.

Usage:
  publish-play.py <aab_path> <track> <version_name> [--status completed|draft]

Env/paths:
  SA JSON: ~/.openclaw/workspace/secrets/play-publisher-sa.json
"""
import argparse
import os
import sys
from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload

PACKAGE = "studio.maximumimpact.tokencounter"
SA_PATH = os.path.expanduser("~/.openclaw/workspace/secrets/play-publisher-sa.json")
SCOPES = ["https://www.googleapis.com/auth/androidpublisher"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("aab")
    ap.add_argument("track")
    ap.add_argument("version_name")
    ap.add_argument("--status", default="completed")
    ap.add_argument("--changelog", default="TokenCounter 1.0.0 — first Android release.")
    args = ap.parse_args()

    creds = service_account.Credentials.from_service_account_file(SA_PATH, scopes=SCOPES)
    svc = build("androidpublisher", "v3", credentials=creds, cache_discovery=False)

    print(f"Creating edit for {PACKAGE} ...")
    edit = svc.edits().insert(packageName=PACKAGE, body={}).execute()
    edit_id = edit["id"]
    print("  edit id:", edit_id)

    print(f"Uploading AAB: {args.aab}")
    media = MediaFileUpload(args.aab, mimetype="application/octet-stream", resumable=True)
    up = svc.edits().bundles().upload(
        packageName=PACKAGE, editId=edit_id, media_body=media
    ).execute()
    vc = up["versionCode"]
    print("  uploaded versionCode:", vc)

    print(f"Assigning versionCode {vc} to track '{args.track}' (status={args.status})")
    svc.edits().tracks().update(
        packageName=PACKAGE,
        editId=edit_id,
        track=args.track,
        body={
            "track": args.track,
            "releases": [{
                "name": args.version_name,
                "versionCodes": [str(vc)],
                "status": args.status,
                "releaseNotes": [{"language": "en-US", "text": args.changelog}],
            }],
        },
    ).execute()

    print("Committing edit ...")
    committed = svc.edits().commit(packageName=PACKAGE, editId=edit_id).execute()
    print("  committed edit:", committed.get("id"))
    print(f"\nDONE: {args.version_name} (versionCode {vc}) -> {args.track} [{args.status}]")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print("PUBLISH FAILED:", repr(e), file=sys.stderr)
        # surface API error body if present
        body = getattr(getattr(e, "resp", None), "reason", None)
        content = getattr(e, "content", None)
        if content:
            print(content.decode() if isinstance(content, bytes) else content, file=sys.stderr)
        sys.exit(1)
