// Specifically request an abstraction for XfundToken
var XfundToken = artifacts.require("XfundToken");
var XfundCongress = artifacts.require("XfundCongress");
var cong;
var token;
var timeTravel = function (time) {
  return new Promise((resolve, reject) => {
    web3.currentProvider.sendAsync({
      jsonrpc: "2.0",
      method: "evm_increaseTime",
      params: [time], // 86400 is num seconds in day
      id: new Date().getTime()
    }, (err, result) => {
      if(err){ return reject(err) }
      return resolve(result)
    });
  });
}
var mineblock = function() {
  return new Promise((resolve, reject) => {
	web3.currentProvider.sendAsync({
  		jsonrpc: "2.0",
  		method: "evm_mine",
  		id: new Date().getTime()
	}, function(err, result) {
      if(err){ return reject(err) }
      return resolve(result)
    });
  });
};
var balance0;
var balance1;
var balance2;
var votes0;
var votes1;
var votes2;
// bytecode to transfer to accounts[3]
var byteCode = "0xa9059cbb000000000000000000000000821aea9a577a9b44299b9c15c88cf3087f3b55440000000000000000000000000000000000000000000000000000000000000003";
contract('XfundCongress', function(accounts) {

  it("should submit a proposal to transfer tokens", function() {
    var proposalDescription = "Send 3 tokens to account 2";
    return XfundCongress.deployed().then(function(instance) {
       cong = instance;
       return cong.newProposal(XfundToken.address, 0, 2, proposalDescription, byteCode,0);
    }).then(function() {
        return cong.proposals(0);
    }).then(function(proposal) {
        assert.equal(proposal[2],proposalDescription,"proposal description not set in proposal 0");
    });
  });

  it("should let member 0 vote on proposal 0", function() {
    return XfundCongress.deployed().then(function(instance) {
        cong = instance;
	    return timeTravel(300);
	}).then(function(res) {
		return mineblock();
	}).then(function(res) {
        return cong.vote(0,true,"Its a good proposal",{from:accounts[0]});
    }).then(function(id) {
        return cong.proposals(0);
    }).then(function(proposal) {
        assert.equal(proposal[8].toNumber(),1,"yeas not equal to 1");
        assert.equal(proposal[9].toNumber(),1,"totalVotes not equal to 1");
    });
  });

  it("should send tokens to congress", function() {
    return XfundToken.deployed().then(function(instance) {
        token = instance;
        return token.transfer(XfundCongress.address,1000);
    }).then(function() {
        return token.balanceOf(XfundCongress.address);
    }).then(function(bal) {
        assert.equal(bal.toNumber(),1000,"The Congress should own 1000 tokens");
    });
  });

  it("should let member 0 execute proposal 0 to transfer 3 XF17 from XfundCongress to account 3", function() {
    return XfundCongress.deployed().then(function(instance) {
        cong = instance;
	    return timeTravel(2*60+1);
	}).then(function(res) {
		return mineblock();
	}).then(function(res) {
        return cong.proposals(0);
    }).then(function(prop) {
        //console.log(web3.eth.getBlock("latest"));
        return token.balanceOf(cong.address);
    }).then(function(bal) {
        assert.equal(bal,1000,"congress balance should be 1000");
        return cong.checkProposalCode(0, XfundToken.address, 0, byteCode);
    }).then(function(res) {
        assert.equal(res,true,"proposal bytecode should check out");
        return cong.executeProposal(0,byteCode);
    }).then(function(res) {
        return cong.proposals(0);
    }).then(function(proposal) {
        assert.equal(proposal[6],true,"proposal should have passed");
        assert.equal(proposal[5],true,"proposal should have been executed");
        return token.balanceOf(XfundCongress.address);
    }).then(function(bal) {
        assert.equal(bal.toNumber(),997,"The Congress should now own 997 tokens");
        return token.balanceOf(accounts[3]);
    }).then(function(bal) {
        assert.equal(bal.toNumber(),3,"accounts[3] should now have 3 tokens");
    });
  });

  it("should vote account[3] for congress", function() {
    return XfundToken.deployed().then(function(instance) {
        token = instance;
        return token.transfer(accounts[2],1000);
    }).then(function() {
        return token.transfer(accounts[3],1000);
    }).then(function() {
        return token.voteOnCongress(accounts[3],{from:accounts[2]});
    }).then(function(res) {
        return token.votesReceived(accounts[3]);
    }).then(function(votes) {
        assert.equal(votes.toNumber(),1000,"accounts[3] should have 1000 votes");
    });
  });

  it("should change owner to Congress, then block", function() {
    return XfundCongress.deployed().then(function(instance) {
        cong = instance;
        return cong.transferOwnership(XfundCongress.address);
	}).then(function(res) {
        return cong.owner();
	}).then(function(owner) {
        assert.equal(owner,XfundCongress.address,"ownership not transferred");
        return cong.transferOwnership(XfundToken.address);
    }).then(assert.fail)
    .catch(function(err) {
        assert.include(err.message,'invalid opcode','cant change congress owner after already changed owner');
    });
  });

  var proposalDescription = "Transfer ownership of congress back to account[0]";
  it("should pass proposal to change ownership", function() {
    byteCode = '0xf2fde38b000000000000000000000000627306090abab3a6e1400e9345bc60c78a8bef57';
    return XfundCongress.deployed().then(function(instance) {
        cong = instance;
        return cong.newProposal(XfundCongress.address, 0, 10, proposalDescription, byteCode,0);
    }).then(function(prop) {
        //console.log(prop.logs[0]);
        return cong.proposals(1);
    }).then(function(proposal) {
        assert.equal(proposal[2],proposalDescription,"proposal description not set in proposal 0");
	    return timeTravel(250);
	}).then(function(res) {
		return mineblock();
	}).then(function(res) {
        return cong.vote(1,true,"Its a great proposal",{from:accounts[0]});
    }).then(function(id) {
        return cong.proposals(1);
    }).then(function(proposal) {
        assert.equal(proposal[8].toNumber(),1,"yeas not equal to 1");
        assert.equal(proposal[9].toNumber(),1,"totalVotes not equal to 1");
	    return timeTravel(12*60);
	}).then(function(res) {
		return mineblock();
	}).then(function(res) {
        return cong.executeProposal(1,byteCode);
    }).then(function(res) {
        return cong.proposals(1);
    }).then(function(proposal) {
        assert.equal(proposal[6],true,"proposal should have passed");
        assert.equal(proposal[5],true,"proposal should have been executed");
        return cong.owner();
    }).then(function(owner) {
        assert.equal(owner,accounts[0],"proposal should have passed");
    });
  });

  it("should NOT let accounts[3] join congress", function() {
    return XfundCongress.deployed().then(function(instance) {
        cong = instance;
        return cong.joinCongress("accounts[3]","",{from:accounts[3]});
	}).then(function(res) {
        return cong.getCongressSize();
	}).then(function(size) {
        assert.equal(size,1,"congress size should be 1");
    });
  });

  it("should increase congress size and then let accounts[3] join congress", function() {
    return XfundCongress.deployed().then(function(instance) {
        cong = instance;
        return cong.changeCongressSize(2);
	}).then(function(res) {
        return cong.getCongressSize();
	}).then(function(size) {
        assert.equal(size,2,"Congress should now have 2 members");
        return cong.joinCongress("accounts[3]","identity",{from:accounts[3]});
	}).then(function(res) {
        return cong.members(1);
	}).then(function(member) {
        assert.equal(member[0],"accounts[3]","new member is not accounts[3]");
    }).then(assert.fail)
    .catch(function(err) {
        assert.include(err.message,'invalid opcode','cant change congress owner after already changed owner');
    });
  });
});

