#!/usr/bin/env bash
# Open a passcode-authenticated shared connection to ALCF Aurora.
exec bash "$(dirname "${BASH_SOURCE[0]}")/alcf_session.sh" aurora
