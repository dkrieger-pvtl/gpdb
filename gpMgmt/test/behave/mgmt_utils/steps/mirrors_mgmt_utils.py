from behave import given, when, then

from test.behave_utils.utils import *

# This file contains steps for gpaddmirrors and gpmovemirrors tests

def _get_mirror_count():
    with dbconn.connect(dbconn.DbURL(dbname='template1')) as conn:
        sql = """SELECT count(*) FROM gp_segment_configuration WHERE role='m'"""
        count_row = dbconn.execSQL(conn, sql).fetchone()
        return count_row[0]


def _generate_input_config(spread=False):
    datadir_config = _write_datadir_config()

    mirror_config_output_file = "/tmp/test_gpaddmirrors.config"
    cmd_str = 'gpaddmirrors -a -o %s -m %s' % (mirror_config_output_file, datadir_config)
    if spread:
        cmd_str += " -s"
    Command('generate mirror_config file', cmd_str).run(validateAfter=True)

    return mirror_config_output_file


def do_write(template, config_file_path):
    mirror_data_dir = make_data_directory_called('mirror')

    with open(config_file_path, 'w') as fp:
        contents = template.format(mirror_data_dir)
        fp.write(contents)


def _write_datadir_config():
    datadir_config = '/tmp/gpaddmirrors_datadir_config'

    template = """
{0}
{0}
"""

    do_write(template, datadir_config)

    return datadir_config


def _write_datadir_config_for_three_mirrors():
    datadir_config='/tmp/gpaddmirrors_datadir_config'

    template = """
{0}
{0}
{0}
"""

    do_write(template, datadir_config)

    return datadir_config


def add_three_mirrors(context):
    datadir_config = _write_datadir_config_for_three_mirrors()
    mirror_config_output_file = "/tmp/test_gpaddmirrors.config"

    cmd_str = 'gpaddmirrors -o %s -m %s' % (mirror_config_output_file, datadir_config)
    Command('generate mirror_config file', cmd_str).run(validateAfter=True)

    cmd = Command('gpaddmirrors ', 'gpaddmirrors -a -i %s ' % mirror_config_output_file)
    cmd.run(validateAfter=True)


def add_mirrors(context):
    context.mirror_config = _generate_input_config()

    cmd = Command('gpaddmirrors ', 'gpaddmirrors -a -i %s ' % context.mirror_config)
    cmd.run(validateAfter=True)


def make_data_directory_called(data_directory_name):
    mdd_parent_parent = os.path.realpath(
        os.getenv("MASTER_DATA_DIRECTORY") + "../../../")
    mirror_data_dir = os.path.join(mdd_parent_parent, data_directory_name)
    if not os.path.exists(mirror_data_dir):
        os.mkdir(mirror_data_dir)
    return mirror_data_dir


@then('verify the database has mirrors')
def impl(context):
    if _get_mirror_count() == 0:
        raise Exception('No mirrors found')


@given('gpaddmirrors adds mirrors')
@when('gpaddmirrors adds mirrors')
@then('gpaddmirrors adds mirrors')
def impl(context):
    add_mirrors(context)


@given('gpaddmirrors adds mirrors with temporary data dir')
def impl(context):
    context.mirror_config = _generate_input_config()
    mdd = os.getenv('MASTER_DATA_DIRECTORY', "")
    del os.environ['MASTER_DATA_DIRECTORY']
    try:
        cmd = Command('gpaddmirrors ', 'gpaddmirrors -a -i %s -d %s' % (context.mirror_config, mdd))
        cmd.run(validateAfter=True)
    finally:
        os.environ['MASTER_DATA_DIRECTORY'] = mdd


@given('gpaddmirrors adds mirrors in spread configuration')
def impl(context):
    context.mirror_config = _generate_input_config(spread=True)

    cmd = Command('gpaddmirrors ', 'gpaddmirrors -a -i %s ' % context.mirror_config)
    cmd.run(validateAfter=True)


@then('save the gparray to context')
def impl(context):
    gparray = GpArray.initFromCatalog(dbconn.DbURL())
    context.gparray = gparray


@then('mirror hostlist matches the one saved in context')
def impl(context):
    gparray = GpArray.initFromCatalog(dbconn.DbURL())
    old_content_to_host = {}
    curr_content_to_host = {}

    # Map content IDs to hostnames for every mirror, for both the saved GpArray
    # and the current one.
    for (array, hostMap) in [(context.gparray, old_content_to_host), (gparray, curr_content_to_host)]:
        for host in array.get_hostlist(includeMaster=False):
            for mirror in array.get_list_of_mirror_segments_on_host(host):
                hostMap[mirror.getSegmentContentId()] = host

    if len(curr_content_to_host) != len(old_content_to_host):
        raise Exception("Number of mirrors doesn't match between old and new clusters")

    for key in old_content_to_host.keys():
        if curr_content_to_host[key] != old_content_to_host[key]:
            raise Exception("Mirror host doesn't match for content %s (old host=%s) (new host=%s)"
            % (key, old_content_to_host[key], curr_content_to_host[key]))

