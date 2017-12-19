// some usefull commands for truffle console
me0 = web3.eth.accounts[0];
me1 = web3.eth.accounts[1];
me2 = web3.eth.accounts[2];
var token = XfundToken.at(XfundToken.address);
var cong = XfundCongress.at(XfundCongress.address);
token.transfer(me1,Math.pow(10,18));
token.transfer(me2,2*Math.pow(10,18));
token.voteOnCongress(me1);
token.voteOnCongress(me2,{from:me1});


// get transaction bytecode
var web3token = web3.eth.contract(XfundToken.abi).at(token.address);
var byteCode = web3token.transfer.getData(me2,101);

// see some block parameters
web3.eth.getBlock("latest")

// send a web3 transaction
var web3send = { from: me0, to: token.address, value: 0, data: '0xa9059cbb000000000000000000000000c5fdf4076b8f3a5357c5e395ab970b5b54098fef0000000000000000000000000000000000000000000000000000000000000065'}web3.eth.sendTransaction(web3send)
