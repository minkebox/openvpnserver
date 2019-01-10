const EventEmitter = require('events').EventEmitter;
const Util = require('util');
const DnsPacket = require('dns-packet');
const Dgram = require('dgram');
const OS = require('os');
const Netmask = require('netmask').Netmask;

const MCAST_ADDRESS = '224.0.0.251';
const PORT = 5353;

function mDNS(iface) {
  EventEmitter.call(this);

  const interfaces = OS.networkInterfaces()[iface];
  if (!interfaces) {
    throw new Error();
  }
  const interface = interfaces.find(i => i.family === 'IPv4');
  if (!interface) {
    throw new Error();
  }
  const netblock = new Netmask(interface.cidr);

  this._socket = Dgram.createSocket({
    type: 'udp4',
    reuseAddr: true
  }, (msg, rinfo) => {
    if (netblock.contains(rinfo.address)) {
      try {
        this.emit('packet', DnsPacket.decode(msg));
      }
      catch (_) {
      }
    }
  });
  this._socket.bind(PORT, MCAST_ADDRESS, () => {
    this._socket.setMulticastTTL(255);
    this._socket.setMulticastLoopback(false);
    this._socket.addMembership(MCAST_ADDRESS, interface.address);
    this._socket.setMulticastInterface(interface.address);
  });

  this.send = (pkt) => {
    const msg = DnsPacket.encode(pkt);
    this._socket.send(msg, 0, msg.length, PORT, MCAST_ADDRESS);
  }

  this.interface = interface;
  this.netblock = netblock;
}

Util.inherits(mDNS, EventEmitter);

module.exports = {
  create: function(iface) {
    return new mDNS(iface);
  }
};
