#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"
source "$ROOT_DIR/lib/ssh_access.sh"
init "$@"
site_user
setup_ssh_access
