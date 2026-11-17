#!/usr/bin/env bash
# Shared by guard-bash.sh and guard-files.sh (layer 1a): decides whether a file name
# (or a glob for one) points at an env file that holds secrets.
# Source it, then: is_secret_env_name <basename>   (exit 0 = secret, 1 = not)

# Real env file names a glob could expand to. Templates are not in the list.
SECRET_ENV_SAMPLES=(.env .env.local .env.development .env.development.local
  .env.production .env.production.local .env.test .env.test.local)

is_secret_env_name() {
  # Lower-case: the default macOS volume is case-insensitive, so .ENV.local opens .env.local.
  local name
  name="$(tr '[:upper:]' '[:lower:]' <<<"$1")"
  case "$name" in
    .env.example | .env.sample | .env.template) return 1 ;;
    .env | .env.*) return 0 ;;
  esac
  # A glob such as .en?.local or .e* that would expand to an env file.
  # Only names that start with a dot: shell globs don't match dotfiles otherwise.
  case "$name" in
    .*[*?[]*)
      local s
      for s in "${SECRET_ENV_SAMPLES[@]}"; do
        [[ $s == $name ]] && return 0 # $name unquoted on purpose: it is a glob pattern
      done
      ;;
  esac
  return 1
}
