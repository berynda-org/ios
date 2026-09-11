# Internal TestFlight delivery

The `Internal TestFlight` workflow is manual-only. It runs the package, app,
and deterministic UI tests before it imports signing material, archives a
Release build with Xcode 26.3, validates the IPA, uploads it to App Store
Connect, and retains the signed IPA plus dSYMs for 30 days.

## Required Apple material

- an Apple Distribution certificate exported as a password-protected `.p12`;
- an App Store Connect provisioning profile for `org.berynda.ios` with
  Associated Domains enabled;
- an App Store Connect API key with the least-privileged role that can upload
  builds; and
- the API key ID and issuer ID shown by App Store Connect.

Berynda uses its **own** certificate, profile, and API key — nothing is shared
with Lexykon — so either app's access can be revoked or rotated without
touching the other. Apple still scopes certificates and API keys to the whole
team (`KHMPLP3CXQ`): a separate key is a separate credential, not one limited
to a single app.

Create a fresh provisioning profile after changing an App ID capability.
Never commit a certificate, profile, private key, password, or encoded secret,
and never paste one into a chat or an issue.

## Required GitHub Actions secrets

| Secret | Value |
| --- | --- |
| `APP_STORE_CERTIFICATE_P12_BASE64` | Base64 of the distribution `.p12` |
| `APP_STORE_CERTIFICATE_P12_PASSWORD` | Password used to export the `.p12` |
| `APP_STORE_PROFILE_BASE64` | Base64 of the App Store `.mobileprovision` |
| `APP_STORE_PROFILE_NAME` | Exact provisioning-profile name |
| `APP_STORE_CONNECT_KEY_ID` | App Store Connect API key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | App Store Connect issuer UUID |
| `APP_STORE_CONNECT_PRIVATE_KEY_BASE64` | Base64 of `AuthKey_<KEY_ID>.p8` |

Base64 is an encoding, not encryption. The encoded values belong only in
GitHub Actions secrets. Restrict repository administration and workflow-file
changes to trusted maintainers, and revoke the API key if repository access is
ever in doubt.

## Setting up Berynda's signing material on Windows

Everything below is stored in `D:\berynda\secrets\ios`, which sits outside
every git repository. Run the commands in **PowerShell** — a cmder PowerShell
tab works; `cmd` and Git Bash do not — and keep the same window open from step
1 to step 6, since later steps reuse the variables set here:

```powershell
$ssl = "C:\Program Files\Git\usr\bin\openssl.exe"
$dir = "D:\berynda\secrets\ios"
New-Item -ItemType Directory -Force $dir | Out-Null
```

OpenSSL ships with Git for Windows and is called by full path because it is
usually not on PowerShell's `PATH`. That build is OpenSSL 1.1.1, which writes a
`.p12` the macOS runner's `security import` accepts; an OpenSSL 3 build would
need `-legacy`. If you reopen the window, run the block above again.

### 1. Create a private key and a signing request

```powershell
& $ssl genrsa -out "$dir\berynda_distribution.key" 2048
& $ssl req -new -key "$dir\berynda_distribution.key" -out "$dir\berynda_distribution.csr" -subj "/CN=Oleksandr Kryvonos/C=DE"
```

The `.key` is the certificate's private key and is not password-protected. It
stays in this folder so a lost `.p12` password can be recovered by exporting a
new `.p12` from it (step 3); guard the folder accordingly.

### 2. Create the certificate at Apple

