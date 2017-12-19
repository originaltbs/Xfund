pragma solidity ^0.4.16;

contract owned {
    address public owner;

    function owned() public {
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    function transferOwnership(address newOwner) onlyOwner public {
        owner = newOwner;
    }
}

interface tokenRecipient { function receiveApproval(address _from, uint256 _value, address _token, bytes _extraData) public; }

contract TokenERC20 {
    // Public variables of the token
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    // 18 decimals is the strongly suggested default, avoid changing it
    uint256 public totalSupply;

    // This creates an array with all balances
    mapping (address => uint256) public balanceOf;
    mapping (address => mapping (address => uint256)) public allowance;

    // This generates a public event on the blockchain that will notify clients
    event Transfer(address indexed from, address indexed to, uint256 value);

    // This notifies clients about the amount burnt
    event Burn(address indexed from, uint256 value);

    /**
     * Constrctor function
     *
     * Initializes contract with initial supply tokens to the creator of the contract
     */
    function TokenERC20(
        uint256 initialSupply,
        string tokenName,
        string tokenSymbol
    ) public {
        totalSupply = initialSupply * 10 ** uint256(decimals);  // Update total supply with the decimal amount
        balanceOf[msg.sender] = totalSupply;                // Give the creator all initial tokens
        name = tokenName;                                   // Set the name for display purposes
        symbol = tokenSymbol;                               // Set the symbol for display purposes
    }

    /**
     * Internal transfer, only can be called by this contract
     */
    function _transfer(address _from, address _to, uint _value) internal {
        // Prevent transfer to 0x0 address. Use burn() instead
        require(_to != 0x0);
        // Check if the sender has enough
        require(balanceOf[_from] >= _value);
        // Check for overflows
        require(balanceOf[_to] + _value > balanceOf[_to]);
        // Save this for an assertion in the future
        uint previousBalances = balanceOf[_from] + balanceOf[_to];
        // Subtract from the sender
        balanceOf[_from] -= _value;
        // Add the same to the recipient
        balanceOf[_to] += _value;
        Transfer(_from, _to, _value);
        // Asserts are used to use static analysis to find bugs in your code. They should never fail
        assert(balanceOf[_from] + balanceOf[_to] == previousBalances);
    }

    /**
     * Transfer tokens
     *
     * Send `_value` tokens to `_to` from your account
     *
     * @param _to The address of the recipient
     * @param _value the amount to send
     */
    function transfer(address _to, uint256 _value) public {
        _transfer(msg.sender, _to, _value);
    }

    /**
     * Transfer tokens from other address
     *
     * Send `_value` tokens to `_to` in behalf of `_from`
     *
     * @param _from The address of the sender
     * @param _to The address of the recipient
     * @param _value the amount to send
     */
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success) {
        require(_value <= allowance[_from][msg.sender]);     // Check allowance
        allowance[_from][msg.sender] -= _value;
        _transfer(_from, _to, _value);
        return true;
    }

    /**
     * Set allowance for other address
     *
     * Allows `_spender` to spend no more than `_value` tokens in your behalf
     *
     * @param _spender The address authorized to spend
     * @param _value the max amount they can spend
     */
    function approve(address _spender, uint256 _value) public
        returns (bool success) {
        allowance[msg.sender][_spender] = _value;
        return true;
    }

    /**
     * Set allowance for other address and notify
     *
     * Allows `_spender` to spend no more than `_value` tokens in your behalf, and then ping the contract about it
     *
     * @param _spender The address authorized to spend
     * @param _value the max amount they can spend
     * @param _extraData some extra information to send to the approved contract
     */
    function approveAndCall(address _spender, uint256 _value, bytes _extraData)
        public
        returns (bool success) {
        tokenRecipient spender = tokenRecipient(_spender);
        if (approve(_spender, _value)) {
            spender.receiveApproval(msg.sender, _value, this, _extraData);
            return true;
        }
    }

    /**
     * Destroy tokens
     *
     * Remove `_value` tokens from the system irreversibly
     *
     * @param _value the amount of money to burn
     */
    function burn(uint256 _value) public returns (bool success) {
        require(balanceOf[msg.sender] >= _value);   // Check if the sender has enough
        balanceOf[msg.sender] -= _value;            // Subtract from the sender
        assert(totalSupply >= _value);
        totalSupply -= _value;                      // Updates totalSupply
        Burn(msg.sender, _value);
        return true;
    }

    /**
     * Destroy tokens from other account
     *
     * Remove `_value` tokens from the system irreversibly on behalf of `_from`.
     *
     * @param _from the address of the sender
     * @param _value the amount of money to burn
     */
    function burnFrom(address _from, uint256 _value) public returns (bool success) {
        require(balanceOf[_from] >= _value);                // Check if the targeted balance is enough
        require(_value <= allowance[_from][msg.sender]);    // Check allowance
        balanceOf[_from] -= _value;                         // Subtract from the targeted balance
        allowance[_from][msg.sender] -= _value;             // Subtract from the sender's allowance
        assert(totalSupply >= _value);
        totalSupply -= _value;                              // Update totalSupply
        Burn(_from, _value);
        return true;
    }
}

