// Rename this file truffle.js and make the changes below
// If testing on ropsten (or other testnet), You need to install npm package truffle-hdwallet-provider locally (at the root of your truffle project)
var HDWalletProvider = require("truffle-hdwallet-provider");
var mnemonic = "wallet words from metamask here";
module.exports = {
  // See <http://truffleframework.com/docs/advanced/configuration>
  // to customize your Truffle configuration!
  networks: {
    development: {
      host: "127.0.0.1",
      port: 9545,
      network_id: "*" // Match any network id
    },
	ropsten: {
      provider: function() {
        return new HDWalletProvider(mnemonic, "https://ropsten.infura.io/<infura key here>",0);
      },
      network_id: 3,
      gas: 4700000
    } 
  }
};
