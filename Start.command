#!/bin/zsh
set -eu
cd -- "${0:A:h}"

# Run this option in the signed-in user's Terminal when an agent's sandbox
# cannot access the login Keychain. Never export the private key.
if [[ "${1:-}" == "--setup-signing" ]]; then
  typeset -a fingerprints labels
  while IFS= read -r identity; do
    if [[ "$identity" =~ '^[[:space:]]*[0-9]+\) ([[:xdigit:]]{40}) "(Apple Development: [^"]+)"' ]]; then
      fingerprints+=("$match[1]")
      labels+=("$match[2]")
    fi
  done < <(security find-identity -v -p codesigning)

  if (( ${#fingerprints} == 0 )); then
    print -u2 'No usable Apple Development certificate is available in this Terminal session.'
    print -u2 'Check Xcode → Settings → Apple Accounts → Personal Team → Manage Certificates.'
    exit 1
  fi

  choice=0
  if [[ -f Signing.local.mk ]]; then
    saved_identity=$(sed -nE 's/^CODE_SIGN_IDENTITY[[:space:]]*=[[:space:]]*([[:xdigit:]]{40})[[:space:]]*$/\1/p' Signing.local.mk)
    for (( i=1; i<=${#fingerprints}; i++ )); do
      if [[ "$fingerprints[$i]" == "$saved_identity" ]]; then
        choice=$i
        break
      fi
    done
  fi
  if (( choice == 0 && ${#fingerprints} == 1 )); then
    choice=1
  elif (( choice == 0 )); then
    print 'Choose your Personal Team certificate:'
    for (( i=1; i<=${#fingerprints}; i++ )); do
      print -r -- "$i) $labels[$i] — $fingerprints[$i]"
    done
    read -r 'choice?Certificate number: '
    if [[ "$choice" != <-> ]] || (( choice < 1 || choice > ${#fingerprints} )); then
      print -u2 'No valid selection. Nothing changed.'
      exit 1
    fi
  fi

  print -r -- "Using $labels[$choice]"
  print 'Quit Virtual Desktop from its menu bar menu before continuing.'
  read -r 'confirmation?Press Return once the app is closed: '

  mkdir -p build
  # Make target names cannot contain unescaped spaces. Keep these paths
  # relative, even when the repository's absolute path contains spaces.
  staging=$(mktemp -d 'build/signing-setup.XXXXXX')
  trap 'if [[ -e "$staging/Previous.app" ]]; then print -u2 "Previous app preserved at $staging/Previous.app"; else rm -rf -- "$staging"; fi' EXIT
  staged_app="$staging/VirtualDesktop.app"
  make build APP="$staged_app" BIN="$staged_app/Contents/MacOS/VirtualDesktop" \
    CODE_SIGN_IDENTITY="$fingerprints[$choice]"
  codesign --verify --strict "$staged_app"
  codesign -d -r- "$staged_app"
  print -r -- "CODE_SIGN_IDENTITY = $fingerprints[$choice]" > "$staging/Signing.local.mk"

  # Only replace the installation after the new build is signed and verified.
  if [[ -e build/VirtualDesktop.app ]]; then
    mv build/VirtualDesktop.app "$staging/Previous.app"
  fi
  if ! mv "$staged_app" build/VirtualDesktop.app; then
    [[ ! -e "$staging/Previous.app" ]] || mv "$staging/Previous.app" build/VirtualDesktop.app
    exit 1
  fi
  if ! mv "$staging/Signing.local.mk" Signing.local.mk; then
    mv build/VirtualDesktop.app "$staged_app"
    [[ ! -e "$staging/Previous.app" ]] || mv "$staging/Previous.app" build/VirtualDesktop.app
    exit 1
  fi
  rm -rf -- "$staging/Previous.app"
  print 'Signing configured. Future builds will reuse this certificate.'
  print 'macOS may ask once more for Screen Recording and Accessibility after this identity change.'
  open "build/VirtualDesktop.app"
  exit 0
elif (( $# > 0 )); then
  print -u2 'Usage: ./Start.command [--setup-signing]'
  exit 1
fi

make build
open "build/VirtualDesktop.app"