In [Certificates, Identifiers & Profiles → Certificates](https://developer.apple.com/account/resources/certificates/list)
for team `KHMPLP3CXQ`, choose **+** → **Apple Distribution** → **Continue**,
upload `berynda_distribution.csr`, then **Download**. Save the file as
`D:\berynda\secrets\ios\berynda_distribution.cer`.

Every Apple Distribution certificate on the team shows the same name, so tell
them apart by expiry date. The one expiring **2027/04/14** signs Lexykon —
never revoke it. If Apple refuses because the team has reached its
certificate limit, revoke an older one you no longer have the private key for.

### 3. Export the password-protected `.p12`

```powershell
& $ssl x509 -inform DER -in "$dir\berynda_distribution.cer" -out "$dir\berynda_distribution.pem"
& $ssl pkcs12 -export -inkey "$dir\berynda_distribution.key" -in "$dir\berynda_distribution.pem" -out "$dir\berynda_distribution.p12" -name "Berynda Apple Distribution" -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1
```

OpenSSL asks for a new export password twice. **Save it in your password
manager before continuing** — a `.p12` whose password is lost is useless.
`No certificate matches private key` means the `.cer` was not issued for this
key's signing request; repeat step 2 with `berynda_distribution.csr`.

Check the file opens with that password:

```powershell
& $ssl pkcs12 -in "$dir\berynda_distribution.p12" -info -noout
```

It should finish without `Mac verify error`.

### 4. Create the provisioning profile

In [Profiles](https://developer.apple.com/account/resources/profiles/list),
choose **+** → **App Store Connect** → **Continue**, pick the App ID
`org.berynda.ios`, and select the certificate from step 2 — the newest expiry
date, about a year from today, **not** 2027/04/14. Name it
`Berynda App Store`, then **Generate** and **Download**. Save the
`.mobileprovision` into `D:\berynda\secrets\ios`, and make sure it is the only
`.mobileprovision` there.

If a profile named `Berynda App Store` already exists, open it, choose
**Edit**, select only the new certificate, **Save**, and download it instead —
profile names are unique.

### 5. Create the App Store Connect API key

In [App Store Connect](https://appstoreconnect.apple.com/) → **Users and
Access** → **Integrations** → **App Store Connect API** → **Team Keys**, choose
**+**, name it `Berynda GitHub`, give it **Developer** access, and generate it.

- **Download API Key** works only once. Save the file into
  `D:\berynda\secrets\ios` under its original name, `AuthKey_<KEY_ID>.p8` —
  step 6 reads the key ID from that name — and make sure it is the only
  `AuthKey_*.p8` there.
- Note the **Issuer ID** shown above the list of keys; step 6 asks for it.
- If an upload is later refused for insufficient permissions, raise the key's
  role to **App Manager**.

Also confirm that App Store Connect → **Apps** lists Berynda (record
`6808289031`) with bundle ID `org.berynda.ios`.

### 6. Store the seven secrets

This replaces every existing value, including anything uploaded earlier from
other material:

```powershell
$repo = "berynda-org/ios"
$p8   = @(Get-ChildItem "$dir\AuthKey_*.p8")
$prof = @(Get-ChildItem "$dir\*.mobileprovision")
if ($p8.Count -ne 1)   { throw "Expected one AuthKey_*.p8 in $dir, found $($p8.Count)" }
if ($prof.Count -ne 1) { throw "Expected one .mobileprovision in $dir, found $($prof.Count)" }
$files = [ordered]@{
    APP_STORE_CERTIFICATE_P12_BASE64     = "$dir\berynda_distribution.p12"
    APP_STORE_PROFILE_BASE64             = $prof[0].FullName
    APP_STORE_CONNECT_PRIVATE_KEY_BASE64 = $p8[0].FullName
}
foreach ($name in $files.Keys) {
    gh secret set $name --repo $repo --body ([Convert]::ToBase64String([IO.File]::ReadAllBytes($files[$name])))
    if ($LASTEXITCODE -ne 0) { throw "Failed to set $name" }
}
gh secret set APP_STORE_CONNECT_KEY_ID --repo $repo --body ($p8[0].BaseName -replace '^AuthKey_', '')
gh secret set APP_STORE_PROFILE_NAME --repo $repo --body "Berynda App Store"
gh secret set APP_STORE_CONNECT_ISSUER_ID --repo $repo
gh secret set APP_STORE_CERTIFICATE_P12_PASSWORD --repo $repo
gh secret list --repo $repo
```

The last two `set` commands prompt: paste the Issuer ID, then type the `.p12`
password from step 3. The input is hidden. Cmder may ask you to confirm
pasting several lines at once; accept. Each value is passed as an argument
rather than piped, because Windows PowerShell 5.1 appends a line break to piped
input. `gh secret list` should show all seven secrets with today's date.

### 7. Toolchain

Since 28 April 2026 App Store Connect accepts only builds made with Xcode 26 or
later against the iOS 26 SDK. Both workflows select Xcode 26.3 on the
`macos-15` runner. Do not switch to a floating "latest" Xcode or to the
`macos-26` runner without also changing the test destination: the tests run on
an `iPhone 16 Pro` simulator, which `macos-26` does not provide.

## First upload checklist

1. Confirm Bundle ID `org.berynda.ios`, Team ID `KHMPLP3CXQ`, version `0.1.0`,
   and the App Store Connect record `6808289031`.
2. Complete the Windows setup above, so that all seven secrets are Berynda's
   own.
3. Run the workflow — from GitHub Actions → **Internal TestFlight** →
   **Run workflow** on `main`, or with
   `gh workflow run testflight.yml --repo berynda-org/ios --ref main`.
4. Wait for Apple processing, answer the build's export-compliance prompt if
   Apple still presents it, and add the build to the internal testing group.
   Internal testers need no Beta App Review; external testers do.
5. Install on a real iPhone and iPad and execute the Milestone A acceptance
   journeys from `docs/IMPLEMENTATION-PLAN.md`.

## Rotating or revoking

- **Revoke CI upload access:** revoke the `Berynda GitHub` key in App Store
  Connect. Lexykon is unaffected.
- **The certificate expires after a year.** Repeat steps 1–4 and 6; the key
  from step 5 can stay.
