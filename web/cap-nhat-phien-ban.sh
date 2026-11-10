#!/bin/bash
# Old name, kept so existing steps keep working. See web/update-version.sh.
exec "$(dirname "$0")/update-version.sh" "$@"
