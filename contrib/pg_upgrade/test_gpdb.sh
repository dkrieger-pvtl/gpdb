#!/usr/bin/env bash

# contrib/pg_upgrade/test_gpdb.sh
#
# Test driver for upgrading a Greenplum cluster with pg_upgrade within the same
# major version. Upgrading within the same major version is obviously not
# testing the full functionality of pg_upgrade, but it's a good compromise for
# being able to test pg_upgrade in a normal CI pipeline. Testing an actual
# major version upgrade need another setup. For test data, this script assumes
# the gpdemo cluster in gpAux/gpdemo/datadirs contains the end-state of an ICW
# test run. The test first performs a pg_dumpall, then initializes a parallel
# gpdemo cluster and upgrades it against the ICW cluster. After the upgrade it
# performs another pg_dumpall, if the two dumps match then the upgrade created
# a new identical copy of the cluster.

OLD_BINDIR=
OLD_DATADIR=
NEW_BINDIR=
NEW_DATADIR=

DEMOCLUSTER_OPTS=
PGUPGRADE_OPTS=

DUMP_OPTS=

# The normal ICW run has a gpcheckcat call, so allow this testrunner to skip
# running it in case it was just executed to save time.
gpcheckcat=1

# This is a regression test; we may want to disable it in the future but
#  still keep it around.
run_check_vacuum_worked=1

# gpdemo can create a cluster without mirrors, and if such a cluster should be
# upgraded then mirror upgrading must be turned off as it otherwise will report
# a failure.
mirrors=0

# Smoketesting pg_upgrade is done by just upgrading the QD and checking the
# resulting schema. This is *NOT* a test of whether pg_upgrade can successfully
# upgrade a cluster but a test intended to catch when objects aren't properly
# handled in pg_dump/pg_upgrade wrt Oid synchronization
smoketest=0

# For debugging purposes it can be handy to keep the temporary directory around
# after the test. If set to 1 the directory isn't removed when the testscript
# exits
retain_tempdir=0

# For performance testing, we want to skip everything other than what we need
# to upgrade to the new cluster.  This tests the nominal production use case.
# TODO: what about the pg_upgrade precheck for upgrade?
perf_test=0

