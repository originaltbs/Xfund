var GystToken = artifacts.require("./XfundToken.sol");
var GystCongress = artifacts.require("./XfundCongress.sol");

module.exports = function(deployer) {
  //deployer.link(ConvertLib, MetaCoin);
  deployer.deploy(XfundToken, 1000, "Xfund 2017", "XF17", 5, 10).then( function() { 
      return deployer.deploy(XfundCongress, 1, 2, 50, XfundToken.address);
  });
};
