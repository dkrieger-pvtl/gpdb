import abc

from gppylib.commands import unix
from gppylib.mainUtils import ExceptionNoStackTraceNeeded
from gppylib.operations.detect_unreachable_hosts import get_unreachable_segment_hosts
from gppylib.parseutils import line_reader, check_values, canonicalize_address
from gppylib.utils import normalizeAndValidateInputPath
from gppylib.gparray import GpArray

class MirrorBuilderFactory:
    @staticmethod
    def instance(gpArray, config_file=None, new_hosts=[], logger=None):
        if config_file:
            return ConfigFileMirrorBuilder(gpArray, config_file)

        return GpArrayMirrorBuilder(gpArray, new_hosts, logger)


class MirrorBuilder(abc.ABC):
    def __init__(self, gpArray):
        self.gpArray = gpArray
        self.recoveryTriples = []

    @abc.abstractmethod
    def getMirrorTriples(self):
        pass

class GpArrayMirrorBuilder(MirrorBuilder):
    def __init__(self, gpArray, newHosts, logger):
        super().__init__(gpArray)
        self.newHosts = []
        if newHosts:
            self.newHosts = newHosts[:]
        self.logger = logger

    def getMirrorTriples(self):
        segments = self.gpArray.getSegDbList()

        failedSegments = [seg for seg in segments if seg.isSegmentDown()]
        peersForFailedSegments = _findAndValidatePeersForFailedSegments(self.gpArray, failedSegments)

        # Dictionaries used for building mapping to new hosts
        recoverAddressMap = {}
        recoverHostMap = {}
        interfaceHostnameWarnings = []

        recoverHostIdx = 0

        if self.newHosts and len(self.newHosts) > 0:
            for seg in failedSegments:
                segAddress = seg.getSegmentAddress()
                segHostname = seg.getSegmentHostName()

                # Haven't seen this hostname before so we put it on a new host
                if segHostname not in recoverHostMap:
                    try:
                        recoverHostMap[segHostname] = self.newHosts[recoverHostIdx]
                    except:
                        # If we get here, not enough hosts were specified in the -p option.  Need 1 new host
                        # per 1 failed host.
                        raise Exception('Not enough new recovery hosts given for recovery.')
                    recoverHostIdx += 1

                destAddress = recoverHostMap[segHostname]
                destHostname = recoverHostMap[segHostname]

                # Save off the new host/address for this address.
                recoverAddressMap[segAddress] = (destHostname, destAddress)

            new_recovery_hosts = [destHostname for (destHostname, destAddress) in recoverAddressMap.values()]
            unreachable_hosts = get_unreachable_segment_hosts(new_recovery_hosts, len(new_recovery_hosts))
            if unreachable_hosts:
                raise ExceptionNoStackTraceNeeded("Cannot recover. The recovery target host %s is unreachable." % (
                    ' '.join(map(str, unreachable_hosts))))

            for key in list(recoverAddressMap.keys()):
                (newHostname, newAddress) = recoverAddressMap[key]
                try:
                    unix.Ping.local("ping new address", newAddress)
                except:
                    # new address created is invalid, so instead use same hostname for address
                    self.logger.info("Ping of %s failed, Using %s for both hostname and address.", newAddress,
                                     newHostname)
                    newAddress = newHostname
                recoverAddressMap[key] = (newHostname, newAddress)

            if len(self.newHosts) != recoverHostIdx:
                interfaceHostnameWarnings.append("The following recovery hosts were not needed:")
                for h in self.newHosts[recoverHostIdx:]:
                    interfaceHostnameWarnings.append("\t%s" % h)

        portAssigner = _PortAssigner(self.gpArray)

        for i in range(len(failedSegments)):

            failoverSegment = None
            failedSegment = failedSegments[i]
            liveSegment = peersForFailedSegments[i]

            if self.newHosts and len(self.newHosts) > 0:
                (newRecoverHost, newRecoverAddress) = recoverAddressMap[failedSegment.getSegmentAddress()]
                # these two lines make it so that failoverSegment points to the object that is registered in gparray
                failoverSegment = failedSegment
                failedSegment = failoverSegment.copy()
                failoverSegment.unreachable = False  # recover to a new host; it is reachable as checked above.
                failoverSegment.setSegmentHostName(newRecoverHost)
                failoverSegment.setSegmentAddress(newRecoverAddress)
                port = portAssigner.findAndReservePort(newRecoverHost, newRecoverAddress)
                failoverSegment.setSegmentPort(port)
            else:
                # we are recovering to the same host("in place") and hence
                # cannot recover if the failed segment is unreachable.
                # This is equivalent to failoverSegment.unreachable that we should be doing here but
                # due to how the code is factored failoverSegment is None here.
                if failedSegment.unreachable:
                    continue

            self.recoveryTriples.append((failedSegment, liveSegment, failoverSegment))

        return self.recoveryTriples


