@gpmovemirrors_single_host
Feature: Tests for gpmovemirrors that can be run on a single host
    
# to run these tests locally, you should have a local demo cluster created, and
# started.  This test will modify the original local demo cluster.  This test
# will, as a side effect, destroy the current contents of /tmp/gpmovemirrors and
# replace it with data as used in this test.
    
    
    @newtestme1
    Scenario: gpmovemirrors fails with totally malformed input file
        Given the gpmovemirrors context is reset
        And a standard local demo cluster is running
        And a working directory of the test as '/tmp/gpmovemirrors' with mode '0700'
        And the working directory is set to that test working directory
        And a 'malformed' gpmovemirrors file is created in that working directory
        And the user runs gpmovemirrors with the setup context
        Then gpmovemirrors should return a return code of 3

    @newtestme1
    Scenario: gpmovemirrors fails with bad host in input file
        Given the gpmovemirrors context is reset
        And a standard local demo cluster is running
        And a working directory of the test as '/tmp/gpmovemirrors' with mode '0700'
        And the working directory is set to that test working directory
        And a 'badhost' gpmovemirrors file is created in that working directory
        And the user runs gpmovemirrors with the setup context
        Then gpmovemirrors should return a return code of 3

    @newtestme1
    Scenario: gpmovemirrors can change the location of mirrors within a single host
        Given the gpmovemirrors context is reset
        And a standard local demo cluster is created
        And a working directory of the test as '/tmp/gpmovemirrors' with mode '0700'
        And the working directory is set to that test working directory
        And a 'good' gpmovemirrors file is created in that working directory
        And the user runs gpmovemirrors with the setup context
        Then gpmovemirrors should return a return code of 0
        And verify the database has mirrors
        And all the segments are running
        And the segments are synchronized
        And save the gparray to context
        And verify that mirrors are recognized after a restart

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

    #Scenario: gpmovemirrors can move mirrors in batches
    #    Given a working directory of the test as '/tmp/gpmovemirrors'
    #    And the database is killed on hosts "mdw,sdw1,sdw2,sdw3"
    #    And a cluster is created with mirrors on "mdw" and "sdw1, sdw2, sdw3"
    #    And a sample gpmovemirrors input file is created in "spread" configuration
    #    And the user runs "gpmovemirrors --input=/tmp/gpmovemirrors_input_group -B 1"
    #    Then gpmovemirrors should return a return code of 0
    #    And gpmovemirrors should print "TBD" to stdout