# Not all platforms have a realpath binary in PATH, most notably macOS doesn't,
# so provide an alternative implementation. Returns an absolute path in the
# variable reference passed as the first parameter.  Code inspired by:
# http://stackoverflow.com/questions/3572030/bash-script-absolute-path-with-osx
realpath()
{
	local __ret=$1
	local path

	if [[ $2 = /* ]]; then
		path="$2"
	else
		path="$PWD/${2#./}"
	fi

	eval $__ret="'$path'"
}

restore_cluster()
{
	status=$?

	pushd $base_dir
	# Reset the pg_control files from the old cluster which were renamed
	# .old by pg_upgrade to avoid booting up an upgraded cluster.
	find ${OLD_DATADIR} -type f -name 'pg_control.old' |
	while read control_file; do
		mv "${control_file}" "${control_file%.old}"
	done

	# Remove the copied lalshell unless we're running in the gpdemo
	# directory where it's version controlled
	if ! git ls-files lalshell --error-unmatch >/dev/null 2>&1; then
		rm -f lalshell
	fi

	# Remove the temporary cluster, and associated files. Keep things around if
	# there was a failure, or if -r is passed.
	if (( ! $retain_tempdir && ! $status )) ; then
		# If we are asked to blow away the temp root, echo any potential error
		# files to the output channel to aid debugging
		find ${temp_root} -type f -name "*.txt" | grep -v share |
		while read error_file; do
			cat ${error_file}
		done
		# Remove configuration files created by setting up the new cluster
		rm -f "clusterConfigPostgresAddonsFile"
		rm -f "clusterConfigFile"
		rm -f "gpdemo-env.sh"
		rm -f "hostfile"
		# Remove temporary cluster
		rm -rf "$temp_root"
	fi
}

# Test for a nasty regression -- if VACUUM FREEZE doesn't work correctly during
# upgrade, things fail later in mysterious ways. As a litmus test, check to make
# sure that catalog tables have been frozen. (We use gp_segment_configuration
# because the upgrade shouldn't have touched it after the freeze.)
check_vacuum_worked()
{
	local datadir=$1
	local contentid=$2

	if (( !$run_check_vacuum_worked )) ; then
        return 0;
    fi

	# GPDB_94_MERGE_FIXME: This test doesn't work in 9.4 anymore, because
	# freezing no longer resets 'xmin', it just sets a new flag in the
	# tuple header to indicate that the row is frozen. See upstream commit
	# 37484ad2aa. Need to find a new way to verify this.
	return 0;

	echo "Verifying VACUUM FREEZE using gp_segment_configuration xmins..."

	# Start the instance using the same pg_ctl invocation used by pg_upgrade.
	"${NEW_BINDIR}/pg_ctl" -w -l /dev/null -D "${datadir}" \
		-o "-p 18432 --gp_dbid=1 --gp_num_contents_in_cluster=0 --gp_contentid=${contentid} --xid_warn_limit=10000000 -b" \
		start

	# Query for the xmin ages.
	local xmin_ages=$( \
		PGOPTIONS='-c gp_session_role=utility' \
		"${NEW_BINDIR}/psql" -c 'SELECT age(xmin) FROM pg_catalog.gp_segment_configuration GROUP BY age(xmin);' \
			 -p 18432 -t -A template1 \
	)

	# Stop the instance.
	"${NEW_BINDIR}/pg_ctl" -l /dev/null -D "${datadir}" stop

	# Check to make sure all the xmins are frozen (maximum age).
	while read age; do
		if [ "$age" -ne "2147483647" ]; then
			echo "ERROR: gp_segment_configuration has an entry of age $age"
			return 1
		fi
	done <<< "$xmin_ages"

	return 0
}

upgrade_qd()
{
	mkdir -p $1

	# Run pg_upgrade
	pushd $1
	time ${NEW_BINDIR}/pg_upgrade --mode=dispatcher --old-bindir=${OLD_BINDIR} --old-datadir=$2 --new-bindir=${NEW_BINDIR} --new-datadir=$3 ${PGUPGRADE_OPTS}
	if (( $? )) ; then
		echo "ERROR: Failure encountered in upgrading qd node"
		exit 1
	fi
	popd

	if ! check_vacuum_worked "$3" -1; then
		echo "ERROR: VACUUM FREEZE appears to have failed during QD upgrade"
		exit 1
	fi

	# Remember where we were when we upgraded the QD node. pg_upgrade generates
	# some files there that we need to copy to QE nodes.
	qddir=$1
}

upgrade_segment()
{
	mkdir -p $1

	# Run pg_upgrade
	pushd $1
	time ${NEW_BINDIR}/pg_upgrade --mode=segment --old-bindir=${OLD_BINDIR} --old-datadir=$2 --new-bindir=${NEW_BINDIR} --new-datadir=$3 ${PGUPGRADE_OPTS}
	if (( $? )) ; then
		echo "ERROR: Failure encountered in upgrading node"
		exit 1
	fi
	popd

	# TODO: run check_vacuum_worked on each segment, too, once we have a good
	# candidate catalog table (gp_segment_configuration doesn't exist on
	# segments).
}

usage()
{
	appname=`basename $0`
	echo "$appname usage:"
	echo " -o <dir>     Directory containing old datadir"
	echo " -b <dir>     Directory containing binaries"
	echo " -s           Run smoketest only"
	echo " -C           Skip gpcheckcat test"
	echo " -k           Add checksums to new cluster"
	echo " -K           Remove checksums during upgrade"
	echo " -m           Upgrade mirrors"
	echo " -r           Retain temporary installation after test, even on success"
	echo " -p           pg_upgrade performance checking only"
	exit 0
}

# Diffs the dump1.sql and dump2.sql files in the $temp_root, and exits
# accordingly (exit code 1 if they differ, 0 otherwise).
diff_and_exit() {
	args=
	pgopts=

	if (( $smoketest )) ; then
		# After a smoke test, we only have the master available to query.
		args='-m'
		pgopts='-c gp_session_role=utility'
	fi

	# Start the new cluster, dump it and stop it again when done. We need to bump
	# the exports to the new cluster for starting it but reset back to the old
	# when done. Set the same variables as gpdemo-env.sh exports. Since creation
	# of that file can collide between the gpdemo clusters, perform it manually
	export PGPORT=17432
	export MASTER_DATA_DIRECTORY="${NEW_DATADIR}/qddir/demoDataDir-1"
	gpstart -a ${args}

	echo -n 'Dumping database schema after upgrade... '
	PGOPTIONS="${pgopts}" ${NEW_BINDIR}/pg_dumpall ${DUMP_OPTS} -f "$temp_root/dump2.sql"
	echo done

	gpstop -a ${args}
	export PGPORT=15432
	export MASTER_DATA_DIRECTORY="${OLD_DATADIR}/qddir/demoDataDir-1"

	# Since we've used the same pg_dumpall binary to create both dumps, whitespace
	# shouldn't be a cause of difference in the files but it is. Partitioning info
	# is generated via backend functionality in the cluster being dumped, and not
	# in pg_dump, so whitespace changes can trip up the diff.
	# FIXME: Maybe we should not use '-w' in the future since it is too aggressive.
	if diff -w "$temp_root/dump1.sql" "$temp_root/dump2.sql" >/dev/null; then
		rm -f regression.diffs
		echo "Passed"
		exit 0
	fi

	# To aid debugging in pipelines, print the diff to stdout. Ignore
	# whitespace, as above, to avoid misdirecting the troubleshooter.
	diff -wdu "$temp_root/dump1.sql" "$temp_root/dump2.sql" | tee regression.diffs
	echo "Error: before and after dumps differ"
	exit 1
}

# Main
temp_root=`pwd`/tmp_check
base_dir=`pwd`

while getopts ":o:b:sCkKmrp" opt; do
	case ${opt} in
		o )
			realpath OLD_DATADIR "${OPTARG}"
			;;
		b )
			realpath NEW_BINDIR "${OPTARG}"
			realpath OLD_BINDIR "${OPTARG}"
			;;
		s )
			smoketest=1
			DUMP_OPTS+=' --schema-only'
			;;
		C )
			gpcheckcat=0
			;;
		k )
			add_checksums=1
			PGUPGRADE_OPTS+=' --add-checksum '
			;;
		K )
			remove_checksums=1
			DEMOCLUSTER_OPTS=' -K '
			PGUPGRADE_OPTS+=' --remove-checksum '
			;;
		m )
			mirrors=1
			;;
		r )
			retain_tempdir=1
			PGUPGRADE_OPTS+=' --retain '
			;;
		p )
			perf_test=1
			gpcheckcat=0
			run_check_vacuum_worked=0
			;;
		* )
			usage
			;;
	esac
done

if [ -z "${OLD_DATADIR}" ] || [ -z "${NEW_BINDIR}" ]; then
	usage
fi

# This should be rejected by pg_upgrade as well, but this test is not concerned
# with testing handling incorrect option handling in pg_upgrade so we'll error
# out early instead.
if [ ! -z "${add_checksums}"] && [ ! -z "${remove_checksums}" ]; then
	echo "ERROR: adding and removing checksums are mutually exclusive"
	exit 1
fi

rm -rf "$temp_root"
mkdir -p "$temp_root"
if [ ! -d "$temp_root" ]; then
	echo "ERROR: unable to create workdir: $temp_root"
	exit 1
fi

trap restore_cluster EXIT

# The cluster should be running by now, but in case it isn't, issue a restart.
# Since we expect the testcluster to be a stock standard gpdemo, we test for
# the presence of it. Worst case we powercycle once for no reason, but it's
# better than failing due to not having a cluster to work with.
if [ -f "/tmp/.s.PGSQL.15432.lock" ]; then
	ps aux | grep  `head -1 /tmp/.s.PGSQL.15432.lock` | grep -q postgres
	if (( $? )) ; then
		gpstart -a
	fi
else
	gpstart -a
fi

# Run any pre-upgrade tasks to prep the cluster
if [ -f "test_gpdb_pre.sql" ]; then
	if ! psql -f test_gpdb_pre.sql -v ON_ERROR_STOP=1 postgres; then
		echo "ERROR: unable to execute pre-upgrade cleanup"
		exit 1
	fi
fi

# Ensure that the catalog is sane before attempting an upgrade. While there is
# (limited) catalog checking inside pg_upgrade, it won't catch all issues, and
# upgrading a faulty catalog won't work.
if (( $gpcheckcat )) ; then
	gpcheckcat
	if (( $? )) ; then
		echo "ERROR: gpcheckcat reported catalog issues, fix before upgrading"
		exit 1
	fi
fi

if (( !$perf_test )) ; then
	echo -n 'Dumping database schema before upgrade... '
	${NEW_BINDIR}/pg_dumpall ${DUMP_OPTS} -f "$temp_root/dump1.sql"
	echo done
fi

gpstop -a

# Create a new gpdemo cluster in the temproot. Using the old datadir for the
# path to demo_cluster.sh is a bit of a hack, but since this test relies on
# gpdemo having been used for ICW it will do for now.
export MASTER_DEMO_PORT=17432
export DEMO_PORT_BASE=27432
export NUM_PRIMARY_MIRROR_PAIRS=3
export MASTER_DATADIR=${temp_root}
cp ${OLD_DATADIR}/../lalshell .
BLDWRAP_POSTGRES_CONF_ADDONS=fsync=off ${OLD_DATADIR}/../demo_cluster.sh ${DEMOCLUSTER_OPTS}

NEW_DATADIR="${temp_root}/datadirs"

export MASTER_DATA_DIRECTORY="${NEW_DATADIR}/qddir/demoDataDir-1"
export PGPORT=17432
gpstop -a
MASTER_DATA_DIRECTORY=""; unset MASTER_DATA_DIRECTORY
PGPORT=""; unset PGPORT
PGOPTIONS=""; unset PGOPTIONS

epoch_for_perf_start=`date +%s`

# Start by upgrading the master
upgrade_qd "${temp_root}/upgrade/qd" "${OLD_DATADIR}/qddir/demoDataDir-1/" "${NEW_DATADIR}/qddir/demoDataDir-1/"
epoch_for_perf_1=`date +%s`
qd_run_time=`expr $epoch_for_perf_1 - $epoch_for_perf_start`
echo "number_of_seconds_for_upgrade_qd $qd_run_time"

# If this is a minimal smoketest to ensure that we are handling all objects
# properly, then check that the upgraded schema is identical and exit.
if (( $smoketest )) ; then
	diff_and_exit
fi

# Upgrade all the segments and mirrors. In a production setup the segments
# would be upgraded first and then the mirrors once the segments are verified.
# In this scenario we can cut corners since we don't have any important data
# in the test cluster and we only concern ourselves with 100% success rate.
for i in 1 2 3
do
	j=$(($i-1))
	k=$(($i+1))

	# Replace the QE datadir with a copy of the QD datadir, in order to
	# bootstrap the QE upgrade so that we don't need to dump/restore
	mv "${NEW_DATADIR}/dbfast$i/demoDataDir$j/" "${NEW_DATADIR}/dbfast$i/demoDataDir$j.old/"
	cp -rp "${NEW_DATADIR}/qddir/demoDataDir-1/" "${NEW_DATADIR}/dbfast$i/demoDataDir$j/"
	# Retain the segment configuration
	cp "${NEW_DATADIR}/dbfast$i/demoDataDir$j.old/postgresql.conf" "${NEW_DATADIR}/dbfast$i/demoDataDir$j/postgresql.conf"
	cp "${NEW_DATADIR}/dbfast$i/demoDataDir$j.old/pg_hba.conf" "${NEW_DATADIR}/dbfast$i/demoDataDir$j/pg_hba.conf"
	cp "${NEW_DATADIR}/dbfast$i/demoDataDir$j.old/postmaster.opts" "${NEW_DATADIR}/dbfast$i/demoDataDir$j/postmaster.opts"
	cp "${NEW_DATADIR}/dbfast$i/demoDataDir$j.old/gp_replication.conf" "${NEW_DATADIR}/dbfast$i/demoDataDir$j/gp_replication.conf"
	# Remove QD only files
	rm -f "${NEW_DATADIR}/dbfast$i/demoDataDir$j/gp_dbid"
	rm -f "${NEW_DATADIR}/dbfast$i/demoDataDir$j/gpssh.conf"
	rm -rf "${NEW_DATADIR}/dbfast$i/demoDataDir$j/gpperfmon"
	# Upgrade the segment data files without dump/restore of the schema

	epoch_for_perf_2=`date +%s`
	upgrade_segment "${temp_root}/upgrade/dbfast$i" "${OLD_DATADIR}/dbfast$i/demoDataDir$j/" "${NEW_DATADIR}/dbfast$i/demoDataDir$j/"
	epoch_for_perf_3=`date +%s`
	qe_run_time=`expr $epoch_for_perf_3 - $epoch_for_perf_2`
	echo "number_of_seconds_for_upgrade_qe $qe_run_time"


	if (( $mirrors )) ; then
		epoch_for_perf_3=`date +%s`
		upgrade_segment "${temp_root}/upgrade/dbfast_mirror$i" "${OLD_DATADIR}/dbfast_mirror$i/demoDataDir$j/" "${NEW_DATADIR}/dbfast_mirror$i/demoDataDir$j/"
		epoch_for_perf_4=`date +%s`
	fi
done

epoch_for_perf_final=`date +%s`
perf_run_time=`expr $epoch_for_perf_final - $epoch_for_perf_start`
echo "number_of_seconds_for_upgrade $perf_run_time"

. ${NEW_BINDIR}/../greenplum_path.sh


if (( !$perf_test )) ; then
	diff_and_exit
fi