class ConfigFileMirrorBuilder(MirrorBuilder):
    def __init__(self, gpArray, config_file):
        super().__init__(gpArray)
        self.config_file = config_file
        self.rows = self._parseConfigFile(self.config_file)

    @staticmethod
    def _parseConfigFile(config_file):
        rows = []
        with open(config_file) as f:
            for lineno, line in line_reader(f):

                groups = line.split()  # NOT line.split(' ') due to MPP-15675
                if len(groups) not in [1, 2]:
                    msg = "line %d of file %s: expected 1 or 2 groups but found %d" % (lineno, config_file, len(groups))
                    raise ExceptionNoStackTraceNeeded(msg)
                parts = groups[0].split('|')
                if len(parts) != 3:
                    msg = "line %d of file %s: expected 3 parts on failed segment group, obtained %d" % (
                        lineno, config_file, len(parts))
                    raise ExceptionNoStackTraceNeeded(msg)
                address, port, datadir = parts
                check_values(lineno, address=address, port=port, datadir=datadir)
                row = {
                    'failedAddress': address,
                    'failedPort': port,
                    'failedDataDirectory': datadir,
                    'lineno': lineno
                }
                if len(groups) == 2:
                    parts2 = groups[1].split('|')
                    if len(parts2) != 3:
                        msg = "line %d of file %s: expected 3 parts on new segment group, obtained %d" % (
                            lineno, config_file, len(parts2))
                        raise ExceptionNoStackTraceNeeded(msg)
                    address2, port2, datadir2 = parts2
                    check_values(lineno, address=address2, port=port2, datadir=datadir2)
                    row.update({
                        'newAddress': address2,
                        'newPort': port2,
                        'newDataDirectory': datadir2
                    })

                rows.append(row)

        return rows

    def getMirrorTriples(self):
        failedSegments = []
        failoverSegments = []
        for row in self.rows:
            # find the failed segment
            failedAddress = row['failedAddress']
            failedPort = row['failedPort']
            failedDataDirectory = normalizeAndValidateInputPath(row['failedDataDirectory'],
                                                                "config file", row['lineno'])
            failedSegment = None
            for segment in self.gpArray.getDbList():
                if (segment.getSegmentAddress() == failedAddress
                        and str(segment.getSegmentPort()) == failedPort
                        and segment.getSegmentDataDirectory() == failedDataDirectory):

                    if failedSegment is not None:
                        # this could be an assertion -- configuration should not allow multiple entries!
                        raise Exception(("A segment to recover was found twice in configuration.  "
                                         "This segment is described by address|port|directory '%s|%s|%s' "
                                         "on the input line: %s") %
                                        (failedAddress, failedPort, failedDataDirectory, row['lineno']))
                    failedSegment = segment

            if failedSegment is None:
                raise Exception("A segment to recover was not found in configuration.  " \
                                "This segment is described by address|port|directory '%s|%s|%s' on the input line: %s" %
                                (failedAddress, failedPort, failedDataDirectory, row['lineno']))

            failoverSegment = None
            if "newAddress" in row:
                """
                When the second set was passed, the caller is going to tell us to where we need to failover, so
                  build a failover segment
                """
                # these two lines make it so that failoverSegment points to the object that is registered in gparray
                failoverSegment = failedSegment
                failedSegment = failoverSegment.copy()

                address = row["newAddress"]
                try:
                    port = int(row["newPort"])
                except ValueError:
                    raise Exception('Config file format error, invalid number value in line: %s' % (row['lineno']))

                dataDirectory = normalizeAndValidateInputPath(row["newDataDirectory"], "config file",
                                                              row['lineno'])
                # FIXME: hostname probably should not be address, but to do so, "hostname" should be added to gpaddmirrors config file
                # FIXME: This appears identical to __getMirrorsToBuildFromConfigFilein clsAddMirrors
                hostName = address

                # now update values in failover segment
                failoverSegment.setSegmentAddress(address)
                failoverSegment.setSegmentHostName(hostName)
                failoverSegment.setSegmentPort(port)
                failoverSegment.setSegmentDataDirectory(dataDirectory)

            # this must come AFTER the if check above because failedSegment can be adjusted to
            #   point to a different object
            failedSegments.append(failedSegment)
            failoverSegments.append(failoverSegment)

        peersForFailedSegments = _findAndValidatePeersForFailedSegments(self.gpArray, failedSegments)

        for index, failedSegment in enumerate(failedSegments):
            peerForFailedSegment = peersForFailedSegments[index]

            if failedSegment.unreachable:
                continue

            self.recoveryTriples.append((failedSegment, peerForFailedSegment, failoverSegments[index]))

        return self.recoveryTriples