@then('verify that mirror segments are in "{mirror_config}" configuration')
def impl(context, mirror_config):
    if mirror_config not in ["group", "spread"]:
        raise Exception('"%s" is not a valid mirror configuration for this step; options are "group" and "spread".')

    gparray = GpArray.initFromCatalog(dbconn.DbURL())
    host_list = gparray.get_hostlist(includeMaster=False)

    primary_to_mirror_host_map = {}
    primary_content_map = {}
    # Create a map from each host to the hosts holding the mirrors of all the
    # primaries on the original host, e.g. the primaries for contents 0 and 1
    # are on sdw1, the mirror for content 0 is on sdw2, and the mirror for
    # content 1 is on sdw4, then primary_content_map[sdw1] = [sdw2, sdw4]
    for segmentPair in gparray.segmentPairs:
        primary_host, mirror_host = segmentPair.get_hosts()
        pair_content = segmentPair.primaryDB.content

        # Regardless of mirror configuration, a primary should never be mirrored on the same host
        if primary_host == mirror_host:
            raise Exception('Host %s has both primary and mirror for content %d' % (primary_host, pair_content))

        primary_content_map[primary_host] = pair_content
        if primary_host not in primary_to_mirror_host_map:
            primary_to_mirror_host_map[primary_host] = set()
        primary_to_mirror_host_map[primary_host].add(mirror_host)


    if mirror_config == "spread":
        # In spread configuration, each primary on a given host has its mirror
        # on a different host, and no host has both the primary and the mirror
        # for a given segment.  For this to work, the cluster must have N hosts,
        # where N is 1 more than the number of segments on each host.
        # Thus, if the list of mirror hosts for a given primary host consists
        # of exactly the list of hosts in the cluster minus that host itself,
        # the mirrors in the cluster are correctly spread.

        for primary_host in primary_to_mirror_host_map:
            mirror_host_set = primary_to_mirror_host_map[primary_host]

            other_host_set = set(host_list)
            other_host_set.remove(primary_host)
            if other_host_set != mirror_host_set:
                raise Exception('Expected primaries on %s to be mirrored to %s, but they are mirrored to %s' %
                        (primary_host, other_host_set, mirror_host_set))
    elif mirror_config == "group":
        # In group configuration, all primaries on a given host are mirrored to
        # a single other host.
        # Thus, if the list of mirror hosts for a given primary host consists
        # of a single host, and that host is not the same as the primary host,
        # the mirrors in the cluster are correctly grouped.

        for primary_host in primary_to_mirror_host_map:
            num_mirror_hosts = len(primary_to_mirror_host_map[primary_host])

            if num_mirror_hosts != 1:
                raise Exception('Expected primaries on %s to all be mirrored to the same host, but they are mirrored to %d different hosts' %
                        (primary_host, num_mirror_hosts))

@given('a sample gpmovemirrors input file is created in "{mirror_config}" configuration')
def impl(context, mirror_config):
    if mirror_config not in ["group", "spread"]:
        raise Exception('"%s" is not a valid mirror configuration for this step; options are "group" and "spread".')
    # The format for a line in the gpmovemirrors input file is
    #   <old_address>:<port>:<datadir> <new_address>:<port>:<datadir>
    # Port numbers and addresses are hardcded to TestCluster values, assuming a 3-host 2-segment cluster.
    input_filename = "/tmp/gpmovemirrors_input_%s" % mirror_config
    line_template = "%s:%d:/tmp/gpmovemirrors/data/mirror/gpseg%d %s:%d:/tmp/gpmovemirrors/data/mirror/gpseg%d_moved\n"
    # Group mirroring (TestCluster default): sdw1 mirrors to sdw2, sdw2 mirrors to sdw3, sdw3 mirrors to sdw2
    group_port_map = {0: 21500, 1: 21501, 2: 21500, 3: 21501, 4: 21500, 5: 21501}
    group_address_map = {0: "sdw2", 1: "sdw2", 2: "sdw3", 3: "sdw3", 4: "sdw1", 5: "sdw1"}
    # Spread mirroring: each host mirrors one primary to each of the other two hosts
    spread_port_map = {0: 21500, 1: 21500, 2: 21500, 3: 21501, 4: 21501, 5: 21501}
    spread_address_map = {0: "sdw2", 1: "sdw3", 2: "sdw1", 3: "sdw3", 4: "sdw1", 5: "sdw2"}
    # The mirrors for contents 0 and 3 are excluded from the above maps because they are the same in either configuration
    with open(input_filename, "w") as fd:
        for content in [1,2,4,5]:
            if mirror_config == "spread":
                old_port = group_port_map[content]
                old_address = group_address_map[content]
                new_port = spread_port_map[content]
                new_address = spread_address_map[content]
            else:
                old_port = spread_port_map[content]
                old_address = spread_address_map[content]
                new_port = group_port_map[content]
                new_address = group_address_map[content]
            fd.write(line_template % (old_address, old_port, content, new_address, new_port, content))
        fd.flush()
