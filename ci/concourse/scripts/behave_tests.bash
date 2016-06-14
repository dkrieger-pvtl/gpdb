#!/bin/bash -l

set -eox pipefail

CWDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${CWDIR}/common.bash"

function gen_env(){
  cat > /opt/run_test.sh <<-EOF
		trap look4results ERR

		function look4results() {

		    results_files="../gpMgmt/gpMgmt_testunit_results.log"

		    for results_file in \${results_files}; do
			if [ -f "\${results_file}" ]; then
			    cat <<-FEOF

						======================================================================
						RESULTS FILE: \${results_file}
						----------------------------------------------------------------------

						\$(cat "\${results_file}")

					FEOF
			fi
		    done
		    exit 1
		}
		source /usr/local/greenplum-db-devel/greenplum_path.sh
		source /opt/gcc_env.sh
		source \${1}/gpdb_src/gpAux/gpdemo/gpdemo-env.sh
		cd \${1}/gpdb_src/gpMgmt/bin
		make behave tags=${BEHAVE_TAGS}
	EOF

	chmod a+x /opt/run_test.sh
}

function _main() {

    if [ -z "$BEHAVE_TAGS" ]; then
        echo "FATAL: BEHAVE_TAGS is not set"
        exit 1
    fi

    install_gpdb
    ./gpdb_src/ci/concourse/scripts/setup_gpadmin_user.bash
    make_cluster
    gen_env
    run_test
}

_main "$@"