# FIXME: I removed the getProgramName() from the exception here but does not seem important...
def _findAndValidatePeersForFailedSegments(gpArray, failedSegments):
    dbIdToPeerMap = gpArray.getDbIdToPeerMap()
    peersForFailedSegments = [dbIdToPeerMap.get(seg.getSegmentDbId()) for seg in failedSegments]

    for i in range(len(failedSegments)):
        peer = peersForFailedSegments[i]
        if peer is None:
            raise Exception("No peer found for dbid %s" % failedSegments[i].getSegmentDbId())
        elif peer.isSegmentDown():
            raise Exception(
                "Both segments for content %s are down; Try restarting Greenplum DB and running the program again." %
                (peer.getSegmentContentId()))
    return peersForFailedSegments

class _PortAssigner:
    """
    Used to assign new ports to segments on a host

    Note that this could be improved so that we re-use ports for segments that are being recovered but this
      does not seem necessary.

    """

    MAX_PORT_EXCLUSIVE = 65536

    def __init__(self, gpArray):
        #
        # determine port information for recovering to a new host --
        #   we need to know the ports that are in use and the valid range of ports
        #
        segments = gpArray.getDbList()
        ports = [seg.getSegmentPort() for seg in segments if seg.isSegmentQE()]
        if len(ports) > 0:
            self.__minPort = min(ports)
        else:
            raise Exception("No segment ports found in array.")
        self.__usedPortsByHostName = {}

        byHost = GpArray.getSegmentsByHostName(segments)
        for hostName, segments in byHost.items():
            usedPorts = self.__usedPortsByHostName[hostName] = {}
            for seg in segments:
                usedPorts[seg.getSegmentPort()] = True

    def findAndReservePort(self, hostName, address):
        """
        Find a port not used by any postmaster process.
        When found, add an entry:  usedPorts[port] = True   and return the port found
        Otherwise raise an exception labeled with the given address
        """
        if hostName not in self.__usedPortsByHostName:
            self.__usedPortsByHostName[hostName] = {}
        usedPorts = self.__usedPortsByHostName[hostName]

        minPort = self.__minPort
        for port in range(minPort, _PortAssigner.MAX_PORT_EXCLUSIVE):
            if port not in usedPorts:
                usedPorts[port] = True
                return port
        raise Exception("Unable to assign port on %s" % address)
