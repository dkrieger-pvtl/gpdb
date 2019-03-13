#!/bin/bash -l

set -eox pipefail

CWDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${CWDIR}/common.bash"

pushd /home/gpadmin
#./gpdb_src/concourse/scripts/setup_gpadmin_user.bash
make_cluster
