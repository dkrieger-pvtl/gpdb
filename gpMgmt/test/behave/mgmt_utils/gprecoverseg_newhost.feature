@gprecoverseg_newhost
Feature: gprecoverseg tests involving migrating to a new host

########################### @concourse_cluster tests ###########################
# The @concourse_cluster tag denotes the scenario that requires a remote cluster
    @concourse_cluster
    Scenario Outline: gprecoverseg successfully fails over to a new host specifying <test_case>
      Given the database is running
      And all the segments are running
      And the segments are synchronized
      And the user runs gpconfig sets guc "wal_sender_timeout" with "15s"
      And the user runs "gpstop -air"
      And gprecoverseg_newhost test setups are done for "<test_case>" and "<recovery_file>"
      And the cluster configuration is saved "before"
      And segment hosts <down> are disconnected from the cluster and from the spare segment hosts <spare>
      And the cluster configuration reflects the desired state <down_sql>
      When the user runs <gprecoverseg_cmd>
      Then gprecoverseg should return a return code of 0
      And the cluster configuration is saved "<when>"
      And the "before" and "<when>" cluster configuration matches with the expected for gprecoverseg newhost
      And the mirrors replicate and fail over and back correctly
      And segment hosts <down> are reconnected to the cluster and to the spare segment hosts "<unused>"
      And the original cluster state is recreated to <down>
      And the cluster configuration is saved "after_recreation"
      And the "before" and "after_recreation" cluster configuration matches with the expected for gprecoverseg newhost
      Examples:
      | test_case  |  down        | spare       | unused |   when    | gprecoverseg_cmd                                | down_sql                                              | recovery_file           |
      | host_one   |  "sdw1"      | "sdw5,sdw6" | sdw6   | after_one | "gprecoverseg -a -F -p sdw5"                    | "hostname='sdw1' and status='u'"                      | none                    |
      | config_one |  "sdw1"      | "sdw5,sdw6" | sdw6   | after_one | "gprecoverseg -a -F -i /tmp/gprecoverseg_1.txt" | "hostname='sdw1' and status='u'"                      | /tmp/gprecoverseg_1.txt |
      | host_two   |  "sdw1,sdw3" | "sdw5,sdw6" | none   | after_two | "gprecoverseg -a -F -p sdw5,sdw6"               | "(hostname='sdw1' or hostname='sdw3') and status='u'" | none                    |
      | config_two |  "sdw1,sdw3" | "sdw5,sdw6" | none   | after_two | "gprecoverseg -a -F -i /tmp/gprecoverseg_2.txt" | "(hostname='sdw1' or hostname='sdw3') and status='u'" | /tmp/gprecoverseg_2.txt |

    @concourse_cluster
    Scenario: gprecoverseg failing test to keep cluster up
      Given this test does not exist so it fails
