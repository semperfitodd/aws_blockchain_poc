'use strict';

const shim = require('fabric-shim');
const util = require('util');

class contract {
  async Init(stub) {
    console.info('========= Init =========');
    return shim.success();
  }

  async Invoke(stub) {
    let ret = stub.getFunctionAndParameters();
    console.info(ret);

    let method = this[ret.fcn];
    if (!method) {
      console.error('No function of name:' + ret.fcn + ' found');
      throw new Error('Received unknown function ' + ret.fcn + ' invocation');
    }
    try {
      let payload = await method(stub, ret.params);
      return shim.success(payload);
    } catch (err) {
      console.log(err);
      return shim.error(err);
    }
  }

  async hello(stub, args) {
    if (args.length != 1) {
      throw new Error('Incorrect number of arguments. Expecting 1');
    }

    let name = args[0];
    let helloMessage = util.format('Hello, %s!', name);

    return Buffer.from(helloMessage);
  }
}

shim.start(new contract());
