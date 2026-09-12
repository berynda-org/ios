"""Validate and upload an IPA, including altool failures that return exit code zero."""

import os
from pathlib import Path
import re
import subprocess
import sys


_FAILURE = re.compile(r"\bERROR:|\b(?:VERIFY|UPLOAD) FAILED\b|Failed to (?:validate|upload) package", re.IGNORECASE)
_SUCCESS = {
    "validate": re.compile(r"\b(?:VERIFY|VALIDATION) (?:SUCCEEDED|SUCCESSFUL)\b|No errors validating|Successfully validated", re.IGNORECASE),
    "upload": re.compile(r"\bUPLOAD (?:SUCCEEDED|SUCCESSFUL)\b|No errors uploading|Successfully uploaded", re.IGNORECASE),
}


def run_altool(operation, ipa_path, key_id, issuer_id):
    result = subprocess.run(
        ["xcrun", "altool", f"--{operation}-app", "--file", str(ipa_path),
         "--type", "ios", "--apiKey", key_id, "--apiIssuer", issuer_id],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, check=False,
    )
    output = result.stdout or ""
    print(output, end="" if output.endswith("\n") else "\n", flush=True)
    if result.returncode != 0 or _FAILURE.search(output):
        raise RuntimeError(f"Apple {operation} failed; see the uploader output above.")
    if not _SUCCESS[operation].search(output):
        raise RuntimeError(f"Apple {operation} did not confirm success; refusing to continue.")


def validate_and_upload(ipa_path, key_id, issuer_id):
    run_altool("validate", ipa_path, key_id, issuer_id)
    run_altool("upload", ipa_path, key_id, issuer_id)


def main():
    if len(sys.argv) != 2 or not Path(sys.argv[1]).is_file():
        raise RuntimeError("Expected one existing IPA path.")
    validate_and_upload(Path(sys.argv[1]), os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"])


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, KeyError, OSError) as error:
        print(f"::error::{error}", file=sys.stderr)
        sys.exit(1)
