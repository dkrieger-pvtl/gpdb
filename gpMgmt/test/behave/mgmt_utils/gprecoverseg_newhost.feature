@gprecoverseg_newhost
Feature: gprecoverseg tests involving migrating to a new host

########################### @concourse_cluster tests ###########################
# The @concourse_cluster tag denotes the scenario that requires a remote cluster
    @concourse_cluster
    Scenario: gprecoverseg -p successfully fails over to a new host
      Given the database is running
      And all the segments are running
      And the segments are synchronized
      And the user runs gpconfig sets guc "wal_sender_timeout" with "15s"
      And the user runs "gpstop -air"
      And the cluster configuration is saved "before"
      And segment hosts "sdw1" are disconnected from the cluster and from the spare segment hosts "sdw5,sdw6"
      And the cluster configuration reflects the desired state "hostname='sdw1' and status='u'"
      When the user runs "gprecoverseg -a -p sdw5"
      Then gprecoverseg should return a return code of 0
      And the cluster configuration is saved "after_one"
      And the "before" and "after_one" cluster configuration matches with the expected for gprecoverseg newhost
      And the mirrors replicate and fail over and back correctly
      And segment hosts "sdw1" are reconnected to the cluster and to the spare segment hosts "sdw6"
      And the original cluster state is recreated to "sdw1"
      And the cluster configuration is saved "after_recreation"
      And the "before" and "after_recreation" cluster configuration matches with the expected for gprecoverseg newhost

    @concourse_cluster
    Scenario: gprecoverseg -p successfully fails over to multiple hosts
      Given the database is running
      And all the segments are running
      And the segments are synchronized
      And the user runs gpconfig sets guc "wal_sender_timeout" with "15s"
      And the user runs "gpstop -air"
      And the cluster configuration is saved "before"
      And segment hosts "sdw1,sdw3" are disconnected from the cluster and from the spare segment hosts "sdw5,sdw6"
      And the cluster configuration reflects the desired state "(hostname='sdw1' or hostname='sdw3') and status='u'"
      When the user runs "gprecoverseg -a -p sdw5,sdw6"
      Then gprecoverseg should return a return code of 0
      And the cluster configuration is saved "after_two"
      And the "before" and "after_two" cluster configuration matches with the expected for gprecoverseg newhost
      And the mirrors replicate and fail over and back correctly
      And segment hosts "sdw1,sdw3" are reconnected to the cluster and to the spare segment hosts "none"
      And the original cluster state is recreated to "sdw1,sdw3"
      And the cluster configuration is saved "after_recreation"
      And the "before" and "after_recreation" cluster configuration matches with the expected for gprecoverseg newhost

    @concourse_cluster
    Scenario: gprecoverseg failing test to keep cluster up
      Given this test does not exist so it fails



#    [gpadmin@mdw ~]$ cat /etc/hosts
#    127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
#    ::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
#    10.0.154.92 ccp-sage-wanderer-0.c.data-gpdb-cm.internal ccp-sage-wanderer-0  # Added by Google
#    169.254.169.254 metadata.google.internal  # Added by Google
#    10.0.154.92 mdw ccp-sage-wanderer-0
#    10.0.154.87 sdw1 ccp-sage-wanderer-1
#    10.0.154.55 sdw2 ccp-sage-wanderer-2
#    10.0.154.89 sdw3 ccp-sage-wanderer-3
#    10.0.154.67 sdw4 ccp-sage-wanderer-4
#
#    [gpadmin@mdw ~]$ cat /etc/hosts | grep sdw1 | awk '{ print $3 }'
#    ccp-sage-wanderer-1
#    [gpadmin@mdw ~]$ cat /etc/hosts | grep sdw1 | awk '{ print $2 }'
#    sdw1
#    [gpadmin@mdw ~]$ cat /etc/hosts | grep sdw1 | awk '{ print $1 }'
#    10.0.154.87

