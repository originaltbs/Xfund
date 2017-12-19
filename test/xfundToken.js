// Specifically request an abstraction for XfundToken
var XfundToken = artifacts.require("XfundToken");
var token;

var balance0;
var balance1;
var balance2;
var votes0;
var votes1;
var votes2;
contract('XfundToken', function(accounts) {

  it("should put 1e21 XF17 in the first account and 0 in account 2", function() {
    return XfundToken.deployed().then(function(instance) {
        token = instance;
        return token.balanceOf(accounts[0]);
    }).then(function(bal1) {
        assert.equal(bal1.valueOf(), Math.pow(10,21), "1e21 wasn't in accounts[0]");
        return token.balanceOf(accounts[1]);
    }).then(function(bal2) {
        assert.equal(bal2.valueOf(), 0, "0 wasn't in the accounts[1]");
    });
  });

  it("should tally a vote for congress and block new votes", function() {
    return XfundToken.deployed().then(function(instance) {
        token = instance;
        return token.votesReceived(accounts[1]);
    }).then(function(votes1) {
        assert.equal(votes1.valueOf(), 0, "accounts[1] votes total was not 0");
        return token.voteOnCongress(accounts[1]);
    }).then(function() {
        return token.balanceOf(accounts[0]);
    }).then(function(bal0) {
        balance0 = bal0;
        return token.votesReceived(accounts[1]);
    }).then(function(votes1) {
        assert.equal(votes1.valueOf(), balance0.valueOf(), "accounts[1] votes total was not accounts[0] balance");
        return token.voteOnCongress(accounts[2]);
    }).then(assert.fail)
    .catch(function(err) {
        assert.include(err.message,'invalid opcode','second votes should throw an error');
    });
  });

  it("should unvote vote for congress and then revote", function() {
    return XfundToken.deployed().then(function(instance) {
        token = instance;
        return token.votesReceived(accounts[1]);
    }).then(function(v1) {
        votes1 = v1;
        return token.balanceOf(accounts[0]);
    }).then(function(bal0) {
        balance0=bal0;
        assert.equal(votes1.valueOf(), balance0.valueOf(), "accounts[1] votes total was not balanceOf(accounts[0])");
        return token.unvoteCongress();
    }).then(function() {
        return token.votesReceived(accounts[1]);
    }).then(function(v1) {
        votes1 = v1;
        assert.equal(votes1.valueOf(), 0, "accounts[1] votes total was not 0");
    }).then(function() {
        return token.voteOnCongress(accounts[2]);
    }).then(function() {
        return token.votesReceived(accounts[2]);
    }).then(function(v2) {
        assert.equal(v2.valueOf(), balance0.valueOf(), "accounts[2] votes total was not accounts[0] balance");
    });
  });

  it("should send coin correctly", function() {
    var meta;

    // Get initial balances of first and second account.
    var account_one = accounts[0];
    var account_two = accounts[1];

    var account_one_starting_balance;
    var account_two_starting_balance;
    var account_one_ending_balance;
    var account_two_ending_balance;

    var amount = 10;

    return XfundToken.deployed().then(function(instance) {
      meta = instance;
      return meta.balanceOf.call(account_one);
    }).then(function(balance) {
      account_one_starting_balance = balance.toNumber();
      return meta.balanceOf.call(account_two);
    }).then(function(balance) {
      account_two_starting_balance = balance.toNumber();
      return meta.transfer(account_two, amount, {from: account_one});
    }).then(function() {
      return meta.balanceOf.call(account_one);
    }).then(function(balance) {
      account_one_ending_balance = balance.toNumber();
      balance0 = balance.toNumber();
      return meta.balanceOf.call(account_two);
    }).then(function(balance) {
      account_two_ending_balance = balance.toNumber();
      assert.equal(account_one_ending_balance, account_one_starting_balance - amount, "Amount wasn't correctly taken from the sender");
      assert.equal(account_two_ending_balance, account_two_starting_balance + amount, "Amount wasn't correctly sent to the receiver");
    });
  });

  it("should transfer votes along with balances", function() {
    return XfundToken.deployed().then(function(instance) {
        token = instance;
        return token.votesReceived(accounts[2]);
    }).then(function(v2) {
        assert.equal(v2.valueOf(), balance0.valueOf(), "accounts[2] votes total was not accounts[0] balance");
    });
  });

  it("should freeze account and prevent transfers", function() {
    return XfundToken.deployed().then(function(instance) {
        token = instance;
        return token.freezeAccount(accounts[0],true);
    }).then(function() {
        return token.transfer(accounts[1], 100);
    }).then(assert.fail)
    .catch(function(err) {
        assert.include(err.message,'invalid opcode','second votes should throw an error');
    });
  });

  it("should start with 0 inflation", function() {
    return XfundToken.deployed().then(function(instance) {
        token = instance;
        return token.getInflation();
    }).then(function(i) {
        assert.equal(i.toNumber(),0,"inflation should be zero");
    });
  });

  it("should not be able to mint 1000 tokens to account[2]", function() {
    return XfundToken.deployed().then(function(instance) {
        token = instance;
        return token.mintToken(accounts[2],1000);
    }).then(assert.fail)
    .catch(function(err) {
        assert.include(err.message,'invalid opcode','minting above the block limit should throw');
    });
  });

  it("should be able to mint 1 tokens to account[2]", function() {
    return XfundToken.deployed().then(function(instance) {
        token = instance;
        return token.mintToken(accounts[2],1);
    }).then(function() {
        return token.balanceOf(accounts[2]);
    }).then(function(bal2) {
        assert.equal(bal2.valueOf(), 1, "accounts[2] balance should be 1");
    });
  });

  it("should lift inflation to 10,000", function() {
    return XfundToken.deployed().then(function(instance) {
        token = instance;
        return token.updateInflationParams(10000,10);
    }).then(function() {
        return token.inflation();
    }).then(function(i) {
        assert.equal(i[1].toNumber(),10000,"block limit should be lifted to 10000");
        assert.equal(i[5].toNumber(),10000,"highest recorded block limit should be lifted to 10000");
    });
  });

  it("should now be able to mint 1000 tokens to account[2]", function() {
    return XfundToken.deployed().then(function(instance) {
        token = instance;
        return token.mintToken(accounts[2],1000);
    }).then(function() {
        return token.balanceOf(accounts[2]);
    }).then(function(bal2) {
        assert.equal(bal2.valueOf(), 1001, "accounts[2] balance should be 1001");
    });
  });

  it("inflation should be alpha*mintedTokens = 181818181*1000/10^9", function() {
    return XfundToken.deployed().then(function(instance) {
        token = instance;
        return token.getInflation();
    }).then(function(i) {
        assert.isAbove(i.toNumber(),0,"inflation should be greater than 0");
        return token.inflation();
    }).then(function(i) {
        assert.equal(i[3].toNumber(), Math.trunc(i[2].toNumber() * 1000 / Math.pow(10,9)));
    });
  });

});

