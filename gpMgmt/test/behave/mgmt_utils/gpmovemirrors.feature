@gpmovemirrors
Feature: Tests for gpmovemirrors
    
    # [ok] test for malformed input files
    # basic tests locally
    # figure out how to run on concourse too
    # maybe run on demo cluster on concourse too
    # factor the code to aggregate common parts
    
    #Scenario: gpmovemirrors can change the location of mirrors within a single host with multiple tablespaces
    #    Given a working directory of the test as '/tmp/gpmovemirrors'
    #    And an empty demo cluster is running with data directory '/tmp/gpmovemirrors/democluster'
    #    And we create multiple tablespaces within the cluster
    #    And a sample gpmovemirrors input file 'mydemocluster' exists
    #    And the user runs "gpmovemirrors --input=/tmp/mydemocluster"
    #    Then gpmovemirrors should return a return code of 0
    #    Then verify the database has mirrors
    #    And all the segments are running
    #    And the segments are synchronized
    #    And save the gparray to context
    #    And verify that mirror segments are in "round robin" configuration
    #    # Verify that mirrors are recognized after a restart
    #    When an FTS probe is triggered
    #    And the user runs "gpstop -a"
    #    And wait until the process "gpstop" goes down
    #    And the user runs "gpstart -a"
    #    And wait until the process "gpstart" goes down
    #    Then all the segments are running
    #    And the segments are synchronized
#
    #Scenario: gpmovemirrors can change from group mirroring to spread mirroring
    #    Given a working directory of the test as '/tmp/gpmovemirrors'
    #    And the database is killed on hosts "mdw,sdw1,sdw2,sdw3"
    #    And a cluster is created with mirrors on "mdw" and "sdw1, sdw2, sdw3"
    #    And a sample gpmovemirrors input file is created in "spread" configuration
    #    And the user runs "gpmovemirrors --input=/tmp/gpmovemirrors_input_spread"
    #    Then gpmovemirrors should return a return code of 0
    #    # Verify that mirrors are functional in the new configuration
    #    Then verify the database has mirrors
    #    And all the segments are running
    #    And the segments are synchronized
    #    And save the gparray to context
    #    And verify that mirror segments are in "spread" configuration
    #    # Verify that mirrors are recognized after a restart
    #    When an FTS probe is triggered
    #    And the user runs "gpstop -a"
    #    And wait until the process "gpstop" goes down
    #    And the user runs "gpstart -a"
    #    And wait until the process "gpstart" goes down
    #    Then all the segments are running
    #    And the segments are synchronized
#
    #Scenario: gpmovemirrors can change from spread mirroring to group mirroring
    #    Given a working directory of the test as '/tmp/gpmovemirrors'
    #    And the database is killed on hosts "mdw,sdw1,sdw2,sdw3"
    #    And a cluster is created with "spread" segment mirroring on "mdw" and "sdw1, sdw2, sdw3"
    #    And a sample gpmovemirrors input file is created in "group" configuration
    #    And the user runs "gpmovemirrors --input=/tmp/gpmovemirrors_input_group"
    #    Then gpmovemirrors should return a return code of 0
    #    # Verify that mirrors are functional in the new configuration
    #    Then verify the database has mirrors
    #    And all the segments are running
    #    And the segments are synchronized
    #    And save the gparray to context
    #    And verify that mirror segments are in "group" configuration
    #    # Verify that mirrors are recognized after a restart
    #    When an FTS probe is triggered
    #    And the user runs "gpstop -a"
    #    And wait until the process "gpstop" goes down
    #    And the user runs "gpstart -a"
    #    And wait until the process "gpstart" goes down
    #    Then all the segments are running
    #    And the segments are synchronized
    #    And the user runs "gpstop -aqM fast"
#
    #Scenario: gpmovemirrors can move mirrors in batches
    #    Given a working directory of the test as '/tmp/gpmovemirrors'
    #    And the database is killed on hosts "mdw,sdw1,sdw2,sdw3"
    #    And a cluster is created with mirrors on "mdw" and "sdw1, sdw2, sdw3"
    #    And a sample gpmovemirrors input file is created in "spread" configuration
    #    And the user runs "gpmovemirrors --input=/tmp/gpmovemirrors_input_group -B 1"
    #    Then gpmovemirrors should return a return code of 0
    #    And gpmovemirrors should print "TBD" to stdout