/******************************************/
/*       ADVANCED TOKEN STARTS HERE       */
/******************************************/

contract XfundToken is owned, TokenERC20 {

    bool public tokenActive = true;
    address public supersedingToken;

    mapping (address => bool) public frozenAccount;

    mapping (address => uint256) public votesReceived;
    mapping (address => address) public voteList;
    uint256 public totalVotedTokens;
    uint256 public initialSupply;

    struct InflationData {
        uint256 lastUpdate;
        uint256 blockRewardLimit; // limit of new tokens per block
		uint256 alpha; // standard alpha parameter for exponential-moving-average (EMA) (scaled by 10**9)
        uint256 averageBlockReward; // estimate of recent new tokens per block using EMA
        uint256 blocksToAverage;
        uint256 highestLimit;
    }
    InflationData public inflation;
    uint256 minBlocksToAverage = 5;

    /* This generates a public event on the blockchain that will notify clients */
    event FrozenFunds(address target, bool frozen);

    /* Initializes contract with initial supply tokens to the creator of the contract */
    function XfundToken(
        uint256 _initialSupply,
        string tokenName,
        string tokenSymbol,
        uint256 blockRewardLimit,
        uint256 blocksToAverage
    ) TokenERC20(_initialSupply, tokenName, tokenSymbol) public { 
        initialSupply = _initialSupply;
        inflation = InflationData({lastUpdate: block.number, blockRewardLimit: blockRewardLimit, highestLimit: blockRewardLimit, blocksToAverage: blocksToAverage, alpha: 2 * 10**9 / (blocksToAverage + 1), averageBlockReward: 0});
    }

    /// @notice Turn off token transfers in case of emergency
    function disableToken(address _newToken) onlyOwner public {
        tokenActive = false;
        supersedingToken = _newToken;
    }
    /// @notice Re-activate token transfers
    function enableToken() onlyOwner public {
        tokenActive = true;
    }

    /* Internal transfer, only can be called by this contract */
    function _transfer(address _from, address _to, uint _value) internal {
        require(tokenActive); 								// This token contract still active
        require (_to != 0x0);                               // Prevent transfer to 0x0 address. Use burn() instead
        require (balanceOf[_from] >= _value);               // Check if the sender has enough
        require (balanceOf[_to] + _value > balanceOf[_to]); // Check for overflows
        require(!frozenAccount[_from]);                     // Check if sender is frozen
        require(!frozenAccount[_to]);                       // Check if recipient is frozen
        balanceOf[_from] -= _value;                         // Subtract from the sender
        balanceOf[_to] += _value;                           // Add the same to the recipient
        if (voteList[_from] != 0x0) {
            votesReceived[voteList[_from]] -= _value;
            totalVotedTokens -= _value;
            if (balanceOf[_from] == 0) { // if the vote is 0, unvote them
                voteList[_from] = 0x0;
            }
        }
        if (voteList[_to] != 0x0) {
            votesReceived[voteList[_to]] += _value;
            totalVotedTokens += _value;
        }
        Transfer(_from, _to, _value);
    }

    /// @notice Vote for `_nominee` to enter congress
    /// @param _nominee Ethereum address of person you are voting for
    function voteOnCongress(address _nominee) public {
        require(_nominee != 0x0);
        require(!frozenAccount[msg.sender]);                       // Check if recipient is frozen
        require(voteList[msg.sender] == 0x0); // can't vote a second time, unvote first
        require(balanceOf[msg.sender] > 0);
        votesReceived[_nominee] += balanceOf[msg.sender];
        voteList[msg.sender] = _nominee;
        totalVotedTokens += balanceOf[msg.sender];
    }

    /// @notice Remove your vote, so that you can vote for someone else
    function unvoteCongress() public {
        _unvoteCongress(msg.sender);
    }

    /* Internal function can only be called by other functions in this contract */
    function _unvoteCongress(address _account) internal {
		address nominee = voteList[_account];
        require(nominee != 0x0);
        assert(votesReceived[nominee] >= balanceOf[_account]);
        assert(totalVotedTokens >= balanceOf[_account]);
        votesReceived[nominee] -= balanceOf[_account];
        totalVotedTokens -= balanceOf[_account];
        voteList[_account] = 0x0;
    }

    /// @notice Create `_mintedAmount` tokens and send it to `_recipient`
    /// @param _recipient Address to receive the tokens
    /// @param _mintedAmount the amount of tokens it will receive
    function mintToken(address _recipient, uint256 _mintedAmount) onlyOwner public {
        require(tokenActive);
        updateInflation(_mintedAmount);
        require(inflation.averageBlockReward < inflation.blockRewardLimit);
        require(_mintedAmount < inflation.blockRewardLimit);
        balanceOf[_recipient] += _mintedAmount;
        if (voteList[_recipient] != 0x0) {
            votesReceived[voteList[_recipient]] += _mintedAmount;
            totalVotedTokens += _mintedAmount;
        }
        totalSupply += _mintedAmount;
        Transfer(0, this, _mintedAmount);
        Transfer(this, _recipient, _mintedAmount);
    }

    /// @notice Update token inflation parameters with `_blockRewardLimit` and `_blocksToAverage`
    /// @param _blockRewardLimit Prohibit minting new tokens at an average rate above this limit
    /// @param _blocksToAverage Number of blocks to include in EMA of token inflation
    function updateInflationParams(uint _blockRewardLimit, uint _blocksToAverage) onlyOwner public {
        require(_blocksToAverage > minBlocksToAverage);
        if (_blockRewardLimit > inflation.highestLimit) inflation.highestLimit = _blockRewardLimit;
        if (_blockRewardLimit > 0) inflation.blockRewardLimit = _blockRewardLimit;
        if (_blocksToAverage > 0) inflation.blocksToAverage = _blocksToAverage;
		inflation.alpha = 2 * 10**9 / (inflation.blocksToAverage + 1);
    }

    /// @notice Track inflation of token supply each time `_newTokens` tokens are minted
    /// @param _newTokens Number of new tokens created
    function updateInflation(uint _newTokens) internal {
        uint256 elapsedBlocks = block.number - inflation.lastUpdate;
        for (uint16 i=0; i<elapsedBlocks; i++) {
            inflation.averageBlockReward = (10**9 - inflation.alpha) * inflation.averageBlockReward / 10**9;
        }
        if (elapsedBlocks > 0) {
            inflation.averageBlockReward += (inflation.alpha * _newTokens) / 10**9;
            //inflation.averageBlockReward = (inflation.alpha * _newTokens + (10**9 - inflation.alpha) * inflation.averageBlockReward) / 10**9;
        } else {
            inflation.averageBlockReward += (inflation.alpha * _newTokens) / 10**9;
        }
        inflation.lastUpdate = block.number;
    }
    /// @notice Let anyone update the average inflation per block
	function updateInflationPublic() public {
		updateInflation(0);
	}
    /// @notice Get current average new tokens minted per block
    function getInflation() constant public returns (uint256 averageBlockReward) {
        return inflation.averageBlockReward;
    }

    /// @notice `_freeze? Prevent | Allow` `_target` from sending & receiving tokens
    /// @param _target Address to be frozen
    /// @param _freeze either to freeze it or not
    function freezeAccount(address _target, bool _freeze) onlyOwner public {
        frozenAccount[_target] = _freeze;
        FrozenFunds(_target, _freeze);
        if (_freeze && voteList[_target] != 0x0) {
            _unvoteCongress(_target);
        }
    }

	// A vulernability of the approve method when resetting an allowance in the ERC20 standard was identified by
  	// Mikhail Vladimirov and Dmitry Khovratovich here:
  	// https://docs.google.com/document/d/1YLPtQxZu1UAvO9cZ1O2RPXBbT0mooh4DYKjA_jp-RLM
  	// It's better to use this method to reset an allowance as it is not susceptible to double-withdraws by the approvee.
  	/// @param _spender The address to approve
  	/// @param _currentAllowance The previous allowance approved, which can be retrieved with allowance(msg.sender, _spender)
  	/// @param _newAllowance The new allowance to approve, this will replace the _currentAllowance
  	/// @return bool Whether the approval was a success (see ERC20's `approve`)
  	function secureApprove(address _spender, uint256 _currentAllowance, uint256 _newAllowance) public returns(bool) {
		if (allowance[msg.sender][_spender] != _currentAllowance) {
			return false;
    	}
		return approve(_spender, _newAllowance);
	}

}