#    @concourse_cluster
#    Scenario: When gprecoverseg full recovery is executed and an existing postmaster.pid on the killed primary segment corresponds to a non postgres process
#        Given the database is running
#        And all the segments are running
#        And the segments are synchronized
#        And the "primary" segment information is saved
#        When the postmaster.pid file on "primary" segment is saved
#        And user stops all primary processes
#        When user can start transactions
#        And the background pid is killed on "primary" segment
#        And we run a sample background script to generate a pid on "primary" segment
#        And we generate the postmaster.pid file with the background pid on "primary" segment
#        And the user runs "gprecoverseg -F -a"
#        Then gprecoverseg should return a return code of 0
#        And gprecoverseg should not print "Unhandled exception in thread started by <bound method Worker.__bootstrap" to stdout
#        And gprecoverseg should print "Skipping to stop segment.* on host.* since it is not a postgres process" to stdout
#        And all the segments are running
#        And the segments are synchronized
#        When the user runs "gprecoverseg -ra"
#        Then gprecoverseg should return a return code of 0
#        And gprecoverseg should not print "Unhandled exception in thread started by <bound method Worker.__bootstrap" to stdout
#        And the segments are synchronized
#        And the backup pid file is deleted on "primary" segment
#        And the background pid is killed on "primary" segment
#
#    @concourse_cluster
#    Scenario: gprecoverseg full recovery testing
#        Given the database is running
#        And all the segments are running
#        And the segments are synchronized
#        And the information of a "mirror" segment on a remote host is saved
#        When user kills a "mirror" process with the saved information
#        And user can start transactions
#        Then the saved "mirror" segment is marked down in config
#        When the user runs "gprecoverseg -F -a"
#        Then gprecoverseg should return a return code of 0
#        And gprecoverseg should not print "Running pg_rewind on required mirrors" to stdout
#        And all the segments are running
#        And the segments are synchronized
#
#    @concourse_cluster
#    Scenario: gprecoverseg with -i and -o option
#        Given the database is running
#        And all the segments are running
#        And the segments are synchronized
#        And the information of a "mirror" segment on a remote host is saved
#        When user kills a "mirror" process with the saved information
#        And user can start transactions
#        Then the saved "mirror" segment is marked down in config
#        When the user runs "gprecoverseg -o failedSegmentFile"
#        Then gprecoverseg should return a return code of 0
#        Then gprecoverseg should print "Configuration file output to failedSegmentFile successfully" to stdout
#        When the user runs "gprecoverseg -i failedSegmentFile -a"
#        Then gprecoverseg should return a return code of 0
#        Then gprecoverseg should print "1 segment\(s\) to recover" to stdout
#        And all the segments are running
#        And the segments are synchronized
#
#    @concourse_cluster
#    Scenario: gprecoverseg should not throw exception for empty input file
#        Given the database is running
#        And all the segments are running
#        And the segments are synchronized
#        And the information of a "mirror" segment on a remote host is saved
#        When user kills a "mirror" process with the saved information
#        And user can start transactions
#        Then the saved "mirror" segment is marked down in config
#        When the user runs command "touch /tmp/empty_file"
#        When the user runs "gprecoverseg -i /tmp/empty_file -a"
#        Then gprecoverseg should return a return code of 0
#        Then gprecoverseg should print "No segments to recover" to stdout
#        When the user runs "gprecoverseg -a -F"
#        Then all the segments are running
#        And the segments are synchronized
#
#    @concourse_cluster
#    Scenario: gprecoverseg should use the same setting for data_checksums for a full recovery
#        Given the database is running
#        And results of the sql "show data_checksums" db "template1" are stored in the context
#        # cause a full recovery AFTER a failure on a remote primary
#        And all the segments are running
#        And the segments are synchronized
#        And the information of a "mirror" segment on a remote host is saved
#        And the information of the corresponding primary segment on a remote host is saved
#        When user kills a "primary" process with the saved information
#        And user can start transactions
#        Then the saved "primary" segment is marked down in config
#        When the user runs "gprecoverseg -F -a"
#        Then gprecoverseg should return a return code of 0
#        And gprecoverseg should print "Heap checksum setting is consistent between master and the segments that are candidates for recoverseg" to stdout
#        When the user runs "gprecoverseg -ra"
#        Then gprecoverseg should return a return code of 0
#        And gprecoverseg should print "Heap checksum setting is consistent between master and the segments that are candidates for recoverseg" to stdout
#        And all the segments are running
#        And the segments are synchronized
#        # validate the new segment has the correct setting by getting admin connection to that segment
#        Then the saved primary segment reports the same value for sql "show data_checksums" db "template1" as was saved
#
#    @concourse_cluster
#    Scenario: incremental recovery works with tablespaces on a multi-host environment
#        Given the database is running
#          And a tablespace is created with data
#          And user stops all primary processes
#          And user can start transactions
#         When the user runs "gprecoverseg -a"
#         Then gprecoverseg should return a return code of 0
#          And the segments are synchronized
#          And the tablespace is valid
#
#        Given another tablespace is created with data
#         When the user runs "gprecoverseg -ra"
#         Then gprecoverseg should return a return code of 0
#          And the segments are synchronized
#          And the tablespace is valid
#          And the other tablespace is valid
#
#    @concourse_cluster
#    Scenario: full recovery works with tablespaces on a multi-host environment
#        Given the database is running
#          And a tablespace is created with data
#          And user stops all primary processes
#          And user can start transactions
#         When the user runs "gprecoverseg -a -F"
#         Then gprecoverseg should return a return code of 0
#          And the segments are synchronized
#          And the tablespace is valid
#
#        Given another tablespace is created with data
#         When the user runs "gprecoverseg -ra"
#         Then gprecoverseg should return a return code of 0
#          And the segments are synchronized
#          And the tablespace is valid
#          And the other tablespace is valid
#
#    @concourse_cluster
#    Scenario: moving mirror to a different host must work
#        Given the database is running
#          And all the segments are running
#          And the segments are synchronized
#          And the information of a "mirror" segment on a remote host is saved
#          And the information of the corresponding primary segment on a remote host is saved
#         When user kills a "mirror" process with the saved information
#          And user can start transactions
#         Then the saved "mirror" segment is marked down in config
#         When the user runs "gprecoverseg -a -p mdw"
#         Then gprecoverseg should return a return code of 0
#         When user kills a "primary" process with the saved information
#          And user can start transactions
#         Then the saved "primary" segment is marked down in config
#         When the user runs "gprecoverseg -a"
#         Then gprecoverseg should return a return code of 0
#          And all the segments are running
#          And the segments are synchronized
#         When the user runs "gprecoverseg -ra"
#         Then gprecoverseg should return a return code of 0
#          And all the segments are running
#          And the segments are synchronized
#
#    @concourse_cluster
#    Scenario: recovering a host with tablespaces succeeds
#        Given the database is running
#
#          # Add data including tablespaces
#          And a tablespace is created with data
#          And database "gptest" exists
#          And the user connects to "gptest" with named connection "default"
#          And the user runs psql with "-c 'CREATE TABLE public.before_host_is_down (i int) DISTRIBUTED BY (i)'" against database "gptest"
#          And the user runs psql with "-c 'INSERT INTO public.before_host_is_down SELECT generate_series(1, 10000)'" against database "gptest"
#          And the "public.before_host_is_down" table row count in "gptest" is saved
#
#          # Stop one of the nodes as if for hardware replacement and remove any traces as if it was a new node.
#          # Recoverseg requires the host being restored have the same hostname.
#          And the user runs "gpstop -a --host sdw1"
#          And gpstop should return a return code of 0
#          And the user runs remote command "rm -rf /data/gpdata/*" on host "sdw1"
#          And user can start transactions
#
#          # Add data after one of the nodes is down for maintenance
#          And database "gptest" exists
#          And the user connects to "gptest" with named connection "default"
#          And the user runs psql with "-c 'CREATE TABLE public.after_host_is_down (i int) DISTRIBUTED BY (i)'" against database "gptest"
#          And the user runs psql with "-c 'INSERT INTO public.after_host_is_down SELECT generate_series(1, 10000)'" against database "gptest"
#          And the "public.after_host_is_down" table row count in "gptest" is saved
#
#          # restore the down node onto a node with the same hostname
#          When the user runs "gprecoverseg -a -p sdw1"
#          Then gprecoverseg should return a return code of 0
#          And all the segments are running
#          And user can start transactions
#          And the user runs "gprecoverseg -ra"
#          And gprecoverseg should return a return code of 0
#          And all the segments are running
#          And the segments are synchronized
#          And user can start transactions
#
#          # verify the data
#          And the tablespace is valid
#          And the row count from table "public.before_host_is_down" in "gptest" is verified against the saved data
#          And the row count from table "public.after_host_is_down" in "gptest" is verified against the saved data
