#!/bin/bash -l

## ----------------------------------------------------------------------
## General purpose functions
## ----------------------------------------------------------------------

function set_env() {
    export TERM=xterm-256color
    export TIMEFORMAT=$'\e[4;33mIt took %R seconds to complete this step\e[0m';
}

function prep_env_for_centos() {
  case "$TARGET_OS_VERSION" in
    5)
      BLDARCH=rhel5_x86_64
      export JAVA_HOME=/usr/lib/jvm/java-1.6.0-openjdk-1.6.0.40.x86_64
      source /opt/gcc_env.sh
      ;;

    6)
      BLDARCH=rhel6_x86_64
      export JAVA_HOME=/usr/lib/jvm/java-1.6.0-openjdk-1.6.0.40.x86_64
      ;;

    7)
      BLDARCH=rhel7_x86_64
      alternatives --set java /usr/lib/jvm/java-1.7.0-openjdk-1.7.0.111-2.6.7.2.el7_2.x86_64/jre/bin/java
      export JAVA_HOME=/usr/lib/jvm/java-1.7.0-openjdk-1.7.0.111-2.6.7.2.el7_2.x86_64
      ln -sf /usr/bin/xsubpp /usr/share/perl5/ExtUtils/xsubpp
      source /opt/gcc_env.sh
      ;;

    *)
    echo "TARGET_OS_VERSION not set or recognized for Centos/RHEL"
    exit 1
    ;;
  esac

  ln -sf "/$(pwd)/gpdb_src/gpAux/ext/${BLDARCH}/python-2.6.2" /opt/python-2.6.2
  export PATH=${JAVA_HOME}/bin:${PATH}
}

function generate_build_number() {
  pushd gpdb_src
    #Only if its git repro, add commit SHA as build number
    # BUILD_NUMBER file is used by getversion file in GPDB to append to version
    if [ -d .git ] ; then
      echo "commit: $(git rev-parse HEAD)" > BUILD_NUMBER
    fi
  popd
}

## ----------------------------------------------------------------------
## Test functions
## ----------------------------------------------------------------------

function install_gpdb() {
    [ ! -d /usr/local/greenplum-db-devel ] && mkdir -p /usr/local/greenplum-db-devel
    tar -xzf bin_gpdb/bin_gpdb.tar.gz -C /usr/local/greenplum-db-devel
}

function install_sync_tools() {
    tar -xzf sync_tools_gpdb/sync_tools_gpdb.tar.gz -C gpdb_src/gpAux
}

function make_sync_tools() {
  pushd gpdb_src/gpAux
    make IVYREPO_HOST="$IVYREPO_HOST" IVYREPO_REALM="$IVYREPO_REALM" IVYREPO_USER="$IVYREPO_USER" IVYREPO_PASSWD="$IVYREPO_PASSWD" sync_tools
    tar -czf "$GPDB_ARTIFACTS_DIR/sync_tools_gpdb.tar.gz" ext
  popd
}

function configure() {
  source /opt/gcc_env.sh
  pushd gpdb_src/gpAux
      make INSTLOC=/usr/local/greenplum-db-devel ../GNUmakefile
  popd
}

function make_cluster() {
  source /usr/local/greenplum-db-devel/greenplum_path.sh
  workaround_before_concourse_stops_stripping_suid_bits
  pushd gpdb_src/gpAux/gpdemo
      su gpadmin -c make cluster
  popd
}

workaround_before_concourse_stops_stripping_suid_bits() {
  chmod u+s /bin/ping
}

function run_test() {
  ln -s "$(pwd)/gpdb_src/gpAux/ext/rhel5_x86_64/python-2.6.2" /opt
  su - gpadmin -c "bash /opt/run_test.sh $(pwd)"
}
