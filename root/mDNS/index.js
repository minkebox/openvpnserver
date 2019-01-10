#! /usr/bin/node

const mDNS = require('./mdns');

const EXTERNAL_IFACE = process.argv[2];
const INTERNAL_IFACE = process.argv[3];

const mDNSExternal = mDNS.create(EXTERNAL_IFACE);
const mDNSInternal = mDNS.create(INTERNAL_IFACE);

function transform(pkt) {
  pkt.answers = pkt.answers.reduce((acc, answer) => {
    switch (answer.type) {
      case 'AAAA':
        break;
      case 'A':
        if (!this.netblock.contains(answer.data)) {
          answer.data = this.interface.address;
        }
        acc.push(answer)
        break;
      default:
        acc.push(answer);
        break;
    }
    return acc;
  }, []);
  this.send(pkt);
}

mDNSExternal.transform = transform;
mDNSInternal.transform = transform;

mDNSExternal.on('packet', (pkt) => {
  mDNSInternal.transform(pkt);
});

mDNSInternal.on('packet', (pkt) => {
  mDNSExternal.transform(pkt);
});
