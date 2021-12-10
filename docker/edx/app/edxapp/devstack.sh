#!/usr/bin/env bash
# For compatibility with Devstack.
#
# Devstack uses a script like this to open a shell and/or run commands on containers.
# It really just serves as a way to source the shell environment (../edxapp_env)
# without knowing the name of the env file iteslf. This could be solved more
# simply by choosing a standard name for the env file across all services
# or putting the env variables in the global bash environment. Alas.
#
# We purposefully don't support the 'start' command because it isn't used by
# Devstack, and we don't want new integrators to begin depending on it.
#
# Source of the original script, for context:
# https://github.com/edx/configuration/blob/open-release/maple.master/playbooks/roles/edxapp/templates/devstack.sh.j2

source /edx/app/edxapp/edxapp_env

case "$1" in

   open) cd /edx/app/edxapp/edx-platform && /bin/bash ;;

  start) echo "start is no longer a supported command" && exit 1 ;;

   exec) shift && cd /edx/app/edxapp/edx-platform && "$@" ;;

      *) "$@" ;;

esac
