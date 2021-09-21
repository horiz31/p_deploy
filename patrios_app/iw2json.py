import json
import logging
import os
import subprocess                   # needed for iw_client_call()
import sys

__version__ = '0.0.3'

logger = logging.getLogger(__name__)

def _doc():
    """
    """

def _parse_args():
    """Function to handle building and parsing of command line arguments"""
    from argparse import ArgumentParser, SUPPRESS
    #PARSER_TYPE_INT = int
    PARSER_TYPE_STR = str
    #PARSER_TYPE_FLOAT = float

    description = (
        'Command line for obtaining/parsing iw station dump output\n'
        '------------------------------------------------------------------------------\n')
    parser = ArgumentParser(description=description)

    # radio connection options
    parser.add_argument('-d', '--device', metavar='STR', default='wlan0', type=PARSER_TYPE_STR, help='Wireless device to parse station dump info from')
    parser.add_argument('-i', '--ident', metavar='PATH', default=None, type=PARSER_TYPE_STR, help='Path to .pem file for radio access')
    parser.add_argument(      '--radio', metavar='user@IP', default=None, type=PARSER_TYPE_STR, help='IPv4 address of radio')
    # test code options
    parser.add_argument('-q', '--quiet', action='store_true', default=False, help='Suppress progress and diagnostic (default: %(default)s')
    # boilerplate options
    parser.add_argument(      '--version', action='version', version='%(prog)s '+__version__)
    parser.add_argument(      '--debug', action='store_true', help=SUPPRESS)
    parser.add_argument(      '--test', action='store_true', default=False, help=SUPPRESS)
    # argument lists
    ##parser.add_argument('vars', nargs='*')

    options = parser.parse_args()
    if isinstance(options, tuple):
        args = options[0]
    else:
        args = options
    return args

def _parse_station(s):
    """Parse one station output.  Return MAC and key/value dictionary."""
    mac = s[len('Station '):-1].split('(')[0].strip()
    d = {}
    lines = s.split('\n')
    for line in lines[1:]:
        kv = line.split(':')
        if len(kv)<2:
            continue
        k = kv[0].strip()
        v = kv[1].strip().split(' ')[0]
        if len(k)>0:
            d[k] = v
    return mac, d

def _parse_info(s):
    """Parse info output.  Return DEV and key/value dictionary."""
    dev = s[len('Interface '):-1].split('(')[0].strip()
    d = {}
    lines = s.split('\n')
    for line in lines[1:]:
        kv = line.strip().split(' ')
        if len(kv)<2:
            continue
        k = kv[0].strip()
        v = kv[1].strip().split(' ')[0]
        if len(k)>0:
            d[k] = v
    return dev, d

def response_to_dictionary(r):
    """Parse iw station dump output into a dictionary indexed by MAC address."""
    d = {}
    end = start = -1
    while len(r)>len('Station'):
        try:
            start = r.index('Station',end+1)
            end = r.index('Station',start+1)
            mac, kv = _parse_station(r[start:end])
            d[mac] = kv
            end = end - 1
        except ValueError:
            if start >= 0:
                mac, kv = _parse_station(r[start:-1])
                d[mac] = kv
            break
    return d

def iw_client_call(d):
    """Perform remote procedure call to collect radio statistics from iw."""
    try:
        cmd = ['ssh','-i',d['ident'],d['radio'],'iw','dev',d['device'],'station','dump']
        logger.debug('{}'.format(cmd))
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE)
        out, err = proc.communicate()
        logger.debug('out={}'.format(out))
        rsp = response_to_dictionary(out.decode())
        cmd = ['ssh','-i',d['ident'],d['radio'],'iw','dev',d['device'],'info']
        logger.debug('{}'.format(cmd))
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE)
        out, err = proc.communicate()
        logger.debug('out={}'.format(out))
        _dev, info = _parse_info(out.decode())
        logger.debug('info={}'.format(info))
        rsp[d['device']] = info
        logger.debug('rsp={}'.format(rsp))
        return rsp, 0 if len(out)>0 else 1
    except Exception as e:
        logger.error(str(e))
        return {}, 1

# ---------------------------------------------------------------------------
# For command-line testing
# ---------------------------------------------------------------------------

_RETURN = '''
Station 00:30:1a:4e:97:f5 (on wlan0)
        inactive time:  10 ms
        rx bytes:       98665737
        rx packets:     107382
        tx bytes:       35149727
        tx packets:     123778
        tx retries:     13875
        tx failed:      115
        rx drop misc:   2313
        signal:         -77 [-78, -84] dBm
        signal avg:     -77 [-78, -84] dBm
        Toffset:        1051070479 us
        tx bitrate:     13.0 MBit/s MCS 1
        rx bitrate:     13.0 MBit/s MCS 1
        expected throughput:    6.682Mbps
        mesh llid:      0
        mesh plid:      0
        mesh plink:     ESTAB
        mesh local PS mode:     ACTIVE
        mesh peer PS mode:      ACTIVE
        mesh non-peer PS mode:  ACTIVE
        authorized:     yes
        authenticated:  yes
        associated:     yes
        preamble:       long
        WMM/WME:        yes
        MFP:            yes
        TDLS peer:      no
        DTIM period:    2
        beacon interval:100
        connected time: 494 seconds
Station 00:30:1a:4e:97:c8 (on wlan0)
        inactive time:  10 ms
        rx bytes:       116799003
        rx packets:     127903
        tx bytes:       44053942
        tx packets:     126335
        tx retries:     18782
        tx failed:      55
        rx drop misc:   1874
        signal:         -71 [-71, -83] dBm
        signal avg:     -71 [-71, -82] dBm
        Toffset:        820089498 us
        tx bitrate:     39.0 MBit/s MCS 4
        rx bitrate:     39.0 MBit/s MCS 4
        expected throughput:    20.49Mbps
        mesh llid:      0
        mesh plid:      0
        mesh plink:     ESTAB
        mesh local PS mode:     ACTIVE
        mesh peer PS mode:      ACTIVE
        mesh non-peer PS mode:  ACTIVE
        authorized:     yes
        authenticated:  yes
        associated:     yes
        preamble:       long
        WMM/WME:        yes
        MFP:            yes
        TDLS peer:      no
        DTIM period:    2
        beacon interval:100
        connected time: 489 seconds
'''

if __name__ == "__main__":

    # parse command line and make a dictionary out of it
    d = vars(_parse_args())
    if d['debug']:
        sys.stderr.write(json.dumps(d,indent=2)+'\n')
        level = logging.DEBUG
    else:
        level = logging.INFO
    logging.basicConfig(level=level)

    if all([d['ident'], d['radio']]) and not d['test']:
        x, e = iw_client_call(d)
    else:
        x = response_to_dictionary(_RETURN)

    sys.stdout.write(json.dumps(x, indent=2)+'\n')
