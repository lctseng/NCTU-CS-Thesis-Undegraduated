#!/usr/bin/python

"""
Create a network and start sshd(8) on each host.

While something like rshd(8) would be lighter and faster,
(and perfectly adequate on an in-machine network)
the advantage of running sshd is that scripts can work
unchanged on mininet and hardware.

In addition to providing ssh access to hosts, this example
demonstrates:

- creating a convenience function to construct networks
- connecting the host network to the root namespace
- running server processes (sshd in this case) on hosts
"""

import sys

from mininet.net import Mininet
from mininet.cli import CLI
from mininet.log import lg
from mininet.node import Node
from mininet.topolib import TreeTopo
from mininet.topo import LinearTopo
from mininet.util import waitListening
from mininet.node import RemoteController
from mininet.link import TCLink
from mininet.topo import Topo

class SimpleTopo( Topo ):
    "Simple topology example."
    def __init__( self ):
        "Create custom topo."
        # Initialize topology
        Topo.__init__( self )
        # Switch
        s1 = self.addSwitch("s1")
        # Host
        h1 = self.addHost("h1")
        h2 = self.addHost("h2")
        h3 = self.addHost("h3")
        # Link
        self.addLink(s1,h1)
        self.addLink(s1,h2)
        self.addLink(s1,h3)

class FlowBaseTopo( Topo ):
    "Simple topology example."
    def __init__( self ):
        "Create custom topo."
        # Initialize topology
        Topo.__init__( self )
        # Switch
        s1 = self.addSwitch("s1")
        # Host
        h1 = self.addHost("h1")
        h2 = self.addHost("h2")
        h3 = self.addHost("h3")
        h4 = self.addHost("h4")
        h5 = self.addHost("h5")
        # Link
        self.addLink(s1,h1)
        self.addLink(s1,h2)
        self.addLink(s1,h3)
        self.addLink(s1,h4)
        self.addLink(s1,h5)


class SwitchSpeedControlTopo( Topo ):
    "Simple topology example."
    def __init__( self ):
        "Create custom topo."
        # Initialize topology
        Topo.__init__( self )
        # Switch
        s1 = self.addSwitch("s1")
        s2 = self.addSwitch("s2")
        # Host
        h1 = self.addHost("h1") # receiver 1
        h2 = self.addHost("h2") # s1
        h3 = self.addHost("h3") # s2
        h4 = self.addHost("h4") # s2
        h5 = self.addHost("h5") # s1
        h6 = self.addHost("h6") # receiver 2

        # Link
        self.addLink(s1,h1) # queue here
        self.addLink(s1,s2) # switch for indirect host, s2 queue here
        self.addLink(s1,h3) # direct host 1
        self.addLink(s1,h5) # direct host 2
        self.addLink(s1,h6) # direct receiver 2
        self.addLink(s2,h2)
        self.addLink(s2,h4)


def CreateNet( **kwargs ):
    topo = LinearTopo(k=4,n=2)
    return Mininet( topo, **kwargs )

def connectToRootNS( network, switch, ip, routes ):
    """Connect hosts to root namespace via switch. Starts network.
      network: Mininet() network object
      switch: switch to connect to root namespace
      ip: IP address for root namespace node
      routes: host networks to route to"""
    # Create a node in root namespace and link to switch 0
    root = Node( 'root', inNamespace=False )
    intf = network.addLink( root, switch ).intf1
    root.setIP( ip, intf=intf )
    # Start network that now includes link to root namespace
    network.start()
    # Add routes from root ns to hosts
    for route in routes:
        root.cmd( 'route add -net ' + route + ' dev ' + str( intf ) )


def sshd( network, cmd='/sbin/sshd', opts='-D',
          ip='172.16.0.253/32', routes=None, switch=None ):
    """Start a network, connect it to root ns, and run sshd on all hosts.
       ip: root-eth0 IP address in root namespace (10.123.123.1/32)
       routes: Mininet host networks to route to (10.0/24)
       switch: Mininet switch to connect to root namespace (s1)"""
    if not switch:
        switch = network[ 's1' ]  # switch to use
    if not routes:
        routes = [ '172.16.0.0/24' ]
    connectToRootNS( network, switch, ip, routes )
    for host in network.hosts:
        host.cmd( cmd + ' ' + opts + '&' )
    print "*** Waiting for ssh daemons to start"
    for server in network.hosts:
        waitListening( server=server, port=22, timeout=5 )

    print
    print "*** Hosts are running sshd at the following addresses:"
    print
    for host in network.hosts:
        print host.name, host.IP()
    print
    print "*** Type 'exit' or control-D to shut down network"
    CLI( network )
    for host in network.hosts:
        host.cmd( 'kill %' + cmd )
    network.stop()

if __name__ == '__main__':
    lg.setLogLevel( 'info')
    net = CreateNet(link=TCLink, controller=None,ipBase='172.16.0.0/24')
    net.addController('c0',controller=RemoteController,ip='127.0.0.1',port=6653)
    # get sshd args from the command line or use default args
    # useDNS=no -u0 to avoid reverse DNS lookup timeout
    argvopts = ' '.join( sys.argv[ 1: ] ) if len( sys.argv ) > 1 else (
        '-D -o UseDNS=no -u0' )
    sshd( net, opts=argvopts )
